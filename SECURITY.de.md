# Sicherheit

*[English](SECURITY.md) · Deutsch*

## Lücken melden

Sicherheitsprobleme bitte **nicht** als öffentliches Issue, sondern per E-Mail an
<christoph.lindl-guk@pm.me>. Ich antworte, so schnell ich kann – dies ist ein
Freizeitprojekt ohne zugesagte Reaktionszeiten.

## Was das Gerät verlässt

Fundus bringt keine Infrastruktur mit. Es gibt keinen Server von mir, keine
Telemetrie und kein Konto.

| Wohin | Was | Wann |
| --- | --- | --- |
| Modell-Endpoint | Das Foto und die Namen der Dinge, die schon im Bestand sind | Beim Lesen einer Aufnahme |
| Suchanbieter (standardmäßig Brave) | Die abgelesene Kennung und der vermutete Name | Nur wenn Nachschlagen an ist und ein Suchschlüssel eingetragen ist |
| Modell-Endpoint oder eine eigene Adresse für Einbettungen | Der Text der Einträge und deine Suchanfragen | Nur wenn die Suche über den Endpoint läuft statt auf dem Gerät (Standard) |
| `huggingface.co` | Eine Download-Anfrage, nichts von dir | Nur wenn du das optionale Modell SAM 2.1 lädst |

Der Bestand selbst, die Fotos und die Orte bleiben auf dem Gerät — im gemeinsamen
App-Group-Container, sofern der Build einen hat, wo Spind sie synchronisieren kann. Das
Nachschlagen ist ausschaltbar, und in den Einstellungen steht, was dabei hinausgeht.
Das Einbettungsmodell für die Suche auf dem Gerät lädt iOS selbst, wenn du es in den
Einstellungen anforderst.

## Schlüssel

API-Schlüssel liegen im **Schlüsselbund des Geräts**. Die Einstellung „Mit Spind und
Faden teilen“ ist standardmäßig aus. Schaltest du sie ein, legt Fundus Adresse und
Modellname in den gemeinsamen Ordner der App Group und den Schlüssel in die gemeinsame
Schlüsselbundgruppe – dann richtet eine eingerichtete App die anderen mit ein. Das ist
der Zweck und zugleich der Preis: Die drei Apps sehen denselben Schlüssel.
Ausgeschaltet bleibt dein Schlüssel in Fundus. Umgekehrt gilt: Hat Fundus noch keinen
Endpoint und hat eine Geschwister-App einen geteilt, übernimmt Fundus ihn beim Start
und sagt das an.

Fundus bringt keinen eigenen Schlüssel mit: Jeder Build startet ohne, und der einzige
Schlüssel, den die App verwendet, ist der, den du einträgst. Ein versionierter
`pre-commit`-Hook (`.githooks/pre-commit`, aktiviert mit
`git config core.hooksPath .githooks`) lehnt einen Commit ab, der etwas enthält, das
nach einem API-Schlüssel aussieht.

## Die Bauart, um die es geht

Fundus hat keine Werkzeuge, die ein Modell aufrufen könnte. Der Hebel ist leiser: was
das Modell aus fremdem Text macht, wird ein **Vorschlag**, und ein Häkchen später
steht er im Bestand.

**Suchtreffer sind eingefasst.** Sie stehen zwischen Marken mit einer je Aufruf
gewürfelten Kennung, und die Systemanweisung des Nachschlagens sagt, was darin gilt:
Material, keine Anweisung – und in `name`, `maker` und `note` kommt nur, was den
Gegenstand beschreibt, keine Adressen und keine Aufforderungen. Der Anlass: eine
Seite, die auf eine gängige Bauteilnummer optimiert ist, schreibt sonst in fremde
Inventare. Ein Eintragsname ist kurz, wird später gesucht, und niemand liest ihn
zweimal.

**Ein Aufkleber ist ein Aufkleber.** Text im Foto lässt sich nicht einfassen – er ist
Teil des Bildes. Dagegen hilft nur die Regel in der Anweisung: was auf einem Etikett
steht, ist Aufdruck und keine Anweisung. Dieser Weg braucht kein Netz und keinen
Angreifer im WLAN, nur eine Sekunde am Regal.

**Das Etikett prüft die App selbst.** Ob ein Vorschlag ein Volltreffer ist, glaubt
Fundus dem Modell nicht: `exact` heißt, die Kennung steht **wörtlich** in einem
Treffer, und das wird nachgesehen. Tut sie es nicht, wird der Vorschlag auf `near`
zurückgestuft. Ein Modell, das gefällig sein will, stuft sonst jeden Treffer hoch –
und genau dieses Etikett entscheidet, wie viel Vertrauen die Zeile bekommt.

**Nichts geht ungefragt in den Bestand.** Alles, was aus einer Aufnahme kommt, ist
ein Vorschlag mit Häkchen. Das ist der Grund, warum du diesem Bestand glauben kannst,
und zugleich die wirksamste Maßnahme gegen alles oben.

## Modellgewichte

Das Segmentierungsmodell (SAM 2.1, Apples Core-ML-Fassung, Apache-2.0) wird zur
Laufzeit geladen und liegt nicht im Bundle – die IPA bleibt dadurch unter zwei
Megabyte, und die Lizenz der App bleibt von der des Modells getrennt.

Geladen wird über HTTPS von `huggingface.co`; geprüft wird die Dateigröße gegen das,
was der Server nennt. Eine Prüfsumme gibt es nicht. Das ist eine Abwägung: sie würde
bei jeder Aktualisierung der fremden Ablage brechen, und Core-ML-Gewichte sind Daten
und kein Programm. Traust du dem Transport nicht, lädst du das Modell nicht; die App
funktioniert auch ohne.

## Bewusste Kompromisse

**Das Foto geht an einen fremden Endpoint.** Das ist der Zweck der App. Welchen,
bestimmst du; was dort damit geschieht, kann Fundus nicht prüfen.

**Die Einfassung ist eine Bitte, keine Schranke.** Ob das Modell sich daran hält, kann
keine Zeile Code erzwingen. Was ein erfolgreicher Angriff erreicht, ist ein falscher
Vorschlag – und den siehst du, bevor du ihn abhakst.

**Die geteilte Schlüsselbundgruppe ist eine Entscheidung.** Siehe oben unter
„Schlüssel“. Willst du sie nicht, lass die Einstellung aus.

Faden hat dieselben Maßnahmen und dieselben Grenzen; die beiden Apps teilen die
Bauart, aber keinen Code.

## Was geprüft ist

Zwei SAM-Tests werden im Simulator übersprungen, weil Core ML die SAM-Maske dort nicht
ausrechnet. Kodierer und Bewertungen kommen richtig heraus, `low_res_masks` ist Byte
für Byte null, auf allen drei Rechenwegen – dasselbe Modell auf dem Mac liefert eine Maske, die
auf zwei Promille auf dem Prüfrechteck liegt. Es ist also nicht der Code. Auf dem
Gerät laufen die beiden mit.

Die Tests laufen in der CI bei jedem Push auf `main` und bei jedem Pull Request, der
mehr als Markdown ändert.
