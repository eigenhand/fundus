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
    private var device: AVCaptureDevice?

    /// Was auf ein ausgelöstes Bild wartet, nach Aufnahme-Kennung.
    ///
    /// Eine Ablage und nicht ein einzelner Verweis, weil im Doku-Modus zwei Auslöser
    /// schneller kommen können, als ein Bild fertig wird. Wer den zweiten dann
    /// verwirft, verliert ein Foto, das der Nutzer gemacht zu haben glaubt.
    private var pending: [Int64: @Sendable (UIImage) -> Void] = [:]
    private let lock = NSLock()

    static var isAvailable: Bool { bestCamera() != nil }

    /// Die beste Rückkamera, die dieses Gerät hat.
    ///
    /// Bevorzugt ein **virtuelles** Gerät — Triple, Dual-Wide, Dual — und erst zuletzt
    /// die einzelne Weitwinkellinse. Das ist nicht Ehrgeiz, sondern zwei Dinge, die
    /// sonst fehlen:
    ///
    ///  - **Zoom über die Linsen hinweg.** Auf einem einzelnen Objektiv ist jeder
    ///    Zoom ein Ausschnitt; ein virtuelles Gerät wechselt beim Zoomen selbst auf
    ///    Ultraweitwinkel oder Tele, ohne dass die App davon etwas wissen muss.
    ///  - **Makro.** iOS macht Nahaufnahmen, indem es unter einem gewissen Abstand auf
    ///    das Ultraweitwinkel umschaltet. Ohne virtuelles Gerät passiert das nicht —
    ///    und für eine App, in der Leute Aufdrucke auf Bauteilen fotografieren, ist
    ///    das genau der Fall, auf den es ankommt.
    ///
    /// Beides hatte `UIImagePickerController` mitgebracht und ging verloren, als der
    /// Sucher selbst gebaut wurde.
    static func bestCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
            .builtInWideAngleCamera,
        ]
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .back).devices
        for type in types {
            if let device = found.first(where: { $0.deviceType == type }) { return device }
        }
        return found.first
    }

    /// Was der Sucher über den Zoom wissen muss.
    struct Zoom: Sendable, Equatable {
        /// In Geräteeinheiten.
        var minimum: CGFloat = 1
        var maximum: CGFloat = 1
        /// Wo „1×" liegt. Auf einem Gerät mit Ultraweitwinkel ist das **nicht** 1:
        /// dort ist 1 das Ultraweitwinkel, also „0,5×".
        var baseline: CGFloat = 1
        /// Die Stellen, an denen die Linse wechselt — daraus werden die Knöpfe.
        var stops: [CGFloat] = [1]

        var current: CGFloat = 1

        /// Was auf dem Knopf steht: 0,5× statt 1,0.
        func label(_ factor: CGFloat) -> String {
            let shown = factor / baseline
            let rounded = (shown * 10).rounded() / 10
            return rounded == rounded.rounded()
                ? "\(Int(rounded))×"
                : String(format: "%.1f×", rounded).replacingOccurrences(of: ".", with: ",")
        }
    }

    /// Nur lesen, und nur auf dem Hauptakteur — der Sucher zeigt es an.
    private(set) nonisolated(unsafe) var zoom = Zoom()

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
        guard let device = Self.bestCamera() else { return .unavailable }
        self.device = device

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
        zoom = Self.zoomRange(of: device)
        applyZoom(zoom.baseline)     // bei „1×" aufmachen, nicht beim Ultraweitwinkel
        return nil
    }
}

extension CameraSession {

    /// Der Zoombereich dieses Geräts, samt der Stellen, an denen die Linse wechselt.
    ///
    /// Die Umrechnung auf „×" ist der heikle Teil. `videoZoomFactor` 1 ist die
    /// **weiteste** Linse, die das virtuelle Gerät hat — bei einem Triple oder
    /// Dual-Wide also das Ultraweitwinkel, das der Nutzer als 0,5× kennt. Bei einem
    /// Dual (Weitwinkel + Tele) ist 1 dagegen schon 1×. Die Schaltpunkte allein
    /// verraten das nicht; was es verrät, ist, ob ein Ultraweitwinkel verbaut ist.
    static func zoomRange(of device: AVCaptureDevice) -> Zoom {
        zoomRange(
            switchOver: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            hasUltraWide: device.constituentDevices
                .contains { $0.deviceType == .builtInUltraWideCamera },
            minimum: device.minAvailableVideoZoomFactor,
            maximum: device.maxAvailableVideoZoomFactor)
    }

    /// Dieselbe Rechnung ohne Gerät, damit sie prüfbar ist.
    ///
    /// Ein `AVCaptureDevice` laesst sich nicht bauen, und die Zahlen unterscheiden
    /// sich von Telefon zu Telefon — die Regel dahinter nicht.
    static func zoomRange(switchOver: [CGFloat], hasUltraWide: Bool,
                          minimum: CGFloat, maximum deviceMaximum: CGFloat) -> Zoom {
        let baseline = hasUltraWide ? (switchOver.first ?? 1) : 1

        // Über das Achtfache hinaus ist es Brei. Wer den Aufdruck lesen will, kommt
        // näher heran — dafür gibt es den Makro.
        let maximum = min(deviceMaximum, baseline * 8)

        var stops = [minimum]
        stops += switchOver.filter { $0 > minimum && $0 < maximum }
        if !stops.contains(where: { abs($0 - baseline) < 0.01 }), baseline < maximum {
            stops.append(baseline)
        }
        stops.sort()

        return Zoom(minimum: minimum, maximum: maximum, baseline: baseline,
                    stops: stops, current: baseline)
    }

    /// Setzt den Zoom. Aus der Oberfläche gerufen, ausgeführt auf dem eigenen Faden.
    ///
    /// `smooth` für Knöpfe, damit es gleitet; für die Zwei-Finger-Geste nicht — die
    /// soll den Fingern folgen und nicht hinterherlaufen.
    func setZoom(_ factor: CGFloat, smooth: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            self.applyZoom(factor, smooth: smooth)
        }
    }

    private func applyZoom(_ factor: CGFloat, smooth: Bool = false) {
        guard let device else { return }
        let wanted = min(max(factor, zoom.minimum), zoom.maximum)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if smooth {
                device.ramp(toVideoZoomFactor: wanted, withRate: 8)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = wanted
            }
            zoom.current = wanted
        } catch {
            // Ein gesperrtes Gerät ist kein Grund, die Aufnahme abzubrechen — es
            // bleibt eben beim bisherigen Ausschnitt.
        }
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
