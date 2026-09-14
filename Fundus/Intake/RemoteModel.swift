import Foundation

/// Ein Modell, das zur Laufzeit vom Netz kommt.
///
/// Beschreibt, **was** geladen wird; das Wie steht einmal hier und nicht in jedem
/// Modell noch einmal. Zwei gibt es inzwischen — SAM 2.1 mit 80 MB fuer den
/// Fingertipp und SAM 3.1 mit 1,7 GB fuer die Textsuche —, und ein zweiter Lader
/// waere ein zweiter Ort, an dem das Fortsetzen kaputtgehen kann.
struct RemoteModel: Sendable {
    /// Der Ordner unter `eigenhand/`, in dem die Dateien liegen.
    let folder: String
    /// Das Verzeichnis auf Hugging Face, mit Schraegstrich am Ende.
    let source: String
    /// Die Dateien, relativ zu beidem. Ein `.mlpackage` ist ein Verzeichnis und wird
    /// Datei fuer Datei wieder zusammengesetzt.
    let files: [String]
    /// Ungefaehr, fuer die Anzeige vor dem Download.
    let approximateBytes: Int64

    var directory: URL {
        let base = SharedContainer.sharedDirectory ?? SharedContainer.directory
        let dir = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func url(for file: String) -> URL { directory.appendingPathComponent(file) }

    var compiledDirectory: URL {
        let dir = directory.appendingPathComponent("compiled", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Ob alle Dateien da sind — und nicht nur angefangen.
    ///
    /// Geprueft wird gegen die Groesse, die der Server nennt, und nicht nur auf
    /// Vorhandensein: eine halb geladene `weight.bin` ist eine Datei, die es gibt, und
    /// Core ML sagt dazu nur „konnte nicht geladen werden".
    func isComplete(_ expected: [String: Int64]) -> Bool {
        files.allSatisfy { file in
            guard let size = Self.fileSize(url(for: file)) else { return false }
            guard let want = expected[file] else { return size > 0 }
            return size == want
        }
    }

    var looksInstalled: Bool {
        files.allSatisfy { (Self.fileSize(url(for: $0)) ?? 0) > 0 }
    }

    var bytesOnDisk: Int64 {
        files.reduce(0) { $0 + (Self.fileSize(url(for: $1)) ?? 0) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let value = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber else { return nil }
        return value.int64Value
    }

    // MARK: Laden

    enum Progress: Sendable, Equatable {
        case downloading(done: Int64, total: Int64)
        case finished
        case failed(String)
    }

    /// Laedt, was fehlt, und setzt fort, was angefangen ist.
    ///
    /// Fortsetzbar, und das ist kein Luxus: 67 MB ueber Mobilfunk reissen ab, und ein
    /// Verwalter, der dann bei null anfaengt, ist der Unterschied zwischen „geht" und
    /// „geht nie". `URLSession.download(from:)` kann das nicht von sich aus — deshalb
    /// ein Range-Kopf und ein Anhaengen an die Datei, die schon daliegt.
    func download(onProgress: @escaping @Sendable (Progress) -> Void) async {
        var sizes: [String: Int64] = [:]
        for file in files {
            guard let size = await remoteSize(file) else {
                onProgress(.failed("Die Modelldateien sind gerade nicht erreichbar."))
                return
            }
            sizes[file] = size
        }
        let total = sizes.values.reduce(0, +)
        guard total > 0 else {
            onProgress(.failed("Die Modelldateien sind gerade nicht erreichbar."))
            return
        }

        /// Was schon auf der Platte liegt, zaehlt als erledigt.
        var settled = files.reduce(Int64(0)) { sum, file in
            sum + min(Self.fileSize(url(for: file)) ?? 0, sizes[file] ?? 0)
        }
        onProgress(.downloading(done: settled, total: total))

        for file in files {
            let target = url(for: file)
            let want = sizes[file] ?? 0
            let have = Self.fileSize(target) ?? 0
            if have == want, want > 0 { continue }
            // Groesser als erwartet heisst: kaputt. Noch einmal von vorn.
            if have > want { try? FileManager.default.removeItem(at: target) }
            let from = have > want ? 0 : have

            do {
                let base = settled
                try await fetch(file, to: target, from: from) { got in
                    onProgress(.downloading(done: base + got, total: total))
                }
                settled = base + (want - from)
            } catch {
                onProgress(.failed(error.localizedDescription))
                return
            }
        }
        onProgress(isComplete(sizes) ? .finished
                                     : .failed("Der Download ist unvollstaendig geblieben."))
    }

    private func remoteSize(_ file: String) async -> Int64? {
        guard let url = URL(string: source + file) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        guard let (_, response) = try? await Net.session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              http.expectedContentLength > 0 else { return nil }
        return http.expectedContentLength
    }

    /// Eine Datei, ab Byte `offset`, angehaengt an das, was schon daliegt.
    ///
    /// Mit einem `URLSessionDownloadTask` und nicht mit `bytes(for:)`: der
    /// Byte-Datenstrom laesst sich zwar elegant durchlaufen, aber bei 67 MB sind das
    /// 67 Millionen `await`. Das kostet mehr Zeit als die Leitung.
    private func fetch(_ file: String, to target: URL, from offset: Int64,
                              onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        guard let url = URL(string: source + file) else { throw ModelError.notConfigured }
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let download = FileDownload(onProgress: onProgress)
        let (temporary, status) = try await download.run(request)
        defer { try? FileManager.default.removeItem(at: temporary) }

        guard (200 ... 299).contains(status) else {
            throw ModelError.http(status: status, body: "")
        }
        // Beantwortet der Server den Bereich nicht, faengt er bei null an — dann darf
        // nicht angehaengt werden, sonst steht die Datei zweimal hintereinander.
        let appending = offset > 0 && status == 206

        if appending, FileManager.default.fileExists(atPath: target.path) {
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(contentsOf: temporary, options: .mappedIfSafe))
        } else {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    }
}

/// Ein Download mit Fortschritt, in async/await verpackt.
///
/// Der Umweg ueber einen Delegierten ist der Preis fuer beides zugleich: eine Datei,
/// die auf die Platte geschrieben wird statt in den Speicher, und eine Zahl, die
/// dabei mitlaeuft. `URLSession.download(for:)` kann nur das Erste.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<(URL, Int), Error>?
    private var session: URLSession?
    /// Damit die Fortsetzung genau einmal ausgeloest wird — beide Rueckrufe koennen
    /// kommen, und ein zweites `resume` ist ein Absturz, kein Fehler.
    private var settled = false
    private let lock = NSLock()

    init(onProgress: @escaping @Sendable (Int64) -> Void) {
        self.onProgress = onProgress
    }

    func run(_ request: URLRequest) async throws -> (URL, Int) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 1_800
            configuration.waitsForConnectivity = true
            let session = URLSession(configuration: configuration, delegate: self,
                                     delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    private func finish(_ result: Result<(URL, Int), Error>) {
        lock.lock()
        let first = !settled
        settled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard first, let continuation else { return }
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // Die Datei an `location` wird nach der Rueckkehr geloescht — also weg damit,
        // bevor der Rueckruf endet.
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: keep)
            finish(.success((keep, status)))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish(.failure(error))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten)
    }
}
