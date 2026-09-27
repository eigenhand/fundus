# Architektur

*[English](ARCHITECTURE.md) · Deutsch*

Die README sagt, was Fundus tut, `SECURITY.de.md` sagt, was es schützt. Dieses hier sagt,
wie es gebaut ist und welche Entscheidungen du kennen musst, bevor du etwas änderst.

## Die Form

Neun Ordner, keine externen Abhängigkeiten, etwa 9 300 Zeilen.

```
UI  ────────►  App  ────►  Intake  ────►  Providers
 │              ├───────►  Search          │
 │              ├───────►  Storage  ───────┤
 │              └───────►  Models  ◄───────┘
 └────────────────────────────────►  Media
```

Die Richtung ist nach unten, mit **einer** Ausnahme im Code.
`Models/Settings.swift` greift für eine Konstante nach `Search` —
`LocalEmbedder.modelIdentifier` —, weil ein Vektor den Namen des Modells tragen muss,
das ihn erzeugt hat, und die Einstellungen entscheiden, welches das ist. Du könntest es
umdrehen, indem du den Wert hereinreichst. Ist nicht geschehen, und dieser Satz steht
hier, damit es niemand erst durch Lesen herausfinden muss.

(Eine zweite scheinbare Rückkante, `Intake → UI`, ist ein Kommentar in `Segmenter.swift`,
der auf `ObjectPicker.circle` verweist. Kein Code folgt ihm.)

| Ordner | Was darin liegt |
| --- | --- |
| `Models/` | Werttypen: Eintrag, Kennung, Ort, Bestand, Einstellungen. `Codable`, prüfbar, ohne Ein- und Ausgabe |
| `Intake/` | Der Weg vom Foto zum Vorschlag: Strichcode, Freistellen, Anweisung, Nachschlagen |
| `Search/` | Einbettung auf dem Gerät, der Index, die zweigleisige Suche |
| `Providers/` | Modell-Client, Such-Client, Vision-Prüfung — der ganze Netzverkehr |
| `Media/` | Kamera, Mediathek, Bildaufbereitung |
| `Storage/` | Der gemeinsame Container, JSON-Persistenz, Schlüsselbund, Fotoablage |
| `App/` | `AppModel` und der Einstieg — etwa 600 Zeilen, der kleinste Ordner, auf den es ankommt |
| `UI/` | 10 Ansichten, 3 600 Zeilen |
| `Design/` | Eine Datei, wörtlich aus Faden übernommen |

## Das Rückgrat: vom Foto zum Eintrag

Alles andere in dieser App dient einem Ablauf, und die Reihenfolge seiner Schritte ist
die Architektur.

```
   Foto
     │
     ├─► BarcodeScanner        auf dem Gerät, Apples Vision, mit Prüfziffer
     │                         — bevor irgendetwas bezahlt wird
     ├─► Segmenter             auf dem Gerät, SAM 2.1, nur wenn ein Ding angetippt wird
     │
     ├─► IntakePrompt ─► ModelClient ─► Vorschläge           ein bezahlter Aufruf
     │
     ├─► IdentityLookup ─► SearchClient ─► ModelClient       nur wenn Nachschlagen an ist
     │
     └─► Prüfen ─► Häkchen ─► Bestand ─► Indexer ─► Vektor
```

In dieser Reihenfolge stecken zwei Regeln.

**Das Gerät macht zuerst, was das Gerät kann.** Ein Strichcode wird lokal dekodiert, mit
Prüfziffer, bevor ein einziger Modellaufruf bezahlt ist. Ein angetipptes Ding oder ein gezogener
Rahmen wird lokal freigestellt. Das Modell sieht das Foto erst, wenn alles Billige und Sichere geschehen
ist — und das Ergebnis des billigen Schritts begrenzt den teuren: Nennt das Modell eine
EAN, die der Dekoder *nicht* gesehen hat, wird sie verworfen. Einen Strichcode kann
niemand mit den Augen lesen.

