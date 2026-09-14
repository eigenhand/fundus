import Foundation

extension KeyedDecodingContainer {

    /// Wie `decodeIfPresent`, aber ein unbekannter Wert ist kein Fehler.
    ///
    /// `decodeIfPresent` wirft bei einer Aufzählung, deren Rohwert sie nicht kennt —
    /// und das `?? standard`, das überall daneben steht, läuft dann nie. Der Schaden
    /// trifft nicht das eine Feld, sondern die ganze Datei: ein einziges
    /// `"kind": "nfc"` aus einer neueren Fassung der App, und der gesamte Bestand
    /// gilt als unlesbar.
    ///
    /// Das ist der falsche Tausch. Eine Kennung, deren Art diese Fassung nicht kennt,
    /// ist eine Kennung mit unbekannter Art — nicht Grund, hundert Einträge zu
    /// verlieren. Dieselbe Überlegung wie bei `origin` und `match`: was nicht lesbar
    /// ist, fällt auf die Vorgabe zurück und steht weiter da.
    ///
    /// Gefunden durch einen Test, der eine ausgedachte Einstellung einlas.
    func decodeLenient<T>(_ type: T.Type, forKey key: Key) -> T?
    where T: RawRepresentable & Decodable, T.RawValue: Decodable {
        guard let raw = try? decodeIfPresent(T.RawValue.self, forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}
