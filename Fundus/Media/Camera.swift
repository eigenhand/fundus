import AVFoundation
import SwiftUI
import UIKit

/// The camera, held ourselves.
///
/// `UIImagePickerController` used to hang here: open, shutter, confirm, close. For one
/// photo of a shelf that was fine. For a walk through a cellar it was not — twelve
/// photos were twelve times the same route, and between two shelf boards the
/// viewfinder closed every time.
///
/// This file is the price for it being able to stay open. It does nothing clever: set
/// up the session, take the picture, hand the picture back. Everything that touches
/// the session runs on `queue` — `startRunning` blocks, and on the main thread that
/// would be a visible stutter on opening.
final class CameraSession: NSObject, @unchecked Sendable {

    /// Why there is no viewfinder. Each case needs a different remedy, and "camera
    /// unavailable" for all three sends the user in the wrong direction.
    enum Failure: Equatable {
        /// The user refused access — only they can take that back.
        case denied
        /// No device with a camera. The normal case in the simulator.
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

    /// Works out how the picture stands relative to the horizon.
    ///
    /// The interface is pinned to portrait, the device is not: whoever photographs a
    /// wide shelf turns the phone sideways. Without this arithmetic the picture would
    /// arrive at the model tilted by 90 degrees — and nobody reads a tilted label, a
    /// model included.
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var device: AVCaptureDevice?

    /// What is waiting for a captured picture, by shot identifier.
    ///
    /// A table and not a single reference, because in documentation mode two shutter
    /// presses can arrive faster than one picture finishes. Discarding the second one
    /// loses a photo the user believes they took.
    private var pending: [Int64: @Sendable (UIImage) -> Void] = [:]
    private let lock = NSLock()

    static var isAvailable: Bool { bestCamera() != nil }

    /// The best rear camera this device has.
    ///
    /// Prefers a **virtual** device — triple, dual wide, dual — and only falls back to
    /// the single wide-angle lens. That is not ambition but two things that would
    /// otherwise be missing:
    ///
    ///  - **Zoom across the lenses.** On a single lens every zoom is a crop; a virtual
    ///    device switches to ultra-wide or telephoto by itself as you zoom, without
    ///    the app needing to know anything about it.
    ///  - **Macro.** iOS takes close-ups by switching to the ultra-wide below a certain
    ///    distance. Without a virtual device that does not happen — and for an app in
    ///    which people photograph the lettering on components, that is exactly the
    ///    case that matters.
    ///
    /// `UIImagePickerController` had brought both along, and both were lost when the
    /// viewfinder was built by hand.
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

    /// What the viewfinder needs to know about the zoom.
    struct Zoom: Sendable, Equatable {
        /// In device units.
        var minimum: CGFloat = 1
        var maximum: CGFloat = 1
        /// Where "1×" sits. On a device with an ultra-wide this is **not** 1: there, 1
        /// is the ultra-wide, that is, "0.5×".
        var baseline: CGFloat = 1
        /// The points at which the lens changes — the buttons are made from these.
        var stops: [CGFloat] = [1]

        var current: CGFloat = 1

        /// What stands on the button: 0.5× rather than 1.0.
        func label(_ factor: CGFloat) -> String {
            let shown = factor / baseline
            let rounded = (shown * 10).rounded() / 10
            return rounded == rounded.rounded()
                ? "\(Int(rounded))×"
                : String(format: "%.1f×", rounded).replacingOccurrences(of: ".", with: ",")
        }
    }

    /// Read only, and only on the main actor — the viewfinder displays it.
    private(set) nonisolated(unsafe) var zoom = Zoom()

    var flashMode: AVCaptureDevice.FlashMode = .auto

    /// Asks for permission, sets up and starts. Returns whatever went wrong.
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

    /// One shutter press. The picture comes back on the main actor.
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

    /// Once only, and only on `queue`.
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

        // Without the preview layer: that belongs to the interface, and the angle that
        // matters is the device's against the horizon — not the view's.
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        zoom = Self.zoomRange(of: device)
        applyZoom(zoom.baseline)     // bei „1×" aufmachen, nicht beim Ultraweitwinkel
        return nil
    }
}

extension CameraSession {

    /// The zoom range of this device, together with the points at which the lens
    /// changes.
    ///
    /// Converting to "×" is the delicate part. `videoZoomFactor` 1 is the **widest**
    /// lens the virtual device has — on a triple or a dual wide, therefore, the
    /// ultra-wide that the user knows as 0.5×. On a dual (wide + telephoto), 1 is
    /// already 1×. The switch-over points alone do not reveal that; what does reveal
    /// it is whether an ultra-wide is fitted.
    static func zoomRange(of device: AVCaptureDevice) -> Zoom {
        zoomRange(
            switchOver: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            hasUltraWide: device.constituentDevices
                .contains { $0.deviceType == .builtInUltraWideCamera },
            minimum: device.minAvailableVideoZoomFactor,
            maximum: device.maxAvailableVideoZoomFactor)
    }

    /// The same arithmetic without a device, so that it can be tested.
    ///
    /// An `AVCaptureDevice` cannot be constructed, and the numbers differ from phone
    /// to phone — the rule behind them does not.
    static func zoomRange(switchOver: [CGFloat], hasUltraWide: Bool,
                          minimum: CGFloat, maximum deviceMaximum: CGFloat) -> Zoom {
        let baseline = hasUltraWide ? (switchOver.first ?? 1) : 1

        // Beyond eight times it is mush. Whoever wants to read the lettering moves
        // closer — that is what macro is for.
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

    /// Sets the zoom. Called from the interface, carried out on its own thread.
    ///
    /// `smooth` for buttons, so that it glides; not for the pinch gesture — that
    /// should follow the fingers and not run along behind them.
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
            // A locked device is no reason to abandon the shot — it simply stays at
            // the crop it had.
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

/// The viewfinder.
///
/// Its own layer class rather than a sublayer: `AVCaptureVideoPreviewLayer` as
/// `layerClass` grows with the view, while one placed inside it has to be resized by
/// hand on every layout pass — and forget that once and the picture sits crooked in
/// the frame.
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
        // The connection only exists once the session is running — on the first pass
        // it is often still nil. Hence again here.
        view.apply(angle: 90)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // Forced because `layerClass` guarantees it: no other layer can stand here.
            layer as! AVCaptureVideoPreviewLayer
        }

        /// The interface is pinned to portrait, so the viewfinder stands fixed at 90
        /// degrees. The picture itself follows the horizon — as in the system camera
        /// with rotation locked.
        func apply(angle: CGFloat) {
            guard let connection = previewLayer.connection,
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
