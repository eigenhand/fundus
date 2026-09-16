import PhotosUI
import SwiftUI

/// Pictures from the photo library.
///
/// `PHPickerViewController` and not `UIImagePickerController`: the picker runs in its
/// own process and therefore needs no access to the photo library — the app gets
/// exactly the pictures the user taps and nothing else. For an app that does not want
/// to collect anything anyway, that is the fitting route.
///
/// Multiple selection, since shots became a queue. Before it would have been pointless:
/// the second picture would have had to wait until the first was through the checking
/// step. Now a walk along a shelf is one gesture — mark twenty photos, queue them, get
/// on with something else.
struct LibraryPicker: UIViewControllerRepresentable {
    var onImages: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        // Not unlimited: the queue holds a fixed number, and a selection half of which
        // silently falls away is worse than a limit the picker itself displays.
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

        /// Loads every selected picture and passes them on in the order in which they
        /// were selected.
        ///
        /// The order is not taste: the user photographed their shelf from left to right,
        /// and the queue should look that way. `loadObject`, however, answers when it is
        /// done — a large picture after a small one. Which is why the results are
        /// written into a fixed-length array and only collected at the end.
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

        /// A fixed-length array with a counter, under a lock.
        ///
        /// `loadObject` calls back from an arbitrary thread, and from a different one
        /// for each picture. Without a lock that would be a race on the same array —
        /// and the counter decides who is last and may pass the result on.
        private final class Slots: @unchecked Sendable {
            private let lock = NSLock()
            private var images: [UIImage?]
            private var remaining: Int

            init(count: Int) {
                images = Array(repeating: nil, count: count)
                remaining = count
            }

            /// Stores one picture and says whether that makes the set complete.
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
