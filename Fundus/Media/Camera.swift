import AVFoundation
import SwiftUI
import UIKit

/// Die Kamera, selbst gehalten.
///
/// Hier hing `UIImagePickerController`: aufmachen, auslösen, bestätigen, zu. Für ein
/// Foto vom Regal ging das. Für einen Kellergang nicht — zwölf Fotos waren zwölfmal
/// derselbe Weg, und zwischen zwei Regalbrettern schloss sich jedes Mal der Sucher.
///
/// Diese Datei ist der Preis dafür, dass er offen bleiben kann. Sie macht nichts
/// Kluges: Sitzung einrichten, Bild auslösen, Bild zurückgeben. Alles, was die
/// Sitzung anfasst, läuft auf `queue` — `startRunning` blockiert, und auf dem
/// Hauptfaden wäre das ein sichtbarer Ruckler beim Aufmachen.
final class CameraSession: NSObject, @unchecked Sendable {

    /// Warum kein Sucher da ist. Jeder Fall braucht eine andere Abhilfe, und „Kamera
    /// nicht verfügbar" für alle drei schickt den Nutzer in die falsche Richtung.
    enum Failure: Equatable {
        /// Der Nutzer hat den Zugriff abgelehnt — nur er kann das zurücknehmen.
        case denied
        /// Kein Gerät mit Kamera. Im Simulator der Normalfall.
        case unavailable
        case broken(String)

        var message: String {
            switch self {
            case .denied:
                return "Fundus darf nicht auf die Kamera. Das lässt sich in den "
                     + "Einstellungen des Geräts unter Fundus ändern."
            case .unavailable:
                return "Dieses Gerät hat keine benutzbare Kamera. Aus der Galerie geht es."
            case .broken(let why):
                return why
            }
        }
    }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "dev.eigenhand.fundus.kamera")

    /// Rechnet aus, wie das Bild zum Horizont steht.
    ///
    /// Die Oberfläche ist auf Hochformat festgelegt, das Gerät ist es nicht: wer ein
    /// breites Regal fotografiert, dreht das Telefon quer. Ohne diese Rechnung käme
    /// das Bild um 90 Grad gekippt beim Modell an — und ein gekipptes Etikett liest
    /// niemand, auch kein Modell.
    private var rotation: AVCaptureDevice.RotationCoordinator?

    /// Was auf ein ausgelöstes Bild wartet, nach Aufnahme-Kennung.
    ///
    /// Eine Ablage und nicht ein einzelner Verweis, weil im Doku-Modus zwei Auslöser
    /// schneller kommen können, als ein Bild fertig wird. Wer den zweiten dann
    /// verwirft, verliert ein Foto, das der Nutzer gemacht zu haben glaubt.
    private var pending: [Int64: @Sendable (UIImage) -> Void] = [:]
    private let lock = NSLock()

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var flashMode: AVCaptureDevice.FlashMode = .auto

    /// Fragt nach Erlaubnis, richtet ein und startet. Gibt zurück, was schiefging.
    func start() async -> Failure? {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .broken("Die Kamera wurde zwischendurch abgeräumt."))
                    return
                }
                let failure = self.configureIfNeeded()
                if failure == nil, !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: failure)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Einmal auslösen. Das Bild kommt auf dem Hauptakteur zurück.
    func capture(_ onImage: @escaping @Sendable (UIImage) -> Void) {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }

            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(self.flashMode) {
                settings.flashMode = self.flashMode
            }
            if let connection = self.output.connection(with: .video),
               let angle = self.rotation?.videoRotationAngleForHorizonLevelCapture,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }

            self.lock.lock()
            self.pending[settings.uniqueID] = onImage
            self.lock.unlock()

            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: Einrichten

    /// Nur einmal, und nur auf `queue`.
    private func configureIfNeeded() -> Failure? {
        guard session.inputs.isEmpty else { return nil }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back)
        else { return .unavailable }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                return .broken("Die Kamera liess sich nicht anschliessen.")
            }
            session.addInput(input)
        } catch {
            return .broken(error.localizedDescription)
        }

        guard session.canAddOutput(output) else {
            return .broken("Die Kamera nimmt keine Fotoausgabe an.")
        }
        session.addOutput(output)

        // Ohne Vorschauebene: die gehört der Oberfläche, und der Winkel, auf den es
        // ankommt, ist der des Geräts zum Horizont — nicht der der Ansicht.
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return nil
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let key = photo.resolvedSettings.uniqueID
        lock.lock()
        let handler = pending.removeValue(forKey: key)
        lock.unlock()

        guard let handler,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else { return }
        handler(image)
    }
}

/// Der Sucher.
///
/// Eine eigene Ebenenklasse statt einer Unterebene: `AVCaptureVideoPreviewLayer` als
/// `layerClass` wächst mit der Ansicht mit, eine hineingelegte muss bei jedem Umbruch
/// von Hand nachgezogen werden — und vergisst man es einmal, steht das Bild schief im
/// Rahmen.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.apply(angle: 90)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        // Die Verbindung steht erst, wenn die Sitzung läuft — beim ersten Aufbau ist
        // sie oft noch nil. Deshalb hier nochmal.
        view.apply(angle: 90)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // Erzwungen, weil `layerClass` es garantiert: eine andere Ebene kann hier
            // nicht stehen.
            layer as! AVCaptureVideoPreviewLayer
        }

        /// Die Oberfläche ist auf Hochformat festgelegt, also steht der Sucher fest
        /// auf 90 Grad. Das Bild selbst richtet sich nach dem Horizont — wie bei der
        /// Kamera des Systems mit gesperrter Drehung.
        func apply(angle: CGFloat) {
            guard let connection = previewLayer.connection,
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
