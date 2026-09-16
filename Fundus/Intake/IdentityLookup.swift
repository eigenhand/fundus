import Foundation

/// Turning an identifier into a choice — not into a verdict.
///
/// Two passes instead of tool calls: the model first reads the photo and names the
/// identifiers it can decipher, then the app searches for them and has the model
/// distil the nearest possibilities out of the hits. Tool calls would be the more
/// elegant route and the wrong one — they demand a provider layer that Faden has and
/// this app deliberately does not, and they give away control over the number of paid
/// calls. Here it is capped and countable.
///
/// The second decision matters more: a find from the search **replaces nothing**. It
/// arrives as a suggestion beside the model's own reading, with the number that
/// produced it. The reason is a chain with three fallible links — a blurred sticker, a
/// model that confuses characters, a search engine that answers something to every
/// string. At the end of it stands a precise product name that looks more reliable
/// than anything else in the inventory and is the least so. Make it visible rather
/// than smoothing it over.
///
/// What has changed is *who* judges the chain. Before, the model was meant to decide
/// whether the hits fitted the number and to stay silent when in doubt — for a number
/// read by eye the doubt is the normal case, and what came out was usually nothing,
/// even though the right part stood among the hits. Now the app presents up to three
/// possibilities, and whoever holds the thing in their hand decides.
struct IdentityLookup {
    let model: ModelClient
    let search: SearchClient

    /// How many identifiers are looked up per shot.
    ///
    /// Capped, because a case holding forty components would otherwise set off forty
    /// searches and forty model calls — for a shot the user may yet discard. Whoever
    /// wants more looks them up one at a time on the entry.
    static let maxPerIntake = 8

    /// Looks the suggestions' identifiers up and attaches the result.
    ///
    /// Fails one at a time, not as a whole: a search without hits or a timeout must not
    /// cost the shot, which has already been paid for.
    func resolve(_ proposals: [Proposal],
                 onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> [Proposal] {
        var out = proposals
        let targets = proposals.indices.filter {
            proposals[$0].code?.isSearchable == true && proposals[$0].code?.lookup == nil
        }
        let capped = Array(targets.prefix(Self.maxPerIntake))
        guard !capped.isEmpty else { return out }

        for (done, index) in capped.enumerated() {
            onProgress?(done, capped.count)
            guard let code = out[index].code else { continue }
            // Take the name out first: reading `out[index]` while writing into the same
            // element is an overlapping access.
            let name = out[index].name
            out[index].code?.lookup = await resolveOne(code: code, itemName: name)
        }
        onProgress?(capped.count, capped.count)
        return out
    }

    /// One identifier: search, then have the choice distilled.
    ///
    /// Always returns something, and that is deliberate. Before, every failure came out
    /// as `nil` — a dropped connection, a model that wrote no JSON and "nothing fits"
    /// all alike. In the interface that was an empty space under the number with
    /// nothing to suggest that anybody had searched at all. Now the reason stands
    /// there.
    func resolveOne(code: ItemCode, itemName: String) async -> CodeLookup {
        let query = Self.query(for: code, itemName: itemName)
        let failure = CodeLookup(query: query, failed: true)

        let hits: [SearchClient.Hit]
        do {
            hits = try await search.search(query)
        } catch {
            return failure
        }
        // No hit is a result, not an error: the number appears nowhere in that form.
        guard !hits.isEmpty else { return CodeLookup(query: query) }

        let reply: String
        do {
            reply = try await model.ask(
                prompt: IntakePrompt.lookupMessage(code: code, itemName: itemName, hits: hits),
                system: IntakePrompt.lookupSystem)
        } catch {
            return failure
        }
        guard let object = JSONSnippet.firstObject(in: reply) else { return failure }
        return Self.parse(object, code: code, query: query, hits: hits)
            ?? CodeLookup(query: query)
    }

    /// The search query.
    ///
    /// The identifier always used to stand in quotation marks here, so that the search
    /// engine would not "correct" it. For a decoded EAN that is right: it is exact to
    /// the character, and falling back on a similar product would be an error.
    ///
    /// For a number read by eye it was the cause of the problem. `42BYGH3701-B-89S80`
    /// in quotation marks finds nothing when the motor says `…-B-80S80` — and "nothing"
    /// was then the result, even though a person would have recognised the motor in two
    /// seconds. Without the quotation marks the search finds the series, and the user
    /// picks out their own variant. Running into nothing was meant as a safeguard; in
    /// truth it only handed the work back.
    static func query(for code: ItemCode, itemName: String) -> String {
        let hint = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch code.origin {
        case .scanned:
            return "\"\(code.value)\""
        case .read:
            return hint.isEmpty ? code.value : "\(code.value) \(hint)"
        }
    }

    /// Turning the model's answer into a list to choose from.
    ///
    /// One check the app makes itself rather than taking it on trust: `exact` means the
    /// identifier appears **verbatim** in a hit, and that can be looked up. If it does
    /// not, the suggestion is downgraded to `near`. A model that wants to please
    /// otherwise grades every hit as a direct hit — and that label is exactly what
    /// decides how much trust the row in the interface is given.
    static func parse(_ object: [String: Any], code: ItemCode, query: String,
                      hits: [SearchClient.Hit]) -> CodeLookup? {
        let rows = object["candidates"] as? [[String: Any]]
            // The old, singular form too, in case the model falls back into it.
            ?? (object["title"] is String ? [object] : [])

        let literal = hits.contains {
            ($0.title + " " + $0.snippet + " " + $0.url)
                .range(of: code.value, options: .caseInsensitive) != nil
        }

        var out: [CodeCandidate] = []
        for row in rows {
            let title = (row["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // No title means: this suggestion is not one. It does not get padded out.
            guard !title.isEmpty, title.lowercased() != "null" else { continue }

            let sourceURL = (row["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matching = hits.first { $0.url == sourceURL } ?? hits.first

            var match = CodeCandidate.Match(
                rawValue: (row["match"] as? String)?.lowercased() ?? "") ?? .family
            if match == .exact, !literal { match = .near }

            out.append(CodeCandidate(
                title: title,
                summary: (row["summary"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourceURL: sourceURL.isEmpty ? (matching?.url ?? "") : sourceURL,
                sourceName: matching?.source ?? "",
                match: match,
                codeSeen: seen(row["code_seen"], unlike: code.value)))
            if out.count == CodeLookup.maxCandidates { break }
        }

        guard !out.isEmpty else { return nil }
        return CodeLookup(query: query, candidates: out)
    }

    /// The number from the hit — but only when it differs from the one that was read.
    /// Writing the same number out again beside it is noise.
    private static func seen(_ raw: Any?, unlike value: String) -> String {
        let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty, s.lowercased() != "null",
              s.compare(value, options: .caseInsensitive) != .orderedSame else { return "" }
        return s
    }
}
