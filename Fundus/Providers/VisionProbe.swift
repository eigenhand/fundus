import UIKit

/// Findet heraus, ob das eingerichtete Modell wirklich Bilder liest.
///
/// Übernommen aus Faden, und für Fundus wichtiger als dort: in Faden waren Bilder
/// eine Zutat, hier sind sie der Weg, auf dem der Bestand entsteht. Ein Modell, das
/// keine Bilder annimmt, macht diese App zu einem Formular.
///
/// Es gibt keine verlässliche Möglichkeit, einen beliebigen Endpoint danach zu
/// fragen — Modelllisten sagen es selten, und Fähigkeitsfelder sehen bei jedem
/// Anbieter anders aus. Also probiert die App es: ein winziges Zweifarbenbild und
/// die Frage, was darauf ist. Eine Ablehnung heißt nein, eine Antwort, die beide
/// Farben nennt, heißt ja. Geraten wird nichts.
enum VisionProbe {

    enum Outcome: Equatable {
        /// Der Endpoint nahm das Bild und das Modell hat es richtig beschrieben.
        case supported
        /// Das Bild wurde angenommen, aber die Antwort nannte die Farben nicht —
        /// wahrscheinlich in Ordnung, nur unbestätigt.
        case acceptedButUnconfirmed(String)
        case notSupported(String)
        case inconclusive(String)

        var isGood: Bool {
            switch self {
            case .supported, .acceptedButUnconfirmed: return true
            case .notSupported, .inconclusive:        return false
            }
        }

        var text: String {
            switch self {
            case .supported:
                return "Das Modell liest Bilder — Farben richtig benannt."
            case .acceptedButUnconfirmed(let reply):
                return "Das Bild wurde angenommen, die Antwort war aber nicht eindeutig: „\(reply)“"
            case .notSupported(let message):
                return message
            case .inconclusive(let message):
                return message
            }
        }
    }

    /// Gezeichnet statt eingebettet: eine base64-Konstante wären Kilobytes Quelltext
    /// für etwas, das zwei Zeichenbefehle erzeugen.
    static func probeImage() -> Data? {
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                            format: format).image { ctx in
            UIColor(red: 0.91, green: 0.50, blue: 0.16, alpha: 1).setFill()      // orange, oben
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
            UIColor(red: 0.48, green: 0.31, blue: 0.75, alpha: 1).setFill()      // violett, unten
            ctx.fill(CGRect(x: 0, y: side / 2, width: side, height: side / 2))
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    private static let question = """
    Das Bild besteht aus zwei waagerechten Farbflächen. Nenne nur die beiden Farben, \
    obere zuerst, getrennt durch ein Komma. Keine weiteren Worte.
    """

    static func run(client: ModelClient) async -> Outcome {
        guard let jpeg = probeImage() else {
            return .inconclusive("Das Testbild ließ sich nicht erzeugen.")
        }
        let reply: String
        do {
            reply = try await client.read(imageJPEG: jpeg, prompt: question,
                                          system: "Du antwortest knapp.")
        } catch let error as ModelError {
            if case .http(let status, let body) = error {
                // 4xx heißt hier: der Endpoint kann keine Bilder annehmen.
                // 5xx und der Rest sagen nichts über Bilder aus.
                if (400 ... 499).contains(status) {
                    return .notSupported("Der Endpoint hat das Bild abgelehnt (HTTP \(status)). "
                                         + ModelError.readable(body))
                }
                return .inconclusive("HTTP \(status) — das sagt nichts über Bilder aus.")
            }
            return .inconclusive(error.errorDescription ?? "Unklar.")
        } catch {
            return .inconclusive(error.localizedDescription)
        }

        let answer = reply.lowercased()
        let sawOrange = ["orange", "orangefarben"].contains { answer.contains($0) }
        let sawViolet = ["violett", "lila", "purpur", "purple", "violet"].contains { answer.contains($0) }
        if sawOrange && sawViolet { return .supported }
        return .acceptedButUnconfirmed(String(reply.prefix(80)))
    }
}
