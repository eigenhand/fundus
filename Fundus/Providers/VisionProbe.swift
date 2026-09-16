import UIKit

/// Finds out whether the configured model really reads images.
///
/// Taken over from Faden, and more important for Fundus than it was there: in Faden
/// images were one ingredient, here they are the route by which the inventory comes
/// into being. A model that does not accept images turns this app into a form.
///
/// There is no reliable way of asking an arbitrary endpoint about it — model lists
/// rarely say, and capability fields look different at every provider. So the app tries
/// it: a tiny two-colour image and the question of what is on it. A refusal means no,
/// an answer naming both colours means yes. Nothing is guessed.
enum VisionProbe {

    enum Outcome: Equatable {
        /// The endpoint took the image and the model described it correctly.
        case supported
        /// The image was accepted, but the answer did not name the colours — probably
        /// fine, just unconfirmed.
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

    /// Drawn rather than embedded: a base64 constant would be kilobytes of source for
    /// something two drawing calls produce.
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
                // 4xx here means: the endpoint cannot accept images. 5xx and the rest
                // say nothing about images.
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
