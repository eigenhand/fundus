import Foundation

/// A model that comes off the network at runtime.
///
/// Describes **what** gets downloaded; the how stands here once and not again in every
/// model. There are two of them by now — SAM 2.1 at 80 MB for tapping and SAM 3.1 at
/// 1.7 GB for the text search — and a second downloader would be a second place where
/// resuming can break.
struct RemoteModel: Sendable {
    /// The folder under `eigenhand/` in which the files live.
    let folder: String
    /// The directory on Hugging Face, with a trailing slash.
    let source: String
    /// The files, relative to both. An `.mlpackage` is a directory and gets reassembled
    /// file by file.
    let files: [String]
    /// Approximate, for the display before the download.
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

    /// Whether every file is there — and not merely begun.
    ///
    /// The check is against the size the server states and not merely for existence: a
    /// half-downloaded `weight.bin` is a file that exists, and all Core ML says about
    /// it is "could not be loaded".
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

    /// Downloads what is missing and resumes what has been begun.
    ///
    /// Resumable, and that is not a luxury: 67 MB over mobile data breaks off, and a
    /// manager that then starts from zero is the difference between "works" and "never
    /// works". `URLSession.download(from:)` cannot do it by itself — hence a range
    /// header and an append to the file that is already there.
    func download(onProgress: @escaping @Sendable (Progress) -> Void) async {
        var sizes: [String: Int64] = [:]
        for file in files {
            guard let size = await remoteSize(file) else {
                onProgress(.failed(String(localized: "Die Modelldateien sind gerade nicht erreichbar.")))
                return
            }
            sizes[file] = size
        }
        let total = sizes.values.reduce(0, +)
        guard total > 0 else {
            onProgress(.failed(String(localized: "Die Modelldateien sind gerade nicht erreichbar.")))
            return
        }

        /// Whatever is already on disk counts as done.
        var settled = files.reduce(Int64(0)) { sum, file in
            sum + min(Self.fileSize(url(for: file)) ?? 0, sizes[file] ?? 0)
        }
        onProgress(.downloading(done: settled, total: total))

        for file in files {
            let target = url(for: file)
            let want = sizes[file] ?? 0
            let have = Self.fileSize(target) ?? 0
            if have == want, want > 0 { continue }
            // Larger than expected means: broken. Once more from the top.
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
                                     : .failed(String(localized: "Der Download ist unvollstaendig geblieben.")))
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

    /// One file, from byte `offset` onwards, appended to what is already there.
    ///
    /// With a `URLSessionDownloadTask` and not with `bytes(for:)`: the byte stream can
    /// be walked elegantly enough, but at 67 MB that is 67 million `await`s. It costs
    /// more time than the connection does.
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
        // If the server does not honour the range it starts at zero — then nothing may
        // be appended, or the file ends up written twice in a row.
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

/// A download with progress, wrapped in async/await.
///
/// The detour through a delegate is the price for having both at once: a file written
/// to disk rather than into memory, and a number that runs along with it.
/// `URLSession.download(for:)` can only do the first.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<(URL, Int), Error>?
    private var session: URLSession?
    /// So that the continuation is resumed exactly once — both callbacks can arrive,
    /// and a second `resume` is a crash, not an error.
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
        // The file at `location` is deleted once this returns — so move it before the
        // callback ends.
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
