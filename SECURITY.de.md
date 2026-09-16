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
| Suchanbieter | Die abgelesene Kennung und der vermutete Name | Nur wenn Nachschlagen an ist |

Der Bestand selbst, die Fotos und die Orte bleiben auf dem Gerät. Das Nachschlagen
ist ausschaltbar, und in den Einstellungen steht, was dabei hinausgeht.

## Schlüssel

API-Schlüssel liegen im **Schlüsselbund des Geräts**. Wer die Einstellung „Mit Spind
und Faden teilen" einschaltet, legt Adresse und Modellname in den gemeinsamen Ordner
der App-Gruppe und den Schlüssel in die gemeinsame Schlüsselbundgruppe – dann richtet
eine eingerichtete App die anderen mit ein. Das ist der Zweck und zugleich der Preis:
die drei Apps sehen denselben Schlüssel. Ausgeschaltet bleibt alles in Fundus.

Bis September 2026 trugen die TestFlight-Builds einen Schlüssel im Binary. Das war
eine bewusste Abwägung und ist keine mehr – ein Schlüssel im ausgelieferten Binary
ist für jeden lesbar, der das Binary hat. Ein versionierter `pre-commit`-Haken schlägt
an, wenn etwas, das nach einem Schlüssel aussieht, in einen Commit gerät.

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

**Die Etikette prüft die App selbst.** Ob ein Vorschlag ein Volltreffer ist, glaubt
Fundus dem Modell nicht: `exact` heisst, die Kennung steht **wörtlich** in einem
Treffer, und das wird nachgesehen. Tut sie es nicht, wird der Vorschlag auf `near`
zurückgestuft. Ein Modell, das gefällig sein will, stuft sonst jeden Treffer hoch –
und genau diese Etikette entscheidet, wie viel Vertrauen die Zeile bekommt.

**Nichts geht ungefragt in den Bestand.** Alles, was aus einer Aufnahme kommt, ist
ein Vorschlag mit Häkchen. Das ist der Grund, warum man diesem Bestand glauben kann,
und zugleich die wirksamste Massnahme gegen alles oben.

## Modellgewichte

Das Segmentierungsmodell (SAM 2.1, Apples Core-ML-Fassung, Apache-2.0) wird zur
Laufzeit geladen und liegt nicht im Bundle – die IPA bleibt dadurch unter zwei
Megabyte, und die Lizenz der App bleibt von der des Modells getrennt.

Geladen wird über HTTPS von `huggingface.co`; geprüft wird die Dateigrösse gegen das,
was der Server nennt. Eine Prüfsumme gibt es nicht. Das ist eine Abwägung: sie würde
bei jeder Aktualisierung der fremden Ablage brechen, und Core-ML-Gewichte sind Daten
und kein Programm. Wer dem Transport nicht traut, lädt das Modell nicht.

## Bewusste Kompromisse

**Das Foto geht an einen fremden Endpoint.** Das ist der Zweck der App. Welcher, sagt
der Nutzer; was dort damit geschieht, kann Fundus nicht prüfen.

**Die Einfassung ist eine Bitte, keine Schranke.** Ob das Modell sich daran hält, kann
keine Zeile Code erzwingen. Was ein erfolgreicher Angriff erreicht, ist ein falscher
Vorschlag – und den sieht der Nutzer, bevor er ihn abhakt.

**Die geteilte Schlüsselbundgruppe ist eine Entscheidung.** Siehe oben unter
„Schlüssel". Wer sie nicht will, lässt die Einstellung aus.

Dieselben Massnahmen und dieselben Grenzen stehen in Faden; die beiden Apps teilen die
Bauart, aber keinen Code.

## Was geprüft ist

169 Tests, davon zwei übersprungen: Core ML rechnet im Simulator die SAM-Maske nicht
aus. Kodierer und Bewertungen kommen richtig heraus, `low_res_masks` ist Byte für Byte
null, auf allen drei Rechenwegen – dasselbe Modell auf dem Mac liefert eine Maske, die
auf zwei Promille auf dem Prüfrechteck liegt. Es ist also nicht der Code. Auf dem
Gerät laufen die beiden mit.

Die Tests laufen bei jedem Push.
