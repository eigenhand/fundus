import UIKit

/// The photos, as files beside the inventory.
///
/// Not in the JSON: an image as base64 inside the inventory would blow the file up
/// several times over, be written on every save and loaded on every start — and Spind
/// would have to transfer the whole inventory again because one photo was added. As a
/// file beside it, taking a photo changes exactly one file.
///
/// The images are the evidence for the entries a model wrote. Whoever stands in front
/// of the shelf later and cannot find the number again can look at what the model saw.
/// That is why they are kept and not discarded after the shot.
enum PhotoStore {
    private static let dirName = "photos"

    private static var dir: URL {
        let url = SharedContainer.directory.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for id: String) -> URL {
        dir.appendingPathComponent(id).appendingPathExtension("jpg")
    }

    /// Stores an image and returns its identifier.
    ///
    /// What gets stored is the scaled-down version, the same one that goes to the
    /// model: an inventory photo is evidence, not a picture archive, and the original
    /// resolution would be several times the space in the synchronised folder for every
    /// shot.
    @discardableResult
    static func save(_ image: UIImage, maxEdge: CGFloat = 1_400,
                     quality: CGFloat = 0.8) -> String? {
        let scaled = image.scaledDown(maxEdge: maxEdge)
        guard let data = scaled.jpegData(compressionQuality: quality) else { return nil }
        let id = UUID().uuidString
        guard (try? data.write(to: url(for: id), options: .atomic)) != nil else { return nil }
        return id
    }

    static func load(_ id: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: id).path)
    }

    static func delete(_ id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Photos no entry points at any more.
    ///
    /// Deleting only happens when asked for. Tidying an image away automatically
    /// because the last entry from it was deleted takes away the evidence for a decision
    /// the user is making right now — and if they want to undo it, the image is gone.
    static func orphans(keeping referenced: Set<String>) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files
            .filter { $0.hasSuffix(".jpg") }
            .map { String($0.dropLast(4)) }
            .filter { !referenced.contains($0) }
    }

    static func totalBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