**Nichts kommt ohne Häkchen in den Bestand.** `IntakeJob` hat sechs Phasen, und `review`
ist eine davon. Es gibt keinen Weg von `ModelClient` zu `Inventory`, der nicht durch
einen Menschen führt. Das ist keine nachträglich angeschraubte Sicherung; es ist der
Grund, warum der Ablauf überhaupt diese Form hat, und es ist der Grund, warum du diesem
Bestand glauben kannst.

## Die Warteschlange

Fotos kommen nicht einzeln. Wer einen Keller abgeht, macht zwanzig, und jedes kostet
einen Modellaufruf von mehreren Sekunden.

`IntakeJob` ist deshalb ein Werttyp mit einer Phase, und `AppModel` hält eine Reihe
davon. Wie viele nebeneinander laufen, ist eine Einstellung und keine Konstante — und der
Grund steht im Quelltext: Die richtige Zahl hängt nicht von der App ab, sondern vom
Anbieter. Der eine nimmt sechs Aufrufe nebeneinander an, der nächste drosselt ab zwei und
antwortet mit 429.

Die Phasen sind `waiting · reading · looking · review · empty · failed`, und zwei davon
sind keine Fehler. `empty` heißt: Das Modell hat das Foto gelesen und nichts darauf
gefunden, was in einen Bestand gehört. `failed` trägt einen Satz für einen Menschen.
Beide bleiben in der Leiste stehen, bis jemand sie wegwischt — ein Foto, das still
verschwindet, ist schlimmer als eines, das sagt, warum es nicht ging.

## Zwei Einbettungsräume, und warum jeder Vektor gestempelt ist

Die Suche läuft zweigleisig, und die Reihenfolge ist eine Entscheidung und keine
Rangfolge: Ein Namenstreffer ist eine Gewissheit, ein Kosinus eine Vermutung.
`ItemSearch` stellt Namenstreffer nach vorn und lässt einen Ähnlichkeitstreffer nie einen
sicheren nach unten schieben.

Die Vektoren kommen entweder aus Apples `NLContextualEmbedding` auf dem Gerät oder von
einem Endpoint. Das ist das interessante Problem: **Zwei Einbettungen sind nur
vergleichbar, wenn sie aus demselben Modell kommen.** Ohne Stempel rechnete die Suche
nach einem Modellwechsel still zwischen zwei Räumen und lieferte Unsinn, der wie Treffer
aussieht.

Jeder Vektor trägt deshalb Modellnamen und Dimension. Die Einstellungen zählen
*nutzbar / fremd / fehlt*, nennen die Modelle, die im Index liegen, und bieten drei
getrennte Knöpfe: Nachholen, neu aufbauen, löschen. Drei und nicht einer, weil die drei
Verschiedenes bedeuten und einer davon löscht.

## `ModelClient` ist mit Absicht klein

Fadens Anbieterschicht spricht zwei Wire-Formate, Werkzeugaufrufe und Gedankengang —
etwa neunhundert Zeilen. Fundus hat etwa 550 in den drei Dateien unter `Providers/`,
und das ist eine Entscheidung und keine Lücke: Fadens Schicht mitzuschleppen hieße, sie
in zwei Apps zu pflegen, damit eine davon einen Bruchteil benutzt.

Was er tut: ein Bild hin, JSON zurück, dazu Vektoren. Gestreamt wird trotzdem, und aus
einem gemessenen Grund — ein getesteter Anbieter beantwortete gestreamte Aufrufe in
Sekunden, während nicht-gestreamte derselben Größe überhaupt nicht zurückkamen.

Dasselbe gilt für die Einfassung fremden Textes: `Intake/UntrustedContent.swift` sind
dieselben gut siebzig Zeilen wie in Faden, doppelt. Der Quelltext sagt warum: Sie zu teilen
wäre eine gemeinsame Bibliothek wert, und solange es die nicht gibt, ist doppelter Code
besser als eine ungeschützte App.

