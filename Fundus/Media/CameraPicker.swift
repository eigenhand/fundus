import SwiftUI
import UIKit

/// Die Kamera, für SwiftUI verpackt.
///
/// Übernommen aus Faden, wo sie eine Zutat war. Hier ist sie der Weg, auf dem dieser
/// Bestand entsteht: wer vor einem Regal steht, fotografiert es, statt vierzig Zeilen
/// zu tippen. Deshalb hängt sie am auffälligsten Knopf der App und nicht in einem
/// Menü.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False in the simulator and on any device without a usable camera.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
