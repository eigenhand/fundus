import UIKit

/// Die Fotos, als Dateien neben dem Bestand.
///
/// Nicht im JSON: ein Bild als base64 im Bestand würde die Datei auf ein Vielfaches
/// aufblähen, bei jedem Speichern mitgeschrieben und bei jedem Start mitgeladen
/// werden — und Spind müsste den ganzen Bestand neu übertragen, weil ein Foto
/// dazukam. Als Datei daneben ändert sich beim Fotografieren genau eine Datei.
///
/// Die Bilder sind der Beleg zu den Einträgen, die ein Modell geschrieben hat. Wer
/// später vor dem Regal steht und die Zahl nicht wiederfindet, kann nachsehen, was
/// das Modell gesehen hat. Deshalb werden sie behalten und nicht nach der Aufnahme
/// verworfen.
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

    /// Legt ein Bild ab und gibt seine Kennung zurück.
    ///
    /// Gespeichert wird die verkleinerte Fassung, dieselbe, die an das Modell geht:
    /// ein Bestandsfoto ist ein Beleg, kein Bildarchiv, und die Originalauflösung
    /// wäre pro Aufnahme ein Vielfaches an Platz im synchronisierten Ordner.
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

    /// Fotos, auf die kein Eintrag mehr verweist.
    ///
    /// Gelöscht wird nur auf Ansage. Ein Bild automatisch mitzuräumen, weil der
    /// letzte Eintrag daraus gelöscht wurde, nimmt dem Nutzer den Beleg für eine
    /// Entscheidung, die er gerade trifft — und wenn er sie rückgängig machen will,
    /// ist das Bild dann weg.
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