## Wo der Zustand liegt

**Im gemeinsamen Container.** Der Bestand liegt als Klartext-JSON in
`group.dev.eigenhand.shared`, damit Spind ihn synchronisieren kann, ohne Fundus zu
kennen. Ist die App Group in einem Build nicht freigeschaltet, fällt `SharedContainer` auf
den eigenen Ordner der App zurück — und die Einstellungen sagen, welcher der beiden gilt.
Eine App, die still woanders hinschreibt, ist eine App, die still Daten verliert.

**In `AppModel`.** Eine `@Observable`-Klasse: der Bestand, die Einstellungen, die
Warteschlange. Fundus hat keinen Zustand je Unterhaltung wie Faden; es gibt einen Bestand
und eine Reihe.

**Im Schlüsselbund.** Schlüssel, aus den Einstellungen über einen Namen angesprochen. Ist
„Mit Spind und Faden teilen“ an (standardmäßig ist es aus), liegt der Modellschlüssel in
der gemeinsamen Schlüsselbundgruppe — das ist der Zweck und zugleich der Preis, und es
steht in `SECURITY.de.md`.

## Modellgewichte liegen nicht im Bundle

SAM 2.1 Tiny (Apples Core-ML-Fassung, float16, Apache-2.0, etwa 80 MB) wird zur Laufzeit
von `huggingface.co/apple/coreml-sam2.1-tiny` geladen, und nur, wenn du in den
Einstellungen auf „Laden“ tippst; `SegmentAssets.swift` erledigt das. Zwei Gründe, und beide zählen: Die IPA bleibt unter
zwei Megabyte, und die Lizenz der App bleibt von der des Modells getrennt.

Das Freistellen ist auch in einem zweiten Sinn optional. Ohne das Modell fällt der
Objekte-Modus darauf zurück, was sich das Gerät selbst aussucht — und das ist für
Porträts gebaut und liegt an einer Werkbank oft daneben. Mit ihm entscheidet dein Finger.

## Prüfen

Zwei der Tests werden im Simulator immer übersprungen, und sie sind der ehrliche Teil: Core ML rechnet die SAM-Maske im Simulator nicht aus. Kodierer und Bewertungen
kommen richtig heraus, `low_res_masks` ist auf allen drei Rechenwegen Byte für Byte null,
und dasselbe Modell auf dem Mac liefert eine Maske, die auf zwei Promille auf dem
Prüfrechteck liegt. Es ist also nicht der Code. Auf dem Gerät laufen die beiden mit.

Alle Tests laufen ohne Netz außer `RemoteModelTests`: Sie laden das kleinste SAM-Paket
(2,1 MB) von Hugging Face, weil sich das Fortsetzen eines abgebrochenen Downloads nur
messen und nicht herleiten lässt. Ist der Server nicht erreichbar, werden sie
übersprungen.

`./run-tests.sh` führt sie auf einem Simulator aus und sagt, woran es lag, wenn es
schiefging. Die CI führt sie bei jedem Push aus, der etwas anderes anfasst als eine
`.md`-Datei.

## Entwurfsnotizen aus der README

**Kennungen nachschlagen.** Ein aufgelöster Produktname steht am Ende einer Kette mit
drei fehlbaren Gliedern: ein unscharfer Aufkleber, ein Modell, das Zeichen verwechselt,
eine Suchmaschine, die auf jede Zeichenfolge irgendetwas antwortet. Danach sieht er
verlässlicher aus als alles andere im Bestand und ist es am wenigsten. Deshalb das
eigene Häkchen, das standardmäßig aus ist, die wörtlich erhaltene Kennung und
Suchanfrage, Quelle und Datum am Eintrag. Passen die Treffer nicht zur Nummer, ist
`null` die vorgesehene Antwort des Modells — kein Vorschlag ist besser als ein
plausibler. Höchstens acht Nummern je Aufnahme (`IdentityLookup.maxPerIntake`): Ein
voller Werkzeugkoffer kostet sonst vierzig Suchen und vierzig Modellaufrufe für eine
Liste, die vielleicht verworfen wird. Die Such-Adresse ist standardmäßig Brave Search,
weil Faden sie auch benutzt und so ein Schlüssel für beide reicht.

