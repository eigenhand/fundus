import PhotosUI
import SwiftUI

/// Bilder aus der Galerie.
///
/// `PHPickerViewController` und nicht `UIImagePickerController`: der Picker läuft in
/// einem eigenen Prozess und braucht deshalb keinen Zugriff auf die Fotobibliothek —
/// die App bekommt genau die Bilder, die der Nutzer antippt, und sonst nichts. Für
/// eine App, die ohnehin nichts sammeln will, ist das der passende Weg.
///
/// Mehrfachauswahl, seit die Aufnahme eine Reihe ist. Vorher wäre sie sinnlos gewesen:
/// das zweite Bild hätte warten müssen, bis das erste durch den Prüfschritt war. Jetzt
/// ist ein Regalgang ein Griff — zwanzig Fotos markieren, einreihen, weiterarbeiten.
struct LibraryPicker: UIViewControllerRepresentable {
    var onImages: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        // Nicht unbegrenzt: die Reihe fasst eine feste Zahl, und eine Auswahl, von der
        // die Hälfte stillschweigend wegfällt, ist schlechter als eine Grenze, die der
        // Picker selbst anzeigt.
        config.selectionLimit = IntakeSchedule.maxQueued
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: LibraryPicker
        init(_ parent: LibraryPicker) { self.parent = parent }

        /// Lädt alle ausgewählten Bilder und gibt sie in der Reihenfolge weiter, in
        /// der sie ausgewählt wurden.
        ///
        /// Die Reihenfolge ist nicht Geschmack: der Nutzer hat sein Regal von links
        /// nach rechts fotografiert, und die Reihe soll so aussehen. `loadObject`
        /// antwortet aber, wann es fertig ist — ein großes Bild nach einem kleinen.
        /// Deshalb wird in ein Feld fester Länge geschrieben und erst am Ende
        /// eingesammelt.
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let usable = results.map(\.itemProvider)
                .filter { $0.canLoadObject(ofClass: UIImage.self) }
            guard !usable.isEmpty else {
                parent.dismiss()
                return
            }

            let slots = Slots(count: usable.count)
            for (index, provider) in usable.enumerated() {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    let done = slots.put(object as? UIImage, at: index)
                    guard done else { return }
                    let images = slots.collected()
                    Task { @MainActor in
                        if !images.isEmpty { self.parent.onImages(images) }
                        self.parent.dismiss()
                    }
                }
            }
        }

        /// Ein Feld fester Länge mit einem Zähler, unter einem Schloss.
        ///
        /// `loadObject` ruft aus einem beliebigen Faden zurück, und zwar für jedes
        /// Bild aus einem anderen. Ohne Schloss wäre das ein Wettlauf auf demselben
        /// Feld — und der Zähler entscheidet, wer der Letzte ist und weitergeben darf.
        private final class Slots: @unchecked Sendable {
            private let lock = NSLock()
            private var images: [UIImage?]
            private var remaining: Int

            init(count: Int) {
                images = Array(repeating: nil, count: count)
                remaining = count
            }

            /// Legt ein Bild ab und sagt, ob damit alle da sind.
            func put(_ image: UIImage?, at index: Int) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                images[index] = image
                remaining -= 1
                return remaining == 0
            }

            func collected() -> [UIImage] {
                lock.lock()
                defer { lock.unlock() }
                return images.compactMap { $0 }
            }
        }
    }
}
