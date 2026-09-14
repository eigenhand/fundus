import Foundation

/// Aus Wörtern Zahlen machen, so wie CLIP es tut.
///
/// SAM 3 nimmt keinen Text entgegen, sondern Token-Nummern: `token_ids [1, 32]`. Der
/// Textturm ist wörtlich CLIPs — `vocab_size 49408`, `model_type clip_text_model` —
/// also gilt CLIPs Byte-Paar-Kodierung, und zwar genau. Ein Token daneben ist nicht
/// ein bisschen daneben, sondern ein anderes Wort: bei der ersten Messung habe ich
/// versehentlich 3739 statt 4055 geschickt und damit nach „halloween" gesucht statt
/// nach „flower". Das Ergebnis war 0,004 statt 0,908.
///
/// Deshalb sind die Prüfwerte aus einer Referenzimplementierung erzeugt und nicht aus
/// dem Kopf. Die Tabellen kommen mit dem Modell und liegen nicht im Bundle: 1,5 MB
/// für eine App, die 1,7 MB gross ist.
struct ClipTokenizer {

    /// Wie lang die Folge ist, die SAM 3 erwartet. Nicht 77 wie bei CLIP sonst —
    /// `max_position_embeddings` steht in dieser Konfiguration auf 32.
    static let contextLength = 32
    static let startOfText = 49406
    static let endOfText = 49407

    private let vocabulary: [String: Int]
    /// Rang jedes Paares. Kleiner Rang heisst: zuerst zusammenfassen.
    private let ranks: [Pair: Int]
    private let byteEncoder: [UInt8: String]

    struct Pair: Hashable {
        let first: String
        let second: String
    }

    enum Failure: Error {
        case missingTables
    }

    init(vocabulary: URL, merges: URL) throws {
        guard let vocabularyData = try? Data(contentsOf: vocabulary),
              let table = try? JSONDecoder().decode([String: Int].self, from: vocabularyData),
              let mergeText = try? String(contentsOf: merges, encoding: .utf8)
        else { throw Failure.missingTables }

        self.vocabulary = table
        var ranks: [Pair: Int] = [:]
        // Die erste Zeile ist eine Versionsangabe, kein Paar.
        for (index, line) in mergeText.split(separator: "\n").dropFirst().enumerated() {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            ranks[Pair(first: String(parts[0]), second: String(parts[1]))] = index
        }
        self.ranks = ranks
        self.byteEncoder = Self.bytesToUnicode()
    }

    /// Die Token-Nummern für einen Suchbegriff, auf `contextLength` aufgefüllt.
    func encode(_ text: String) -> [Int32] {
        var ids: [Int32] = [Int32(Self.startOfText)]
        for piece in Self.split(Self.clean(text)) {
            // Erst auf Bytes, dann auf die Ersatzzeichen: so bleibt ein Umlaut zwei
            // Zeichen, wie CLIP es gelernt hat.
            let encoded = Array(piece.utf8).map { byteEncoder[$0] ?? "" }.joined()
            for token in merge(encoded) {
                if let id = vocabulary[token] { ids.append(Int32(id)) }
            }
        }
        ids.append(Int32(Self.endOfText))

        if ids.count > Self.contextLength {
            ids = Array(ids.prefix(Self.contextLength))
            // Abgeschnitten heisst nicht: ohne Schluss. Das letzte Token bleibt das
            // Ende, sonst laeuft der Textturm in eine Folge ohne Abschluss.
            ids[Self.contextLength - 1] = Int32(Self.endOfText)
        }
        return ids + Array(repeating: 0, count: Self.contextLength - ids.count)
    }

    // MARK: Die Byte-Paar-Kodierung

    private func merge(_ token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        var word = token.map(String.init)
        word[word.count - 1] += "</w>"
        guard word.count > 1 else { return word }

        while true {
            var bestRank = Int.max
            var best: Pair?
            for i in 0 ..< word.count - 1 {
                let pair = Pair(first: word[i], second: word[i + 1])
                if let rank = ranks[pair], rank < bestRank { bestRank = rank; best = pair }
            }
            guard let best else { break }

            var merged: [String] = []
            var i = 0
            while i < word.count {
                if i < word.count - 1, word[i] == best.first, word[i + 1] == best.second {
                    merged.append(best.first + best.second)
                    i += 2
                } else {
                    merged.append(word[i])
                    i += 1
                }
            }
            word = merged
            if word.count == 1 { break }
        }
        return word
    }

    // MARK: Aufraeumen und zerlegen

    /// Kleinschreibung und einfache Leerzeichen. CLIP hat nichts anderes gesehen.
    static func clean(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// CLIPs eigene Zerlegung: Buchstabenfolgen, einzelne Ziffern, alles andere als
    /// Block. „M4" wird dadurch zu „m" und „4" — genau so hat es das Modell gelernt.
    private static let pattern = try? NSRegularExpression(
        pattern: "<\\|startoftext\\|>|<\\|endoftext\\|>|'s|'t|'re|'ve|'m|'ll|'d|\\p{L}+|\\p{N}|[^\\s\\p{L}\\p{N}]+",
        options: [.caseInsensitive])

    static func split(_ text: String) -> [String] {
        guard let pattern else { return text.split(separator: " ").map(String.init) }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return pattern.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// Bytes auf druckbare Zeichen, damit die Kodierung ohne Steuerzeichen auskommt.
    /// Wörtlich CLIPs `bytes_to_unicode`.
    static func bytesToUnicode() -> [UInt8: String] {
        var bytes: [UInt8] = []
        bytes += Array(UInt8(ascii: "!") ... UInt8(ascii: "~"))
        bytes += Array(UInt8(0xA1) ... UInt8(0xAC))
        bytes += Array(UInt8(0xAE) ... UInt8(0xFF))

        var scalars = bytes.map { Int($0) }
        var extra = 0
        for byte in 0 ... 255 where !bytes.contains(UInt8(byte)) {
            bytes.append(UInt8(byte))
            scalars.append(256 + extra)
            extra += 1
        }
        var map: [UInt8: String] = [:]
        for (byte, scalar) in zip(bytes, scalars) {
            map[byte] = String(UnicodeScalar(scalar)!)
        }
        return map
    }
}