**Strichcodes und Herstellernummern.** Ein Sprachmodell, dem du Balken zeigst, liest
die Ziffern darunter ab und rät bei Unschärfe — daher die Regel, dass eine EAN nur
zählt, wenn der Dekoder auf dem Gerät sie gesehen hat. Herstellernummern stehen als
Klartext auf dem Teil und dürfen abgelesen werden, bleiben aber als *abgelesen*
markiert.

**Grenzen der Frische.** *Gesehen* bis 30 Tage, *vermutet* bis 180, danach
*unbestätigt* (`Models/Item.swift`). Ein Bestand veraltet, während die Datenbank
aussieht wie am ersten Tag; die Stufen sagen das. Die beiden Grenzen sind gesetzt,
nicht gemessen, und der Quelltext sagt das auch.

**Einbettungen auf dem Gerät, in Zahlen.** `NLContextualEmbedding`: 512 Dimensionen,
108 MB Modelldateien, gemessen 8 ms je Eintrag und 13,5 MB Arbeitsspeicher. Gröber als
ein Netzmodell — auf neun Fragen gegen vierzehn Sätze setzte `qwen3-embedding-8b`
siebenmal die richtige Antwort auf Platz eins, dieses hier fünfmal. Trotzdem die
Voreinstellung, weil ein Bestand im Keller durchsucht wird, mit einem Balken Empfang
oder keinem: Fünf von neun ohne Netz schlagen sieben von neun mit.

**Endpoints und Token-Vorrat.** Getestet mit `z-ai/glm-5.3-flash` über TensorX.
Reasoning-Modelle brauchen den Token-Vorrat doppelt — erst zum Nachdenken, dann zum
Schreiben —, deshalb liegt das Ausgabelimit standardmäßig bei 32 000 und ist in den
Einstellungen verstellbar. Zu wenig davon sieht aus wie eine leere Antwort. „Bilder
prüfen“ in den Einstellungen schickt ein winziges Zweifarbenbild und fragt, was darauf
ist: Eine Ablehnung heißt, das Modell kann keine Bilder lesen, eine Antwort, die beide
Farben nennt, heißt, es kann.

**Das Icon.** Ein Sortierkasten von oben, erzeugt statt gemalt:
`python3 Tools/make-icon.py` schreibt die drei Fassungen (hell, dunkel, getönt)
byte-genau neu; die Korrekturen aus drei Anläufen stehen im Skript.

## Für Maintainer

**Veröffentlichen.** `./release.sh` archiviert die App, lädt sie zu TestFlight hoch und
weist den Build der internen Testgruppe zu (`assign-build.sh`). Dafür brauchst du eine
`.release.env` (Kopie von `.release.env.example`) mit `ASC_ISSUER_ID` und `ASC_KEY_ID`,
einen App-Store-Connect-API-Schlüssel unter
`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` und die einmalige Einrichtung, die
oben im Skript steht (Bundle-ID, App-Eintrag, App Group). Die Release-Konfiguration in
`project.yml` signiert manuell mit dem Profil „Fundus App Store (API)“; Debug signiert
automatisch, Simulator und Tests bleiben davon unberührt.

**Der Git-Hook.** `git config core.hooksPath .githooks` schaltet einen Pre-Commit-Hook
scharf, der Commits mit etwas ablehnt, das nach einem API-Schlüssel aussieht. Er liegt
versioniert im Repo, weil ein Hook in `.git/hooks` beim Klonen nicht mitkopiert wird.
