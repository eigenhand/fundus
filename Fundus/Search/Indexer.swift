import Foundation

/// The state of the search index — and the work of pulling it straight again.
///
/// The same classification as in Faden's memory, and for the same reason: a vector
/// without an origin is as good as a wrong one. Whoever switches the source in the
/// settings from "on the device" to an endpoint has thereby made every existing vector
/// unusable — not broken but incomparable, which is worse, because it keeps producing
/// numbers. The stamp makes that visible, this file makes it countable.
enum Indexer {

    struct Status: Equatable {
        /// Vector present and from the configured model — usable.
        var usable = 0
        /// Vector present, but from a different model or with a different dimension.
        /// Arithmetically unusable; has to be embedded again.
        var foreign = 0
        /// No vector at all yet.
        var missing = 0
        /// Which models are in the index, with counts — so that it is visible *what* is
        /// in there, rather than only that something does not fit.
        var byModel: [String: Int] = [:]
        /// The dimension the configured model has settled on.
        var dimension: Int?

        var total: Int { usable + foreign + missing }
        var needsWork: Int { foreign + missing }
        var isClean: Bool { needsWork == 0 }
    }

    /// The dimension the configured model actually delivers here.
    ///
    /// Not from a table but from the inventory: providers change the length under the
    /// same model name. The commonest wins; outliers thereby count as foreign and get
    /// fetched again.
    static func dominantDimension(_ items: [Item], model: String) -> Int? {
        let wanted = EmbeddingStamp.normalise(model)
        var counts: [Int: Int] = [:]
        for stamp in items.compactMap(\.embeddingStamp)
        where EmbeddingStamp.normalise(stamp.model) == wanted {
            counts[stamp.dimension, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    static func status(_ items: [Item], model: String) -> Status {
        var status = Status()
        status.dimension = dominantDimension(items, model: model)

        for item in items {
            guard item.embedding != nil else { status.missing += 1; continue }
            if let stamp = item.embeddingStamp {
                status.byModel[stamp.model, default: 0] += 1
                if stamp.matches(model: model, dimension: status.dimension) {
                    status.usable += 1
                } else {
                    status.foreign += 1
                }
            } else {
                // Vector without a stamp: from a version predating this marking.
                status.byModel[String(localized: "unbekannt"), default: 0] += 1
                status.foreign += 1
            }
        }
        return status
    }

    static func isUsable(_ item: Item, model: String, dimension: Int?) -> Bool {
        guard item.embedding != nil, let stamp = item.embeddingStamp else { return false }
        return stamp.matches(model: model, dimension: dimension)
    }

    /// Everything that still needs a vector for the configured model — missing as well
    /// as foreign. The queue of catching up.
    ///
    /// Oldest first, so that an interrupted run carries on next time where it left off
    /// instead of always finding the same ones at the front.
    static func needingEmbedding(_ items: [Item], model: String, limit: Int = .max) -> [Item] {
        let dimension = dominantDimension(items, model: model)
        return items
            .filter { !isUsable($0, model: model, dimension: dimension) }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// The mean vector of the usable entries.
    ///
    /// Against the anisotropy of the local model: there every cosine value lies above
    /// 0.95, because the vectors sit in a narrow cone. Subtract the mean vector and the
    /// values spread out again over the range in which a threshold means something. It
    /// does not affect the ranking — measured in Faden too; it only restores the
    /// meaning of the limit.
    ///
    /// Below ten entries nothing is centred: the mean vector would then mostly be the
    /// one entry you are looking for, and subtracting it would compute away exactly the
    /// hit you wanted.
    static let minimumForCentering = 10

    static func centroid(_ items: [Item], model: String) -> [Float]? {
        let dimension = dominantDimension(items, model: model)
        let vectors = items
            .filter { isUsable($0, model: model, dimension: dimension) }
            .compactMap(\.embedding)
        guard vectors.count >= minimumForCentering, let width = vectors.first?.count else { return nil }

        var sum = [Double](repeating: 0, count: width)
        var counted = 0
        for v in vectors where v.count == width {
            for i in 0 ..< width { sum[i] += Double(v[i]) }
            counted += 1
        }
        guard counted > 0 else { return nil }
        return sum.map { Float($0 / Double(counted)) }
    }

    /// Subtracts the mean vector. Lengths that do not match are left untouched — a
    /// half-centred vector would be worse than an uncentred one.
    static func centered(_ vector: [Float], by centroid: [Float]?) -> [Float] {
        guard let centroid, centroid.count == vector.count else { return vector }
        return zip(vector, centroid).map(-)
    }
}
