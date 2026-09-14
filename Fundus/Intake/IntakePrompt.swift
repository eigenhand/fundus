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

    # Nummern, die am Ding stehen
    Steht an einem Gegenstand eine Kennung — eine Herstellernummer auf einer \
    Platine ("MP1584EN"), eine Typbezeichnung auf einem Motor, eine Seriennummer \
    auf einem Typenschild, eine EAN unter einem Strichcode —, dann schreibe sie \
    **zeichengenau** nach `code`, und nach `code_type` eines von "mpn", "serial", \
    "ean".

    Das ist die einzige Stelle, an der Raten wirklich teuer ist: die App sucht diese \
    Nummer im Netz, und eine verwechselte Ziffer zeigt nicht auf nichts, sondern auf \
    ein **anderes Bauteil**. Lieber kein `code` als ein ungefährer.
      - Nur, was du Zeichen für Zeichen lesen kannst. Unscharf heißt: weglassen.
      - Nichts ergänzen, nichts vervollständigen, keine Schreibweise korrigieren.
      - Keine Maße und keine Mengenangaben: "M4", "4×40", "220 µF" sind \
    Beschreibungen und gehören in `note`.

    # Höchstens 40 Einträge
    Sind mehr im Bild, nimm die auf, die klar erkennbar sind, und schreibe den Rest \
    nach `unreadable`.

    # Die Antwort
    {"items": [{"name": "…", "quantity": 3, "unit": "", "note": "…",
                "code": null, "code_type": null}],
     "unreadable": ["…"]}
    `quantity` ist eine Zahl oder `null`. `unit` und `note` dürfen leer sein. \
    `code` ist `null`, wenn keine Nummer lesbar ist — das ist der Normalfall. \
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
    static func message(placePath: String?, existingNames: [String], hint: String,
                        scannedCodes: [ItemCode] = []) -> String {
        var parts: [String] = []

        if !scannedCodes.isEmpty {
            // Diese Codes hat iOS aus den Balken dekodiert, nicht abgelesen. Sie sind
            // richtig; das Modell soll sie zuordnen, nicht nachprüfen — und schon gar
            // nicht selbst am Strichcode ablesen, was es ohnehin nur raten könnte.
            parts.append("""
            Das Gerät hat in diesem Bild folgende Strichcodes selbst entziffert. Sie \
            sind zeichengenau richtig. Ordne jeden dem Gegenstand zu, an dem er \
            steht, und übernimm ihn unverändert nach `code` mit `code_type`. Passt \
            einer zu keinem Gegenstand, lass ihn weg:
            \(scannedCodes.map { "- \($0.value)  (\($0.label))" }.joined(separator: "\n"))
            """)
        }

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

    // MARK: Zweiter Durchgang — eine Kennung auflösen

    /// Die Anweisung für das Destillieren aus Suchtreffern.
    ///
    /// Dieser Text stand einmal andersherum: „antworte nicht, wenn die Treffer nicht
    /// zur Nummer passen“, zweimal gesagt, damit es sitzt. Die Absicht war richtig und
    /// die Wirkung falsch. Bei einer abgelesenen Nummer passen die Treffer fast nie
    /// wörtlich — ein Zeichen daneben genügt —, und das Modell hat dann pflichtgemäß
    /// geschwiegen, während in denselben Treffern das richtige Bauteil stand.
    ///
    /// Die Strenge bleibt, sie sitzt nur an der richtigen Stelle: das Modell darf
    /// vorlegen, aber nicht behaupten. Es sagt zu jedem Vorschlag, wie weit er von der
    /// gelesenen Nummer entfernt ist, und der Nutzer entscheidet — er hat das Ding in
    /// der Hand, das Modell hat ein unscharfes Foto.
    static let lookupSystem = """
    Du bekommst eine Kennung, die an einem Gegenstand steht, und ein paar \
    Suchtreffer dazu. Du sagst **nicht**, was der Gegenstand ist. Du legst bis zu \
    drei Möglichkeiten vor, und der Nutzer wählt aus. Du antwortest ausschließlich \
    mit einem JSON-Objekt, ohne Vorrede, ohne Codeblock.

    # Warum eine Auswahl und kein Urteil
    Die Kennung wurde meistens von einem Foto abgelesen und ist oft ein Zeichen \
    daneben: eine 0 als O gelesen, eine 8 als 9, ein Bindestrich zu viel. Die Suche \
    findet das richtige Bauteil dann trotzdem — nur eben nicht unter genau dieser \
    Schreibweise. Ob es dasselbe Ding ist, sieht ein Mensch in einer Sekunde: er \
    hält es in der Hand und vergleicht den Aufdruck. Du kannst das nicht. Also \
    entscheidest du nicht, sondern legst vor.

    # Die Vorschläge
    Der wahrscheinlichste zuerst. Jeder Titel kurz und sachlich, wie ein Eintrag in \
    einem Lagerbestand: "MP1584EN DC-DC-Abwärtswandler 3 A", \
    "NEMA-17-Schrittmotor 42×42, Welle 5 mm", "Wago 221-413 Verbindungsklemme \
    3-polig". Deutsch, kein Werbetext, keine Händlerangaben, kein Preis.

    Unterscheidbar müssen sie sein. Dreimal derselbe Motor von drei Händlern ist \
    **ein** Vorschlag, nicht drei — nimm dann den aussagekräftigsten Treffer. Drei \
    Vorschläge lohnen sich nur, wenn sie wirklich verschiedene Dinge sind.

    # `match` — wie weit ist der Vorschlag von der Kennung entfernt
    "exact"  Die Kennung steht wörtlich so in einem Treffer.
    "near"   Ein, zwei Zeichen anders. Dann gehört nach `code_seen`, wie die Nummer \
    im Treffer wirklich lautet — das ist die Zeile, an der der Nutzer sein Teil \
    wiedererkennt.
    "family" Dieselbe Baureihe, andere Ausführung. Auch das ist ein brauchbarer \
    Vorschlag: wer einen 42BYGH-Motor in der Hand hat, erkennt die richtige Länge \
    selbst.

    Stufe nichts hoch. "exact" nur, wenn du die Zeichenfolge im Treffer wirklich \
    siehst; im Zweifel "near".

    # Wann die Liste kurz oder leer bleibt
    Höchstens drei, und lieber einer als drei. Du füllst nicht auf.

    Handeln die Treffer offensichtlich von etwas ganz anderem — Katzenfutter, ein \
    Forenbeitrag ohne Bauteil, eine Begriffsklärung —, dann `"candidates": []`. Das \
    ist die richtige Antwort und keine Niederlage. Drei erfundene Möglichkeiten sind \
    schlechter als keine: der Nutzer prüft sie einzeln und wirft sie einzeln weg.

    # Die Antwort
    {"candidates": [
       {"title": "…",
        "summary": "ein bis zwei Sätze, was das Ding ist und wofür",
        "source": "die URL des Treffers, auf den du dich stützt",
        "match": "exact" | "near" | "family",
        "code_seen": "die Nummer, wie sie im Treffer steht, oder null"}
    ]}
    """

    static func lookupMessage(code: ItemCode, itemName: String,
                              hits: [SearchClient.Hit]) -> String {
        var parts: [String] = []
        parts.append("Kennung: \(code.value)  (\(code.label))")
        if code.origin == .read {
            // Der Unterschied gehört ins Modell, weil er festlegt, wie eng der
            // Vergleich sein muss: eine dekodierte EAN ist richtig, eine abgelesene
            // Nummer kann ein verwechseltes Zeichen enthalten.
            parts.append("Diese Nummer wurde von einem Foto abgelesen und kann "
                         + "Lesefehler enthalten. Ein Treffer, der fast so heißt, "
                         + "ist deshalb ausdrücklich ein Vorschlag wert — sag über "
                         + "`match` und `code_seen`, wie weit er abweicht.")
        } else {
            parts.append("Diese Nummer wurde vom Gerät aus einem Strichcode "
                         + "dekodiert und ist zeichengenau richtig. Ein Treffer mit "
                         + "einer anderen Nummer ist hier ein anderes Produkt.")
        }
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            parts.append("Im Bild sah das Ding aus wie: \(name)")
        }
        parts.append("Suchtreffer:\n" + hits.prefix(5).map(\.forPrompt)
            .joined(separator: "\n"))
        parts.append("Was kommt in Frage?")
        return parts.joined(separator: "\n\n")
    }
}
