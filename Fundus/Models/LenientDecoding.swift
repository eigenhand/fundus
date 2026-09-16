import Foundation

extension KeyedDecodingContainer {

    /// Like `decodeIfPresent`, but an unknown value is not an error.
    ///
    /// `decodeIfPresent` throws on an enum whose raw value it does not know — and the
    /// `?? standard` that stands beside it everywhere then never runs. The damage does
    /// not hit the one field but the whole file: a single `"kind": "nfc"` from a newer
    /// version of the app, and the entire inventory counts as unreadable.
    ///
    /// That is the wrong trade. An identifier whose kind this version does not know is
    /// an identifier of unknown kind — not a reason to lose a hundred entries. The same
    /// reasoning as for `origin` and `match`: what cannot be read falls back on the
    /// default and stays there.
    ///
    /// Found by a test that read in an invented settings file.
    func decodeLenient<T>(_ type: T.Type, forKey key: Key) -> T?
    where T: RawRepresentable & Decodable, T.RawValue: Decodable {
        guard let raw = try? decodeIfPresent(T.RawValue.self, forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}
