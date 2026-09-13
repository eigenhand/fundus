import PhotosUI
import SwiftUI

/// Ein Bild aus der Galerie.
///
/// `PHPickerViewController` und nicht `UIImagePickerController`: der Picker läuft in
/// einem eigenen Prozess und braucht deshalb keinen Zugriff auf die Fotobibliothek —
/// die App bekommt genau das Bild, das der Nutzer antippt, und sonst nichts. Für
/// eine App, die ohnehin nichts sammeln will, ist das der passende Weg.
struct LibraryPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: LibraryPicker
        init(_ parent: LibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                parent.dismiss()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else {
                    Task { @MainActor in self.parent.dismiss() }
                    return
                }
                Task { @MainActor in
                    self.parent.onImage(image)
                    self.parent.dismiss()
                }
            }
        }
    }
}
