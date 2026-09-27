# Fundus

*[English](README.md) · Deutsch*

[![Tests](https://github.com/eigenhand/fundus/actions/workflows/tests.yml/badge.svg)](https://github.com/eigenhand/fundus/actions/workflows/tests.yml)

Eine Inventar-App fürs iPhone, die nur die Oberfläche mitbringt; Modell, Endpoint und
API-Schlüssel kommen von dir. Du fotografierst ein Regal, dein eigenes Modell schlägt
die Einträge vor — und du entscheidest, welche in den Bestand kommen.

Ihre beiden Geschwister: [Faden](https://github.com/eigenhand/faden), eine
KI-Chat-App, und [Spind](https://github.com/eigenhand/spind), eine Datei-App, die auch
den Bestand synchronisieren kann. Was die App schützt und was nicht:
[SECURITY.de.md](SECURITY.de.md). Wie sie gebaut ist:
[ARCHITECTURE.de.md](ARCHITECTURE.de.md).

## Stand und Voraussetzungen

- Ein junges Freizeitprojekt, kein Produkt und nicht im App Store: Du baust es aus dem
  Quelltext.
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

**Fotografieren statt tippen.** Fotografier ein Regal, eine Schublade oder eine Kiste;
dein Modell schreibt Einträge aus dem, was es sieht.

**Vorschläge, keine Einträge.** Nichts kommt ohne dein Häkchen in den Bestand. Namen
und Mengen sind editierbar, und ein Fund, der zu einem bestehenden Eintrag passt, erhöht
dessen Menge, statt ein Duplikat anzulegen.

**„Nicht bestimmbar“ ist eine Antwort.** Das Modell rät nicht, was es nicht sieht; was
es nicht benennen kann, kommt in eine eigene Liste, damit du weißt, wo du nachsehen
musst.

**Ein Ding antippen, um es herauszulösen.** Tipp Dinge an oder zieh einen Rahmen, um
jedes als eigenen Ausschnitt an das Modell zu schicken. Wahlweise mit SAM 2.1 auf dem
Gerät (etwa 80 MB, auf Wunsch von Hugging Face geladen), sonst mit Apples eingebauter
Objekterkennung.

**Strichcodes liest das Gerät, nicht das Modell.** Strich- und QR-Codes werden auf dem
Gerät dekodiert; eine EAN, die das Modell nennt, der Dekoder aber nicht gesehen hat,
wird verworfen.

**Nummern werden nachgeschlagen, aber nichts wird ersetzt.** Zu einer Herstellernummer
oder einem Strichcode kann die App im Netz suchen und einen Namen vorschlagen, mit
eigenem Häkchen (standardmäßig aus). Die Nummer bleibt am Eintrag, mit Suchanfrage,
Quelle und Datum.

**Menge oder „—“.** Ungezählt heißt nicht null, und geschätzt wird nichts.

**Jeder Eintrag weiß, wann du ihn zuletzt gesehen hast und wer ihn geschrieben hat.**
*Gesehen* (bis 30 Tage), *vermutet* (bis 180), danach *unbestätigt*; ein Wisch nach
rechts bestätigt. Jeder Eintrag nennt seinen Urheber, einen Menschen oder ein
bestimmtes Modell, mit dem Foto als Beleg.

**Suche, die findet, was du nicht benennen kannst.** Erst Namenstreffer, dann Treffer
nach Bedeutung, mit Vektoren, die standardmäßig auf dem Gerät entstehen, wahlweise über
deinen Endpoint.

**Orte als Baum.** Keller → Regal 2 → Kiste C. Einen Ort zu löschen löscht keinen
Bestand.

**Wahlweise geteilt mit Spind und Faden.** Der Bestand liegt als Klartext-JSON in der
gemeinsamen App Group, damit Spind ihn synchronisieren kann. Endpoint und API-Schlüssel
zu teilen, ist eine eigene Einstellung, **„Mit Spind und Faden teilen“**, standardmäßig
aus.

## Bauen

```bash
brew install xcodegen
xcodegen generate
open Fundus.xcodeproj
```

Die `.xcodeproj` entsteht aus `project.yml` und steht nicht im Repo. `./run-tests.sh`
führt die Tests auf einem Simulator aus (standardmäßig „iPhone 17 Pro“, oder du gibst
einen anderen Namen mit).

**Mit deinem eigenen Apple-Konto bauen.** Ersetz die Werte des Autors, bevor du für ein
Gerät baust:

- `DEVELOPMENT_TEAM` in `project.yml` → deine Team-ID.
- `bundleIdPrefix` und beide `PRODUCT_BUNDLE_IDENTIFIER` (`dev.eigenhand.fundus.ios…`) →
  dein eigenes Präfix.
- In `Fundus/Fundus.entitlements` die App Group `group.dev.eigenhand.shared` und die
  Schlüsselbundgruppe `dev.eigenhand.shared` → deine eigenen Kennungen, oder entferne
  sie. Sie stehen auch in `Storage/SharedContainer.swift` und `Storage/Keychain.swift`.

Ohne funktionierende App Group nimmt Fundus ihren eigenen Ordner und eigene
Schlüsselbundeinträge, sagt das in den Einstellungen und teilt nichts mit Spind oder
Faden.

**Erster Start.** Öffne die Einstellungen (Zahnrad) und trag Adresse, Pfad, Modellname
und Schlüssel ein. **„Bilder prüfen“** zeigt dir, ob dein Modell Bilder lesen kann. Zum
Nachschlagen von Nummern trägst du unter „Nummern nachschlagen“ einen Suchschlüssel
ein; jeder Dienst geht, der JSON mit Titel, Adresse und Beschreibung liefert.

Für Maintainer: Veröffentlichen (`./release.sh`) und Pre-Commit-Hook stehen in
[ARCHITECTURE.de.md](ARCHITECTURE.de.md#für-maintainer).

## Lizenz

Apache-2.0. Siehe [LICENSE](LICENSE). Copyright 2026 Christoph Lindl-Guk.

Das optionale Segmentierungsmodell SAM 2.1 gehört nicht zu diesem Repository; es wird
zur Laufzeit von Hugging Face geladen und hat seine eigene Lizenz (Apache-2.0, siehe
`Fundus/Intake/SegmentAssets.swift`).
