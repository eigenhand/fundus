# Fundus

*[English](README.md) · Deutsch*

[![Tests](https://github.com/eigenhand/fundus/actions/workflows/tests.yml/badge.svg)](https://github.com/eigenhand/fundus/actions/workflows/tests.yml)

Ein Lagerbestand fürs iPhone, der nichts mitbringt außer der Oberfläche. Modell,
Endpoint und API-Key kommen von dir. Keine Zwischenserver, keine Konten, keine
Telemetrie — die App spricht ausschließlich mit der Adresse, die du einträgst.

Design nach [eigenhand.dev](https://eigenhand.dev). Schwester von
[Faden](https://github.com/eigenhand/faden) (KI-Chat) und Spind (Dateien).

Was die App schützt und was ausdrücklich nicht: [SECURITY.de.md](SECURITY.de.md).
Wie sie gebaut ist: [ARCHITECTURE.de.md](ARCHITECTURE.de.md).

## Was drin ist

**Fotografieren statt tippen.** Ein Regal, eine Schublade, eine Kiste — dein Modell
liest, was darauf ist, und schreibt daraus Einträge. Wer vierzig Dinge von Hand
eintragen müsste, trägt sie nicht ein; das ist der Grund, warum diese App eine Kamera
als auffälligsten Knopf hat.

**Vorschläge, keine Einträge.** Nichts landet im Bestand ohne Häkchen. Ein Modell, das
ein Regal liest, verzählt sich, fasst zusammen und liest Etiketten falsch — und ein
Bestand, der Modellausgabe stillschweigend aufnimmt, ist schlechter als keiner, weil
man ihm glaubt. Der Prüfschritt zeigt jeden Fund einzeln, mit editierbarem Namen und
verstellbarer Menge, und sagt vorher an, wenn ein Fund auf einen bestehenden Eintrag
fällt und die Menge erhöht statt einen zweiten anzulegen.

**„Nicht bestimmbar“ ist eine Antwort.** Das Modell wird ausdrücklich angewiesen,
nicht zu raten: keine Marke, keine Größe, keine Sorte, die es nicht sieht. Was es
sieht, aber nicht benennen kann, kommt in eine eigene Liste — „eine graue Schachtel,
Aufschrift unscharf“. Das sagt dir, wo du selbst nachsehen musst, statt dir eine
plausible Erfindung als Bestand zu verkaufen.

**Nummern werden nachgeschlagen, aber nichts wird ersetzt.** Steht auf einem Bauteil
eine Herstellernummer, oder klebt ein Strichcode darauf, kann die App im Netz danach
suchen und einen genauen Namen vorschlagen — „MP1584EN DC-DC-Abwärtswandler 3 A“
statt „eine Platine“. Das ist die gefährlichste Funktion dieser App, und sie ist
entsprechend gebaut. Ein aufgelöster Produktname steht am Ende einer Kette mit drei
fehlbaren Gliedern: ein unscharfer Aufkleber, ein Modell, das Zeichen verwechselt,
eine Suchmaschine, die auf jede Zeichenfolge irgendetwas antwortet. Danach sieht er
verlässlicher aus als alles andere im Bestand und ist es am wenigsten. Deshalb:

- Der Suchtreffer hat ein **eigenes Häkchen** und ist **aus** voreingestellt. Man kann
  den Fund behalten und die Deutung verwerfen.
- Die Nummer steht daneben, wörtlich, und bleibt am Eintrag — sie ist das Einzige,
  was sich nachprüfen lässt, ohne das Ding in die Hand zu nehmen.
- Am Eintrag steht die Suchanfrage, die Quelle und das Datum.
- Passen die Treffer nicht zur Nummer, ist `null` die vorgesehene Antwort des
  Modells. Kein Vorschlag ist besser als ein plausibler.

**Strichcodes liest das Gerät, nicht das Modell.** Apples Vision dekodiert EAN, UPC,
Code 128, QR und DataMatrix aus dem Foto — mit Prüfziffer, ohne Netz, ohne Kosten, vor
dem ersten bezahlten Aufruf. Ein Sprachmodell, dem man Balken zeigt, liest die Ziffern
darunter ab und rät bei Unschärfe. Nennt das Modell eine EAN, die der Dekoder *nicht*
gesehen hat, wird sie verworfen: einen Strichcode kann man nicht mit den Augen lesen.
Herstellernummern dagegen stehen als Klartext auf dem Bauteil und dürfen abgelesen
werden — sie bleiben als *abgelesen* markiert und damit als fehlbar.

**Menge oder „—“.** `null` heißt ungezählt, nicht null Stück. Eine geschätzte Zahl ist
schlimmer als keine, weil sie wie eine Zählung aussieht. Dosen in einer Schachtel,
Schrauben in einer Schüttung: ungezählt.

**Jeder Eintrag weiß, wann du ihn zuletzt gesehen hast.** Ein Lagerbestand veraltet,
während die Datenbank aussieht wie am ersten Tag — das ist die eine Unwahrheit, die
eine Inventarapp von sich aus erzeugt. Drei Stufen: *gesehen* (bis 30 Tage),
*vermutet* (bis 180), *unbestätigt*. Ein Wisch nach rechts bestätigt. Ein Filter zeigt,
was zu lange nicht bestätigt wurde. Die beiden Grenzen sind gesetzt, nicht gemessen,
und stehen als solche im Quelltext.

**Und wer ihn geschrieben hat.** An jedem Eintrag steht, ob ihn ein Mensch getippt oder
ein Modell aus einem Foto gelesen hat — und **welches** Modell. Das Foto bleibt als
Beleg daneben. Wer später vor dem Regal steht und die Zahl nicht wiederfindet, muss
wissen, wessen Zahl das war.

**Suche, die findet, was du nicht benennen kannst.** Zwei Wege, und die Reihenfolge
ist die Entscheidung: ein Namenstreffer ist eine Gewissheit, ein Kosinus eine
Vermutung. Wer „Rudi“ tippt, bekommt das Ding, das Rudi heißt, an erster Stelle. Die
Ähnlichkeitssuche verdient ihren Platz bei „das schwarze Kabel mit dem eckigen
Stecker“ — da findet kein Teilstring etwas —, darf aber keinen sicheren Treffer nach
unten schieben. Treffer aus Bedeutung sind als solche beschriftet.

**Vektoren auf dem Gerät, voreingestellt.** Apples `NLContextualEmbedding`: 512
Dimensionen, 108 MB Modelldateien, gemessen 8 ms je Eintrag und 13,5 MB
Arbeitsspeicher. Gröber als ein Netzmodell — auf neun Fragen gegen vierzehn Sätze
traf `qwen3-embedding-8b` siebenmal auf Platz eins, dieses hier fünfmal. Trotzdem die
Voreinstellung, und der Grund ist der Ort: ein Bestand wird im Keller durchsucht, vor
dem Regal, mit einem Balken Empfang oder keinem. Fünf von neun ohne Netz schlagen
sieben von neun mit. Wer es anders will, stellt auf seinen Endpoint um.

**Der Index sagt, was in ihm steckt.** Jeder Vektor trägt Modellnamen und Dimension.
Zwei Einbettungen sind nur vergleichbar, wenn sie aus demselben Modell kommen — ohne
Stempel rechnet die Suche nach einem Modellwechsel still zwischen zwei Räumen, die
nichts miteinander zu tun haben. Die Einstellungen zählen deshalb *nutzbar / fremd /
fehlt* und nennen die Modelle, die im Index liegen. Nachholen, neu aufbauen und
löschen sind drei getrennte Knöpfe.

**Orte als Baum.** Keller → Regal 2 → Kiste C. Als Baum und nicht als Zeichenkette,
damit „alles im Keller“ beantwortbar bleibt und ein umbenannter Keller nicht in
dreißig Einträgen stehenbleibt. Einen Ort zu löschen löscht keinen Bestand: die Dinge
liegen danach nirgends, was stimmt und sichtbar ist.

**Geteilt mit Spind und Faden.** Der Bestand liegt als Klartext-JSON im gemeinsamen
Container `group.dev.eigenhand.shared` — Spind kann ihn synchronisieren, ohne Fundus
zu kennen. Endpoint und Modellname liegen daneben in `eigenhand/endpoint.json`, der
Schlüssel in der gemeinsamen Schlüsselbundgruppe: wer eine der drei Apps einrichtet,
hat alle drei eingerichtet. Ist die App Group in einem Build nicht freigeschaltet,
fällt die App auf ihren eigenen Ordner zurück — und sagt in den Einstellungen,
welcher der beiden gilt, statt es erraten zu lassen.

## Was es nicht tut

- **Kein Barcode als Hauptweg.** EAN wird gelesen, wo eine ist, und aufgelöst, wenn
  man es einschaltet. Aber eine Kiste M4-Schrauben und ein namenloses USB-C-Kabel
  haben keinen, und das ist der Normalfall in einer Werkstatt.
- **Keine Konten, kein Server, keine Synchronisierung von uns.** Dafür ist Spind da.
- **Keine automatische Übernahme von Modellausgabe.** Siehe oben — das ist der Punkt.
- **Keine Mengenschätzung.** Was nicht zählbar ist, bleibt ungezählt.

## Einrichten

Bei der ersten Öffnung fragt Fundus nach Adresse, Pfad, Modellname und Schlüssel.
Alles OpenAI-kompatible geht: `/v1/chat/completions` mit `image_url`-Inhalten. Das
Modell muss Bilder lesen können — **„Bilder prüfen“** in den Einstellungen schickt ein
winziges Zweifarbenbild und fragt, was darauf ist. Eine Ablehnung heißt nein, eine
Antwort, die beide Farben nennt, heißt ja. Geraten wird nichts.

Getestet mit `z-ai/glm-5.3-flash` über TensorX. Reasoning-Modelle brauchen den
Token-Vorrat doppelt — erst zum Nachdenken, dann zum Schreiben —, deshalb steht das
Limit bei 32 000 und ist in den Einstellungen verstellbar. Zu wenig davon sieht aus
wie eine leere Antwort; die App sagt inzwischen, wenn es das war.

Das Nachschlagen von Nummern ist aus, bis ein Suchschlüssel eingetragen ist.
Voreingestellt auf Brave Search, weil Faden denselben benutzt; jeder Dienst geht, der
JSON mit Titel, Adresse und Beschreibung liefert. Höchstens acht Nummern je Aufnahme —
ein voller Werkzeugkoffer kostet sonst vierzig Suchen und vierzig Modellaufrufe für
eine Liste, die vielleicht verworfen wird.

## Bauen

```bash
brew install xcodegen
xcodegen generate
open Fundus.xcodeproj
```

Die `.xcodeproj` steht nicht im Repo — sie entsteht aus `project.yml`. Die Bundle-ID
ist `dev.eigenhand.fundus.ios`; für die App Group braucht sie im Developer-Portal das
Recht `com.apple.security.application-groups` mit `group.dev.eigenhand.shared`.

```bash
./run-tests.sh            # 182 Tests auf einem Simulator
./release.sh              # Archiv, Upload zu TestFlight, Zuweisung
git config core.hooksPath .githooks
```

Der Haken verhindert, dass ein für einen TestFlight-Build eingesetzter Schlüssel in
die Historie gerät. Er liegt versioniert im Repo, weil ein Haken in `.git/hooks` bei
keinem Klonen mitwandert.

## Aufbau

```
Fundus/
  Models/      Item · ItemCode · Place · Inventory · Settings   — Werttypen, prüfbar
  Intake/      IntakePrompt · PhotoIntake · BarcodeScanner · IdentityLookup
  Search/      LocalEmbedder · Indexer · ItemSearch     — Namen, Bedeutung, Index
  Storage/     SharedContainer · Store · Keychain · PhotoStore
  Providers/   ModelClient · SearchClient · VisionProbe  — der ganze Netzverkehr
  UI/          InventoryView · IntakeView · ItemDetailView · PlacesView · SettingsView
  App/         AppModel · FundusApp
  Design/      Theme                                    — wörtlich wie in Faden
```

`ModelClient` ist absichtlich klein: ein Bild hin, JSON zurück, plus Vektoren. Fadens
Anbieterschicht kann zwei Wire-Formate, Werkzeugaufrufe und Gedankengang — neunhundert
Zeilen davon mitzuschleppen hieße, sie in zwei Apps zu pflegen, damit eine einen
Bruchteil benutzt. Gestreamt wird trotzdem: ein getesteter Anbieter beantwortete
gestreamte Aufrufe in Sekunden, während nicht-gestreamte derselben Größe überhaupt
nicht zurückkamen.

## Das Icon

Ein Sortierkasten von oben, navy auf hell wie der Rest der Familie. Erzeugt, nicht
gemalt — `python3 Tools/make-icon.py` schreibt die drei Fassungen (hell, dunkel,
getönt) neu und kommt dabei auf dieselben Bytes.

Drei Anläufe, und die Korrekturen stehen im Skript: Rechtecke in Zellen lesen sich
als Wireframe, nicht als Kasten. Was den Unterschied macht, ist die dicke Außenwand
gegen dünne Stege — ein Diagramm hat überall dieselbe Strichstärke — und Inhalt mit
Form statt gefüllter Kacheln. Kein Dashboard hat runde Kacheln; drei Kreise sagen
„Schrauben".

## Lizenz

Apache-2.0. Siehe [LICENSE](LICENSE). Copyright 2026 Christoph Lindl-Guk.

Permissiv und nicht Copyleft, weil eine Inventar-App auf einem Telefon nichts ist,
was jemand als Dienst übernehmen könnte — das Risiko, gegen das ein Copyleft
schützt, gibt es hier nicht. Apache-2.0 statt MIT wegen der ausdrücklichen
Patentlizenz.

Die Modellgewichte gehören nicht dazu: sie werden zur Laufzeit geladen und stehen
unter ihren eigenen Lizenzen (siehe `Intake/SegmentAssets.swift`).
