# Fundus

*[English](README.md) · Deutsch*

[![Tests](https://github.com/eigenhand/fundus/actions/workflows/tests.yml/badge.svg)](https://github.com/eigenhand/fundus/actions/workflows/tests.yml)

Eine Inventar-App fürs iPhone, die nur die Oberfläche mitbringt; Modell, Endpoint und
API-Schlüssel kommen von dir. Du fotografierst ein Regal, dein eigenes Modell schlägt
die Einträge vor — und du entscheidest, welche in den Bestand kommen.

Gestaltet nach [eigenhand.dev](https://eigenhand.dev), wie ihre beiden Geschwister:
[Faden](https://github.com/eigenhand/faden), eine KI-Chat-App, und
[Spind](https://github.com/eigenhand/spind), eine Datei-App, die auch den Bestand
synchronisieren kann. Was die App schützt und was ausdrücklich nicht:
[SECURITY.de.md](SECURITY.de.md). Wie sie gebaut ist:
[ARCHITECTURE.de.md](ARCHITECTURE.de.md).

## Stand und Voraussetzungen

- Ein junges Freizeitprojekt, kein Produkt. Noch nicht im App Store — du baust es aus
  dem Quelltext.
- Nur iPhone, ab iOS 17.0. Oberfläche auf Deutsch und Englisch.
- Zum Bauen brauchst du Xcode mit Swift 6 und
  [XcodeGen](https://github.com/yonaskolb/XcodeGen). Die CI baut mit Xcode 26.6.
- Einen OpenAI-kompatiblen Endpoint (`/v1/chat/completions` mit `image_url`-Inhalten),
  ein Modell, das Bilder lesen kann, und deinen eigenen API-Schlüssel.

## Was dein Telefon verlässt

Kein Server von mir, keine Konten, keine Telemetrie. Die App spricht mit:

- **deinem Modell-Endpoint** — das Foto und die Namen der Dinge, die schon im Bestand sind;
- **deinem Suchanbieter** (standardmäßig Brave) — nur wenn du das Nachschlagen einschaltest und einen Schlüssel einträgst;
- **huggingface.co** — nur wenn du das optionale Segmentierungsmodell SAM 2.1 lädst.

Einzelheiten, auch zu optionalen Einbettungen über deinen Endpoint: [SECURITY.de.md](SECURITY.de.md#was-das-gerät-verlässt).

## Funktionen

**Fotografieren statt tippen.** Ein Regal, eine Schublade, eine Kiste — dein Modell
liest, was darauf ist, und schreibt daraus Einträge. Wer vierzig Dinge von Hand
eintragen müsste, trägt sie nicht ein; deshalb ist die Kamera der auffälligste Knopf.

**Vorschläge, keine Einträge.** Nichts landet im Bestand ohne Häkchen. Ein Modell, das
ein Regal liest, verzählt sich, fasst zusammen und liest Etiketten falsch — und ein
Bestand, der Modellausgabe stillschweigend aufnimmt, ist schlechter als keiner, weil
du ihm glaubst. Der Prüfschritt zeigt jeden Fund einzeln, mit editierbarem Namen und
verstellbarer Menge, und sagt vorher an, wenn ein Fund zu einem bestehenden Eintrag
passt und dessen Menge erhöht, statt einen zweiten anzulegen.

**„Nicht bestimmbar“ ist eine Antwort.** Das Modell ist angewiesen, nicht zu raten:
keine Marke, keine Größe, keine Sorte, die es nicht sieht. Was es sieht, aber nicht
benennen kann, kommt in eine eigene Liste — „eine graue Schachtel, Aufschrift
unscharf“ —, damit du weißt, wo du selbst nachsehen musst.

**Ein Ding antippen, um es herauszulösen.** Tipp im Foto die Dinge an, die du meinst,
oder zieh einen Rahmen um eines, und jedes geht als eigener Ausschnitt an das Modell —
bei einem einzelnen Motor liest es die Aufschrift, bei einem ganzen Regal liest es
alles nur halb. Wahlweise mit SAM 2.1 (Apples Core-ML-Fassung, etwa 80 MB, auf Wunsch
in den Einstellungen von Hugging Face geladen), das auf dem Gerät läuft; ohne das
Modell greift die App auf Apples eingebaute Objekterkennung zurück, die für Porträts
gemacht ist und an einer Werkbank oft danebenliegt.

**Strichcodes liest das Gerät, nicht das Modell.** Apples Vision dekodiert EAN, UPC,
Code 128, QR und DataMatrix aus dem Foto — mit Prüfziffer, ohne Netz, vor dem ersten
bezahlten Aufruf. Nennt das Modell eine EAN, die der Dekoder *nicht* gesehen hat, wird
sie verworfen. Herstellernummern stehen als Klartext auf dem Teil und dürfen abgelesen
werden; sie bleiben als *abgelesen* markiert.

**Nummern werden nachgeschlagen, aber nichts wird ersetzt.** Zu einer Herstellernummer
oder einem Strichcode kann die App im Netz suchen und einen genauen Namen vorschlagen —
„MP1584EN DC-DC-Abwärtswandler 3 A“ statt „eine Platine“. Das ist die gefährlichste
Funktion der App, und sie ist entsprechend gebaut:

- Der Suchtreffer hat ein **eigenes Häkchen**, und das ist standardmäßig **aus**. Du
  kannst den Fund behalten und die Deutung verwerfen.
- Die Nummer bleibt wörtlich am Eintrag — das Einzige, was du nachprüfen kannst, ohne
  das Teil in die Hand zu nehmen.
- Am Eintrag stehen die Suchanfrage, die Quelle und das Datum.

**Menge oder „—“.** Ungezählt heißt nicht null. Eine geschätzte Zahl ist schlimmer als
keine, weil sie wie eine Zählung aussieht.

**Jeder Eintrag weiß, wann du ihn zuletzt gesehen hast und wer ihn geschrieben hat.**
Drei Stufen: *gesehen* (bis 30 Tage), *vermutet* (bis 180), *unbestätigt*; ein Wisch
nach rechts bestätigt. Außerdem steht an jedem Eintrag, ob ihn ein Mensch getippt oder
ein Modell aus einem Foto gelesen hat — und welches Modell —, mit dem Foto als Beleg.

**Suche, die findet, was du nicht benennen kannst.** Namenstreffer kommen zuerst, weil
sie sicher sind; Treffer nach Bedeutung („das schwarze Kabel mit dem eckigen Stecker“)
kommen danach und sind als solche beschriftet. Die Vektoren entstehen standardmäßig auf
dem Gerät, weil ein Bestand im Keller ohne Empfang durchsucht wird; du kannst
stattdessen auf deinen Endpoint umstellen.

**Orte als Baum.** Keller → Regal 2 → Kiste C, damit „alles im Keller“ beantwortbar
bleibt und ein umbenannter Keller nicht in dreißig Einträgen stehen bleibt. Einen Ort
zu löschen löscht keinen Bestand.

**Wahlweise geteilt mit Spind und Faden.** Der Bestand liegt als Klartext-JSON im
gemeinsamen App-Group-Container `group.dev.eigenhand.shared`, damit Spind ihn
synchronisieren kann. Endpoint und API-Schlüssel mit den Geschwister-Apps zu teilen,
ist eine eigene Einstellung, **„Mit Spind und Faden teilen“**, und die ist
standardmäßig aus. Steht die App Group in einem Build nicht zur Verfügung, nimmt Fundus
ihren eigenen Ordner und sagt das in den Einstellungen.

Was Fundus bewusst nicht tut: Mengen schätzen, Modellausgabe ohne dein Häkchen
übernehmen oder eigene Konten und eine eigene Synchronisierung betreiben.

## Bauen

```bash
brew install xcodegen
xcodegen generate
open Fundus.xcodeproj
```

Die `.xcodeproj` steht nicht im Repo; sie entsteht aus `project.yml`.
`./run-tests.sh` führt die Tests auf einem Simulator aus (standardmäßig
„iPhone 17 Pro“, oder du gibst einen anderen Namen mit).

**Mit deinem eigenen Apple-Konto bauen.** `project.yml` und die Entitlements tragen die
Werte des Autors. Ändere sie, bevor du für ein Gerät baust:

- `DEVELOPMENT_TEAM` in `project.yml` → deine Team-ID.
- `bundleIdPrefix` und beide `PRODUCT_BUNDLE_IDENTIFIER` (`dev.eigenhand.fundus.ios…`) →
  dein eigenes Präfix.
- In `Fundus/Fundus.entitlements` die App Group `group.dev.eigenhand.shared` und die
  Schlüsselbundgruppe `dev.eigenhand.shared` → deine eigenen Kennungen, oder entferne
  sie. Dieselben Kennungen stehen auch in `Storage/SharedContainer.swift` und
  `Storage/Keychain.swift`.

Ohne funktionierende App Group fällt Fundus auf ihren eigenen Ordner und ihre eigenen
Schlüsselbundeinträge zurück; sie läuft weiter, teilt aber nichts mit Spind oder Faden.

**Erster Start.** Öffne die Einstellungen (Zahnrad) und trag Adresse, Pfad, Modellname
und Schlüssel ein. **„Bilder prüfen“** schickt ein winziges Zweifarbenbild und fragt,
was darauf ist — so erfährst du, ob dein Modell Bilder lesen kann. Zum Nachschlagen von
Nummern trägst du unter „Nummern nachschlagen“ einen Suchschlüssel ein; jeder Dienst
geht, der JSON mit Titel, Adresse und Beschreibung liefert.

Für Maintainer: Veröffentlichen (`./release.sh`) und der Pre-Commit-Hook stehen in
[ARCHITECTURE.de.md](ARCHITECTURE.de.md#für-maintainer).

## Lizenz

Apache-2.0. Siehe [LICENSE](LICENSE). Copyright 2026 Christoph Lindl-Guk.

Permissiv und nicht Copyleft, weil eine Inventar-App auf einem Telefon nichts ist,
was jemand als Dienst übernehmen könnte — das Risiko, gegen das ein Copyleft schützt,
gibt es hier nicht. Apache-2.0 statt MIT wegen der ausdrücklichen Patentlizenz.

Das optionale Segmentierungsmodell SAM 2.1 gehört nicht zu diesem Repository: Es wird
zur Laufzeit von Hugging Face geladen und steht unter seiner eigenen Lizenz
(Apache-2.0, siehe `Fundus/Intake/SegmentAssets.swift`).
