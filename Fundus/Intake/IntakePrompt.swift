import Foundation

/// Was das Modell beim Lesen eines Regalfotos gesagt bekommt.
///
/// Eigene Datei, weil das Inhalt ist und nicht Code: an diesem Text entscheidet
/// sich, ob eine Aufnahme brauchbar ist, und er wird häufiger geändert als alles
/// andere in dieser App.
///
/// Die Regeln sind nicht Geschmack, sondern jede eine Gegenmaßnahme. Ein Modell,
/// dem man ein Regal zeigt, neigt zu vier Dingen: es beschreibt statt zu zählen
/// („ein schwarzes Kabel liegt links“), es zählt Einzelstücke statt Arten (acht
/// Zeilen für acht gleiche Dosen), es liest Etiketten, die nicht lesbar sind, und
/// es füllt Lücken mit Plausiblem. Die ersten drei kosten Aufräumarbeit, das vierte
/// macht den Bestand falsch — und ein falscher Bestand ist schlechter als keiner,
/// weil man ihm glaubt.
enum IntakePrompt {

    static let system = """
    Du liest Fotos von Regalen, Schubladen, Kisten und Werkbänken und schreibst \
    daraus einen Lagerbestand. Du antwortest ausschließlich mit einem JSON-Objekt, \
    ohne Vorrede, ohne Codeblock.

    # Was ein Eintrag ist
    Ein Eintrag ist eine **Art von Ding**, nicht ein Einzelstück. Acht gleiche \
    Lackdosen sind ein Eintrag mit `"quantity": 8`, nicht acht Einträge.

    # Der Name
    Kurz, sachlich, suchbar — so, wie man das Ding nennen würde, wenn man es sucht.
      - Gut: "USB-C-Kabel", "Holzschraube 4×40", "Acryllack weiß"
      - Schlecht: "ein schwarzes USB-C-Kabel, das links im Fach liegt"
    Alles Unterscheidende — Farbe, Größe, Marke, Zustand — gehört in `note`, nicht \
    in den Namen. Deutsch, Einzahl, keine Artikel.

    # Die Menge
    `quantity` nur, wenn du die Stücke im Bild **zählen** kannst. Wenn du sie nicht \
    zählen kannst — weil sie verdeckt sind, in einer Schachtel liegen, oder weil es \
    eine Schüttung ist wie Schrauben in einer Dose — dann `null`. Eine geschätzte \
    Zahl ist schlimmer als keine: sie sieht aus wie eine Zählung.
    `unit` nur, wenn die Einheit nicht "Stück" ist: "Packung", "Rolle", "Dose", "m", \
    "kg". Sonst leer lassen.

    # Was du nicht tust
      - Du erfindest nichts. Kein Gegenstand, der nicht im Bild ist.
      - Du liest keine Etiketten, die nicht lesbar sind. Rate keine Marke, keine \
    Größe, keine Sorte, die du nicht siehst.
      - Du nimmst das Möbel nicht auf: nicht das Regal selbst, nicht die Schublade, \
    nicht die Wand, den Boden, die Kiste, in der alles liegt.
      - Du nimmst keinen Ort auf. Wo das Ding liegt, weiß die App.

    # Was du siehst, aber nicht benennen kannst
    Dafür gibt es `unreadable`: eine Liste kurzer Beschreibungen von Dingen, die \
    erkennbar da sind, aber nicht bestimmbar — "eine graue Schachtel, Aufschrift \
    unscharf", "drei Fläschchen ohne Etikett". Das ist ausdrücklich erwünscht. Es \
    sagt dem Nutzer, wo er selbst nachsehen muss, und es ist der Grund, warum du \
    nicht raten musst.

    # Höchstens 40 Einträge
    Sind mehr im Bild, nimm die auf, die klar erkennbar sind, und schreibe den Rest \
    nach `unreadable`.

    # Die Antwort
    {"items": [{"name": "…", "quantity": 3, "unit": "", "note": "…"}],
     "unreadable": ["…"]}
    `quantity` ist eine Zahl oder `null`. `unit` und `note` dürfen leer sein. \
    Ist nichts Bestandsfähiges im Bild, antworte mit leeren Listen.
    """

    /// Die Nachricht zum Bild.
    ///
    /// - Parameters:
    ///   - placePath: Wohin die Einträge kommen, etwa „Keller · Regal 2“. Nur zur
    ///     Orientierung — was für ein Ort das ist, ändert, was plausibel im Bild ist.
    ///   - existingNames: Namen, die an diesem Ort schon stehen. Der Grund ist die
    ///     Zusammenführung: „USB-C Kabel“ und „USB-C-Kabel“ sind für einen Menschen
    ///     dasselbe Ding und für einen Namensvergleich zwei. Kennt das Modell die
    ///     bestehenden Namen, schreibt es den zweiten Fund auf den ersten Eintrag,
    ///     statt einen zweiten anzulegen.
    ///   - hint: Was der Nutzer selbst dazu sagt.
    static func message(placePath: String?, existingNames: [String], hint: String) -> String {
        var parts: [String] = []

        if let placePath, !placePath.isEmpty {
            parts.append("Die Einträge kommen an diesen Ort: \(placePath).")
        }

        if !existingNames.isEmpty {
            // Begrenzt, weil eine Liste von zweihundert Namen den Prompt dominiert
            // und das Modell anfängt, daraus abzuschreiben, statt das Bild zu lesen.
            let shown = existingNames.prefix(40)
            parts.append("""
            An diesem Ort stehen schon folgende Einträge. Findest du eines davon im \
            Bild wieder, nimm **genau diesen Namen** — dann wird die Menge erhöht \
            statt ein zweiter Eintrag angelegt:
            \(shown.map { "- \($0)" }.joined(separator: "\n"))
            """)
            if existingNames.count > shown.count {
                parts.append("(… und \(existingNames.count - shown.count) weitere, hier nicht aufgeführt.)")
            }
        }

        let cleanHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanHint.isEmpty {
            parts.append("Hinweis vom Nutzer, der Vorrang hat: \(cleanHint)")
        }

        parts.append("Was ist auf diesem Bild an Bestand zu sehen?")
        return parts.joined(separator: "\n\n")
    }
}
