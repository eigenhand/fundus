import UIKit

/// What came out of a photo.
struct IntakeResult: Equatable {
    var proposals: [Proposal] = []
    /// Things the model saw but could not identify. It stands in front of the user in
    /// the checking step so that they know where to look themselves.
    var unreadable: [String] = []
    /// Which model did the reading. Travels into the provenance of every accepted
    /// entry.
    var model: String = ""
    /// What the device itself deciphered from barcodes. Available in the checking step
    /// even when the model assigned none of them.
    var scannedCodes: [ItemCode] = []

    var isEmpty: Bool { proposals.isEmpty && unreadable.isEmpty }
}

/// Turning a photo into suggestions.
///
/// The name of the type says it already: suggestions. Nothing from this file lands in
/// the inventory without the user having confirmed it. That is the most important
/// decision in the whole app and not a courtesy — a model reading a shelf miscounts,
/// lumps things together and reads labels wrong. An inventory that silently takes in
/// model output is worse than none, because it gets believed. The checking step is the
/// price of being able to trust the app, and it is cheap: a list with ticks, ten
/// seconds.
struct PhotoIntake {
    let client: ModelClient

    func read(image: UIImage, placePath: String?, existingNames: [String],
              hint: String, onDelta: (@Sendable (String) -> Void)? = nil) async throws -> IntakeResult {
        guard let attachment = ImageAttachment.make(from: image) else {
            throw ModelError.transport("Das Bild ließ sich nicht aufbereiten.")
        }

        // Before the paid call: the device deciphers the barcodes itself. Costs
        // nothing, needs no connection, and the result is correct rather than likely.
        let scanned = await BarcodeScanner.scan(image)

        let reply = try await client.read(
            imageJPEG: attachment.jpeg,
            prompt: IntakePrompt.message(placePath: placePath, existingNames: existingNames,
                                         hint: hint, scannedCodes: scanned),
            system: IntakePrompt.system,
            onDelta: onDelta)

        guard let object = JSONSnippet.firstObject(in: reply) else {
            throw ModelError.notJSON(String(reply.prefix(200)))
        }
        var result = Self.parse(object, scannedCodes: scanned)
        result.model = client.config.model
        result.scannedCodes = scanned
        return result
    }

    /// Read leniently, because the answer comes from an arbitrary model.
    ///
    /// `quantity` can turn up as a number, as a string ("8"), as a floating-point value
    /// or as `null`; models are not consistent about it, and losing a find to a
    /// quotation mark would be a paid call for nothing. What is *not* treated leniently
    /// is a missing name: an entry without a name is not an entry.
    static func parse(_ object: [String: Any],
                      scannedCodes: [ItemCode] = []) -> IntakeResult {
        var result = IntakeResult()
        let scannedValues = Set(scannedCodes.map(\.value))

        for raw in object["items"] as? [[String: Any]] ?? [] {
            guard let name = (raw["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { continue }

            var proposal = Proposal(name: name, quantity: quantity(from: raw["quantity"]))
            proposal.unit = string(raw["unit"])
            proposal.note = string(raw["note"])
            proposal.code = code(from: raw, scannedValues: scannedValues,
                                 scannedCodes: scannedCodes)

            // The model sometimes names the same thing twice — two compartments, one
            // glance. Merge rather than offering two ticks that are the same entry: in
            // the checking step the user should see things, not rows.
            if let i = result.proposals.firstIndex(where: {
                Item.normalise($0.name) == Item.normalise(name)
            }) {
                if let extra = proposal.quantity {
                    result.proposals[i].quantity = (result.proposals[i].quantity ?? 0) + extra
                }
                if !proposal.note.isEmpty, result.proposals[i].note.isEmpty {
                    result.proposals[i].note = proposal.note
                }
                if result.proposals[i].code == nil { result.proposals[i].code = proposal.code }
                continue
            }
            result.proposals.append(proposal)
        }

        result.unreadable = (object["unreadable"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return result
    }

    /// The identifier of an entry, with the safety net against invented EANs.
    ///
    /// If the model names a number the device decoded itself, it counts as `scanned` —
    /// then it is attested. If it names an EAN that is **not** among the decoded ones,
    /// that is not a find but an invented row of digits: a barcode cannot be read by
    /// eye. Those get discarded. Manufacturer part numbers and serial numbers, by
    /// contrast, stand in plain text on the thing and may be read — they keep
    /// `origin: .read`.
    static func code(from raw: [String: Any], scannedValues: Set<String>,
                     scannedCodes: [ItemCode]) -> ItemCode? {
        let value = string(raw["code"])
        guard !value.isEmpty, value.lowercased() != "null" else { return nil }

        if let exact = scannedCodes.first(where: { $0.value == value }) { return exact }

        let kind = kind(from: string(raw["code_type"]))
        if kind == .ean || kind == .upc {
            // An EAN the decoder did not see was either invented by the model or copied
            // from the digits under the bars — and it is precisely there that a
            // confused digit goes unnoticed.
            guard scannedValues.contains(value) else { return nil }
        }
        return ItemCode(value: value, kind: kind, origin: .read)
    }

    static func kind(from s: String) -> ItemCode.Kind {
        switch s.lowercased() {
        case "ean", "ean13", "ean8", "gtin": return .ean
        case "upc":                          return .upc
        case "mpn", "manufacturer", "typ", "type": return .manufacturer
        case "serial", "seriennummer", "sn": return .serial
        default:                             return .unknown
        }
    }

    private static func string(_ any: Any?) -> String {
        (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func quantity(from any: Any?) -> Int? {
        switch any {
        case let n as Int: return n > 0 ? n : nil
        case let d as Double:
            // A decimal as a piece count is a misunderstanding on the model's part, not
            // a value. Truncated rather than rounded: 2.7 tins become 2 certain ones,
            // not 3 asserted ones.
            let i = Int(d)
            return i > 0 ? i : nil
        case let s as String:
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let i = Int(cleaned), i > 0 { return i }
            if let d = Double(cleaned), Int(d) > 0 { return Int(d) }
            return nil
        default: return nil
        }
    }
}
