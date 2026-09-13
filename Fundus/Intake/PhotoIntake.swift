import UIKit

/// Was aus einem Foto herauskam.
struct IntakeResult: Equatable {
    var proposals: [Proposal] = []
    /// Dinge, die das Modell gesehen, aber nicht bestimmen konnte. Steht dem Nutzer
    /// im Prüfschritt vor Augen, damit er weiß, wo er selbst nachsehen muss.
    var unreadable: [String] = []
    /// Welches Modell gelesen hat. Wandert in die Herkunft jedes angenommenen
    /// Eintrags.
    var model: String = ""
    /// Was das Gerät selbst aus Strichcodes entziffert hat. Steht im Prüfschritt
    /// auch dann zur Verfügung, wenn das Modell keinen davon zugeordnet hat.
    var scannedCodes: [ItemCode] = []

    var isEmpty: Bool { proposals.isEmpty && unreadable.isEmpty }
}

/// Ein Foto in Vorschläge verwandeln.
///
/// Der Name des Typs sagt es schon: Vorschläge. Nichts aus dieser Datei landet im
/// Bestand, ohne dass der Nutzer es bestätigt hat. Das ist die wichtigste
/// Entscheidung der ganzen App und keine Höflichkeit — ein Modell, das ein Regal
/// liest, verzählt sich, fasst zusammen und liest Etiketten falsch. Ein Bestand, der
/// Modellausgabe stillschweigend aufnimmt, ist schlechter als keiner, weil man ihm
/// glaubt. Der Prüfschritt ist der Preis dafür, dass man der App vertrauen kann, und
/// er ist billig: eine Liste mit Häkchen, zehn Sekunden.
struct PhotoIntake {
    let client: ModelClient

    func read(image: UIImage, placePath: String?, existingNames: [String],
              hint: String, onDelta: (@Sendable (String) -> Void)? = nil) async throws -> IntakeResult {
        guard let attachment = ImageAttachment.make(from: image) else {
            throw ModelError.transport("Das Bild ließ sich nicht aufbereiten.")
        }

        // Vor dem bezahlten Aufruf: die Strichcodes entziffert das Gerät selbst.
        // Kostet nichts, braucht keine Leitung, und das Ergebnis ist richtig statt
        // wahrscheinlich.
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

    /// Nachsichtig gelesen, weil die Antwort von einem beliebigen Modell kommt.
    ///
    /// `quantity` kann als Zahl, als Zeichenkette („8“), als Fließkommazahl oder als
    /// `null` erscheinen; Modelle sind da nicht einheitlich, und einen Fund an einem
    /// Anführungszeichen zu verlieren wäre ein bezahlter Aufruf für nichts. Was
    /// dagegen nicht nachsichtig behandelt wird, ist ein fehlender Name: ein Eintrag
    /// ohne Namen ist kein Eintrag.
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

            // Das Modell nennt dasselbe Ding manchmal zweimal — zwei Fächer, ein
            // Blick. Zusammenlegen statt zwei Häkchen anbieten, die derselbe Eintrag
            // sind: der Nutzer soll im Prüfschritt Dinge sehen, nicht Zeilen.
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

    /// Die Kennung eines Eintrags, mit dem Sicherheitsnetz gegen erfundene EANs.
    ///
    /// Nennt das Modell eine Nummer, die das Gerät selbst dekodiert hat, gilt sie als
    /// `scanned` — dann ist sie belegt. Nennt es eine EAN, die **nicht** unter den
    /// dekodierten ist, ist das kein Fund, sondern eine erfundene Ziffernfolge: einen
    /// Strichcode kann man nicht mit den Augen lesen. Solche werden verworfen.
    /// Herstellernummern und Seriennummern dagegen stehen als Klartext auf dem Ding
    /// und dürfen abgelesen werden — sie behalten `origin: .read`.
    static func code(from raw: [String: Any], scannedValues: Set<String>,
                     scannedCodes: [ItemCode]) -> ItemCode? {
        let value = string(raw["code"])
        guard !value.isEmpty, value.lowercased() != "null" else { return nil }

        if let exact = scannedCodes.first(where: { $0.value == value }) { return exact }

        let kind = kind(from: string(raw["code_type"]))
        if kind == .ean || kind == .upc {
            // Eine EAN, die der Dekoder nicht gesehen hat, hat das Modell erfunden
            // oder von den Ziffern unter den Balken abgeschrieben — und gerade dort
            // ist eine verwechselte Ziffer nicht zu bemerken.
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
            // Eine Kommazahl als Stückzahl ist ein Missverständnis des Modells, kein
            // Wert. Abgeschnitten statt gerundet: aus 2,7 Dosen werden 2 sichere,
            // nicht 3 behauptete.
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
