import SwiftUI
import UIKit

/// Eine Aufnahme in der Schlange.
///
/// Hieß einmal `IntakeState` und war genau eine: ein Foto belegte den ganzen
/// Bildschirm, bis das Modell fertig gelesen hatte. Wer vor einem Regal steht, macht
/// aber nicht ein Foto, sondern zwölf — und wartete dann zwölfmal eine halbe Minute,
/// ohne etwas tun zu können.
///
/// Jetzt ist jedes Foto ein Auftrag mit eigenem Zustand, und die App arbeitet mehrere
/// nebeneinander ab. Der Prüfschritt ist kein Zwang mehr, sondern ein Angebot: der
/// Auftrag wartet in der Reihe, bis jemand ihn antippt.
@Observable @MainActor
final class IntakeJob: Identifiable {

    enum Phase: Equatable {
        /// In der Reihe, aber noch kein Arbeiter frei.
        case waiting
        case reading
        /// Kennungen werden im Netz nachgeschlagen. Eigene Phase, weil der Schritt
        /// Sekunden dauert und der Nutzer sonst vor einer halb fertigen Liste steht.
        case looking(done: Int, total: Int)
        /// Fertig gelesen, wartet auf den Menschen.
        case review
        /// Gelesen, und auf dem Foto war kein Bestand.
        ///
        /// Eigene Phase und nicht `failed`, obwohl es zuerst dort lag. Ein Foto vom
        /// Kellerfenster ist kein Fehler, sondern eine Antwort — und ein rotes
        /// Ausrufezeichen dafür bringt dem Nutzer bei, rote Ausrufezeichen zu
        /// übersehen. Dann sieht er auch den echten nicht mehr.
        case empty
        case failed(String)

        /// Ob dieser Auftrag gerade einen Arbeiter belegt.
        ///
        /// `review` gehört ausdrücklich nicht dazu: ein fertiger Auftrag wartet auf
        /// den Nutzer, nicht auf Rechenzeit, und darf den nächsten nicht aufhalten.
        var isBusy: Bool {
            switch self {
            case .reading, .looking: return true
            case .waiting, .review, .empty, .failed: return false
            }
        }

        var isWaiting: Bool { self == .waiting }
    }

    let id = UUID()
    var phase: Phase = .waiting

    /// Schon auf Sendegröße verkleinert.
    ///
    /// Und zwar beim Einreihen, nicht erst beim Aufruf: eine Schlange aus zwölf
    /// Handyfotos in voller Auflösung sind einige hundert Megabyte im Speicher, für
    /// Pixel, die weder das Modell noch der Beleg je sieht — beide Wege verkleinern
    /// ohnehin auf dieselbe Kantenlänge.
    let image: UIImage
    /// Das Symbol in der Reihe.
    let thumbnail: UIImage

    var placeID: UUID?
    var hint: String
    var result = IntakeResult()
    /// Was schon vom Modell angekommen ist — nur, damit sichtbar ist, dass etwas
    /// passiert. Das rohe JSON zu zeigen wäre schlechter als ein Kreis; gezeigt wird
    /// die Anzahl der Zeichen.
    var received = 0
    let queuedAt = Date()

    /// Nicht beobachtet: die Aufgabe ist Verwaltung, kein Zustand für die Oberfläche.
    @ObservationIgnored var task: Task<Void, Never>?

    init(image: UIImage, placeID: UUID?, hint: String) {
        self.image = image.scaledDown(maxEdge: 1_400)
        self.thumbnail = image.scaledDown(maxEdge: 240)
        self.placeID = placeID
        self.hint = hint
    }

    var acceptedCount: Int { result.proposals.filter(\.accepted).count }

    /// Was auf dem Symbol steht.
    var badge: String? {
        switch phase {
        case .review: return result.proposals.isEmpty ? "0" : "\(result.proposals.count)"
        case .empty:  return "\u{2013}"
        case .failed: return "!"
        case .waiting, .reading, .looking: return nil
        }
    }
}

/// Wer als Nächstes darf.
///
/// Eigener Typ und eine reine Funktion, weil genau hier der Fehler sitzen würde, den
/// man nicht sieht: zu viele Aufrufe gleichzeitig kosten Geld und holen sich eine
/// Drosselung, zu wenige lassen den Nutzer warten, und ein Auftrag, der im
/// Prüfschritt hängt, darf keinen Arbeiter festhalten. Als Funktion über eine Liste
/// von Phasen ist das prüfbar; als drei Bedingungen mitten in einer Schleife nicht.
enum IntakeSchedule {

    /// Wie viele Aufträge überhaupt in der Reihe stehen dürfen.
    ///
    /// Nicht wegen der Rechenzeit, sondern wegen des Speichers: jedes Foto liegt
    /// verkleinert im Arbeitsspeicher, bis es übernommen oder verworfen ist.
    static let maxQueued = 24

    /// In welchen Grenzen die Gleichzeitigkeit einstellbar ist.
    static let concurrencyRange = 1 ... 6

    /// Die Plätze in der Reihe, die jetzt starten dürfen — in der Reihenfolge, in der
    /// sie eingereiht wurden.
    static func startable(_ phases: [IntakeJob.Phase], concurrency: Int) -> [Int] {
        var free = concurrency.clamped(to: concurrencyRange) - phases.filter(\.isBusy).count
        guard free > 0 else { return [] }

        var out: [Int] = []
        for (index, phase) in phases.enumerated() where phase.isWaiting {
            out.append(index)
            free -= 1
            if free == 0 { break }
        }
        return out
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
