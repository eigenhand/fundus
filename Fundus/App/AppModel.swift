import SwiftUI

/// The state of the app in one place.
///
/// The inventory is a value type and sits here as a single property: load, change,
/// save. What concurrency is needed — files, network, the local model — sits behind
/// actors, and everything the interface sees stays on the main actor. That is little
/// architecture for a whole app, and for a few hundred things more is not needed.
@Observable @MainActor
final class AppModel {

    var inventory = Inventory()
    var settings = AppSettings()

    // MARK: Suche

    var query = ""
    var hits: [ItemSearch.Hit] = []
    /// Whether the similarity search contributed to the last result. It stands in the
    /// footer of the hit list, because there is a difference between the app having
    /// searched and the app having understood.
    var semanticContributed = false
    private var searchTask: Task<Void, Never>?

    // MARK: Aufnahme

    /// While a shot is running, its state stands here. `nil` means: none.
    /// The queue of shots — waiting, running and ready to check.
    ///
    /// A list rather than an optional: this used to read `intake: IntakeState?`, and
    /// with that a second photo was only possible once the first was through.
    var jobs: [IntakeJob] = []

    // MARK: Index

    var indexStatus = Indexer.Status()
    var isIndexing = false
    var indexNote = ""

    // MARK: Meldungen

    /// A line that slides in at the top. Errors belong here and not in the console —
    /// what the user does not see did not happen as far as they are concerned.
    var banner: Banner?

    struct Banner: Equatable {
        enum Tone { case info, bad }
        var text: String
        var tone: Tone = .info
    }

    private var saveTask: Task<Void, Never>?

    // MARK: Loading and saving

    func load() async {
        settings = await Store.shared.loadSettings()
        inventory = await Store.shared.loadInventory()
        adoptSharedEndpointIfNeeded()
        refreshIndexStatus()
        // Whatever got no vector last time gets one now. Without fuss and without
        // holding up the interface.
        if settings.indexAutomatically { Task { await indexPending() } }
    }

    /// Takes over an endpoint that a sibling app has left behind.
    ///
    /// Only if none stands here yet — an app that has been set up should not let
    /// itself be reconfigured by another.
    ///
    /// As of today this is the only way Fundus comes by access without somebody
    /// typing. Before it there was a branch for builds with a built-in key; that is
    /// gone, and with it the key in the binary. Whoever has set up Faden on the same
    /// device is still offered its endpoint here — the App Group shares it, and the
    /// user entered it themselves.
    private func adoptSharedEndpointIfNeeded() {
        guard !settings.model.isComplete, let shared = SharedEndpoint.read() else { return }
        settings.model.baseURL = shared.baseURL
        settings.model.path = shared.path
        settings.model.model = shared.model
        settings.model.keychainAccount = shared.keychainAccount
        save()
        banner = Banner(text: String(localized: "Endpoint von \(shared.writtenBy) übernommen."))
    }

    /// Saves with a delay. Twenty keystrokes in a name field should not be twenty
    /// writes to a file that Spind synchronises.
    func save() {
        saveTask?.cancel()
        let snapshot = inventory
        let settingsSnapshot = settings
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Store.shared.save(snapshot)
            await Store.shared.save(settingsSnapshot)
        }
    }

    /// At once and without delay — for the moment the app goes into the background.
    func saveNow() async {
        saveTask?.cancel()
        await Store.shared.save(inventory)
        await Store.shared.save(settings)
    }

    var apiKey: String {
        Keychain.get(account: settings.model.keychainAccount,
                     shared: settings.model.keychainAccount == Keychain.sharedAccount) ?? ""
    }

    var client: ModelClient? {
        guard settings.model.isComplete else { return nil }
        return ModelClient(config: settings.model, apiKey: apiKey)
    }

    // MARK: Dinge

    @discardableResult
    func add(name: String, quantity: Int? = nil, unit: String = "", placeID: UUID? = nil) -> Item? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let item = Item(name: clean, quantity: quantity, unit: unit, placeID: placeID)
        inventory.add(item)
        save()
        if settings.indexAutomatically { Task { await indexPending() } }
        return item
    }

    func update(_ item: Item) {
        let before = inventory.item(item.id)
        inventory.update(item)
        save()
        // The vector belongs to the text. If the text changes, the vector is wrong —
        // not broken, but belonging to the previous name, which is worse.
        if before?.embeddableText != item.embeddableText {
            invalidateEmbedding(of: item.id)
            if settings.indexAutomatically { Task { await indexPending() } }
        }
    }

    func delete(_ id: UUID) {
        inventory.remove(id)
        save()
        refreshIndexStatus()
    }

    /// "Seen." The act on which the reliability of this app rests.
    func markSeen(_ id: UUID) {
        inventory.markSeen(id)
        save()
    }

    private func invalidateEmbedding(of id: UUID) {
        guard let i = inventory.items.firstIndex(where: { $0.id == id }) else { return }
        inventory.items[i].embedding = nil
        inventory.items[i].embeddingStamp = nil
        refreshIndexStatus()
    }

    // MARK: Orte

    @discardableResult
    func addPlace(name: String, under parent: UUID? = nil) -> Place? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let place = Place(name: clean, parentID: parent)
        inventory.addPlace(place)
        save()
        return place
    }

    func removePlace(_ id: UUID) {
        let affected = inventory.items(at: id).count
        inventory.removePlace(id)
        save()
        if affected > 0 {
            banner = Banner(text: affected == 1
                ? String(localized: "1 Ding liegt jetzt nirgends.")
                : String(localized: "\(affected) Dinge liegen jetzt nirgends."))
        }
    }

    // MARK: Suche

    /// Searches with a delay. The text runs through at once — that costs nothing —
    /// the meaning only once the typing stops.
    func searchSoon() {
        let text = ItemSearch.text(query, in: inventory.items)
        hits = ItemSearch.merge(text)
        semanticContributed = false

        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Below three characters, meaning finds nothing useful but costs one request
        // per keystroke against an endpoint.
        guard q.count >= 3 else { return }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.searchSemantic(q)
        }
    }

    private func searchSemantic(_ q: String) async {
        let model = settings.search.effectiveModel
        guard !model.isEmpty else { return }
        let items = inventory.items
        guard Indexer.status(items, model: model).usable > 0 else { return }

        let vector: [Float]
        do {
            vector = try await embedOne(q)
        } catch {
            // Quietly. The text search has already answered, and an error message for
            // something the user did not ask for is noise.
            return
        }
        guard !Task.isCancelled, q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        let centroid = settings.search.needsCentering ? Indexer.centroid(items, model: model) : nil
        let semantic = ItemSearch.semantic(
            vector, in: items, model: model, centroid: centroid,
            minimum: settings.search.minimumSimilarity, limit: settings.search.maxSemanticHits)

        let text = ItemSearch.text(q, in: items)
        hits = ItemSearch.merge(text, semantic)
        semanticContributed = hits.contains { $0.kind == .semantic }
    }

    // MARK: Einbetten

    private func embedOne(_ text: String) async throws -> [Float] {
        let vectors = try await embed([text])
        guard let first = vectors.first else { throw EmbeddingError.failed(String(localized: "Kein Vektor erhalten.")) }
        return first
    }

    private func embed(_ texts: [String]) async throws -> [[Float]] {
        switch settings.search.source {
        case .onDevice:
            return try await LocalEmbedder.shared.embed(texts)
        case .endpoint:
            guard let client else { throw ModelError.notConfigured }
            return try await client.embed(texts, search: settings.search)
        }
    }

    func refreshIndexStatus() {
        indexStatus = Indexer.status(inventory.items, model: settings.search.effectiveModel)
    }

    /// Catches up on whatever has no usable vector yet.
    ///
    /// In small helpings, so that a large inventory does not block the interface, and
    /// saving as it goes: if it breaks off — no network, app in the background, model
    /// not loaded — the work up to that point is not lost.
    func indexPending(batchSize: Int = 24) async {
        guard !isIndexing else { return }
        let model = settings.search.effectiveModel
        guard !model.isEmpty else { return }
        if settings.search.source == .onDevice, !LocalEmbedder.hasAssets { return }

        isIndexing = true
        defer { isIndexing = false; indexNote = ""; refreshIndexStatus() }

        while true {
            let pending = Indexer.needingEmbedding(inventory.items, model: model, limit: batchSize)
            guard !pending.isEmpty else { break }
            indexNote = String(localized: "\(Indexer.status(inventory.items, model: model).needsWork) offen")

            let vectors: [[Float]]
            do {
                vectors = try await embed(pending.map(\.embeddableText))
            } catch {
                banner = Banner(text: String(localized: "Index: \(error.localizedDescription)"), tone: .bad)
                return
            }
            guard vectors.count == pending.count else {
                banner = Banner(text: String(localized: "Index: unerwartete Anzahl Vektoren."), tone: .bad)
                return
            }

            for (item, vector) in zip(pending, vectors) {
                guard let i = inventory.items.firstIndex(where: { $0.id == item.id }) else { continue }
                // Check against the text that was embedded: whoever changes a name
                // during the run would otherwise get the vector of the old one.
                guard inventory.items[i].embeddableText == item.embeddableText else { continue }
                inventory.items[i].embedding = vector
                inventory.items[i].embeddingStamp = EmbeddingStamp(model: model, dimension: vector.count)
            }
            save()
            if Task.isCancelled { return }
        }
    }

    /// Throws away every vector and rebuilds. For a change of source.
    func reindexAll() async {
        for i in inventory.items.indices {
            inventory.items[i].embedding = nil
            inventory.items[i].embeddingStamp = nil
        }
        save()
        refreshIndexStatus()
        await indexPending()
    }

    /// Deletes the index without rebuilding. Frees space and turns the similarity
    /// search off without touching a single entry.
    func dropIndex() {
        for i in inventory.items.indices {
            inventory.items[i].embedding = nil
            inventory.items[i].embeddingStamp = nil
        }
        save()
        refreshIndexStatus()
        banner = Banner(text: String(localized: "Index gelöscht. Die Namenssuche findet weiter alles."))
    }

    // MARK: Aufnahme

    /// Queues photos and lets the workers loose.
    ///
    /// Queuing rather than starting, and that is the whole difference to before:
    /// whoever stands in front of a shelf does not take one photo but twelve. Before,
    /// each one held the screen until the model had finished reading. Now it goes into
    /// the queue, the view stays where it is, and the next photo is one tap away.
    ///
    /// The image is kept *before* the call, not only after confirmation. It is the
    /// evidence for the shot, and it should still be there if the call fails — then
    /// you can try again without walking down to the cellar a second time.
    func enqueue(_ images: [UIImage], placeID: UUID?, hint: String = "") {
        guard client != nil else {
            banner = Banner(text: String(localized: "Kein Modell eingerichtet — ohne Endpoint kann niemand das Foto lesen. Einrichten unter Einstellungen → Modell."),
                            tone: .bad)
            return
        }
        var rejected = 0
        for image in images {
            guard jobs.count < IntakeSchedule.maxQueued else { rejected += 1; continue }
            jobs.append(IntakeJob(image: image, placeID: placeID, hint: hint))
        }
        if rejected > 0 {
            banner = Banner(text: rejected == 1
                ? String(localized: "1 Foto nicht eingereiht — die Reihe fasst \(IntakeSchedule.maxQueued).")
                : String(localized: "\(rejected) Fotos nicht eingereiht — die Reihe fasst \(IntakeSchedule.maxQueued)."),
                            tone: .bad)
        }
        pump()
    }

    /// Starts as many waiting jobs as there are free workers.
    ///
    /// Called after every queuing and after every finished job. A job at the checking
    /// stage holds no worker — otherwise a photo that somebody leaves lying would
    /// block the whole queue.
    private func pump() {
        for index in IntakeSchedule.startable(jobs.map(\.phase),
                                              concurrency: settings.intakeConcurrency) {
            start(jobs[index])
        }
    }

    private func start(_ job: IntakeJob) {
        guard let client else { return }
        job.phase = .reading
        job.received = 0

        let placePath = job.placeID.map { inventory.tree.path(of: $0) }
        let existing = job.placeID.map { inventory.items(at: $0, includingBelow: false).map(\.name) }
            ?? inventory.unplaced.map(\.name)
        let image = job.image
        let hint = job.hint

        // The body runs on the main actor because `start` does — which is why a
        // `defer` is enough here and not a second hop over to it.
        job.task = Task { [weak self, weak job] in
            defer { self?.pump() }
            do {
                let result = try await PhotoIntake(client: client).read(
                    image: image, placePath: placePath, existingNames: existing,
                    hint: hint,
                    onDelta: { piece in
                        Task { @MainActor in job?.received += piece.count }
                    })
                guard let self, let job, self.jobs.contains(where: { $0 === job }) else { return }
                job.result = result
                if result.isEmpty {
                    job.phase = .empty
                    self.announce(job)
                    return
                }

                // Look identifiers up, if that is set up and there are any. At this
                // point the shot has already been paid for and is valid — a failed
                // lookup must therefore not cost it, and `resolve` fails one at a time
                // rather than as a whole.
                if let lookup = self.lookupClient,
                   result.proposals.contains(where: { $0.code?.isSearchable == true }) {
                    job.phase = .looking(done: 0, total: 0)
                    let resolved = await lookup.resolve(result.proposals) { done, total in
                        Task { @MainActor in job.phase = .looking(done: done, total: total) }
                    }
                    guard self.jobs.contains(where: { $0 === job }) else { return }
                    job.result.proposals = resolved
                }
                job.phase = .review
                self.announce(job)
            } catch {
                guard let self, let job, self.jobs.contains(where: { $0 === job }) else { return }
                job.phase = .failed(error.localizedDescription)
                self.announce(job)
            }
        }
    }

    /// Says that a job is done.
    ///
    /// Became necessary with the queue: before, the checking step opened by itself and
    /// you could not miss that something was finished. Whoever keeps taking photos now
    /// would miss it — the symbol in the queue alone is not enough when you are
    /// looking at the shutter.
    private func announce(_ job: IntakeJob) {
        switch job.phase {
        case .review:
            let n = job.result.proposals.count
            banner = Banner(text: n == 1
                ? String(localized: "Aufnahme gelesen — 1 Vorschlag zum Prüfen.")
                : String(localized: "Aufnahme gelesen — \(n) Vorschläge zum Prüfen."))
        case .empty:
            banner = Banner(text: String(localized: "Aufnahme gelesen — auf dem Foto war kein Bestand."))
        case .failed(let message):
            banner = Banner(text: message, tone: .bad)
        default:
            break
        }
    }

    /// Takes over whatever the user has ticked.
    ///
    /// Only here does an entry come into being. Everything before it was a suggestion,
    /// and that difference is the reason this inventory can be believed.
    @discardableResult
    func commit(_ job: IntakeJob) -> (added: Int, increased: Int) {
        let photoID = PhotoStore.save(job.image)

        var added = 0, increased = 0
        for proposal in job.result.proposals where proposal.accepted {
            switch inventory.absorb(proposal, at: job.placeID, photoID: photoID,
                                    model: job.result.model) {
            case .added:     added += 1
            case .increased: increased += 1
            case .skipped:   break
            }
        }
        remove(job)
        save()
        refreshIndexStatus()
        if settings.indexAutomatically { Task { await indexPending() } }

        if added + increased > 0 {
            var parts: [String] = []
            if added > 0 { parts.append(String(localized: "\(added) neu")) }
            if increased > 0 { parts.append(String(localized: "\(increased) erhöht")) }
            banner = Banner(text: parts.joined(separator: ", ") + ".")
        }
        return (added, increased)
    }

    /// Throws a job away — including one that is currently running.
    func discard(_ job: IntakeJob) {
        job.task?.cancel()
        remove(job)
        pump()
    }

    /// Once more, from the top. For a job whose call failed: the photo is still there,
    /// and a second attempt costs no walk down to the cellar.
    func retry(_ job: IntakeJob) {
        switch job.phase {
        case .failed, .empty: break
        default: return
        }
        job.result = IntakeResult()
        job.phase = .waiting
        pump()
    }

    private func remove(_ job: IntakeJob) {
        jobs.removeAll { $0 === job }
    }

    // MARK: Das Erkennungsmodell

    /// How far the download has got. `nil` means: none is running.
    var segmentDownload: RemoteModel.Progress?

    var segmenterInstalled: Bool { SegmentAssets.looksInstalled }
    var segmenterBytes: Int64 { SegmentAssets.model.bytesOnDisk }

    /// Loads the model for tapping in object mode.
    ///
    /// In the background and not in the sheet: the settings can be closed while it
    /// downloads, and eighty megabytes are nothing to sit in front of.
    func downloadSegmenter() {
        guard segmentDownload == nil else { return }
        segmentDownload = .downloading(done: 0, total: SegmentAssets.model.approximateBytes)
        Task { [weak self] in
            await SegmentAssets.model.download { step in
                Task { @MainActor in self?.segmentDownload = step }
            }
            guard let self else { return }
            switch self.segmentDownload {
            case .finished:
                self.banner = Banner(text: String(localized: "Erkennungsmodell ist da."))
            case .failed(let why):
                self.banner = Banner(text: why, tone: .bad)
            default:
                break
            }
            self.segmentDownload = nil
        }
    }

    func removeSegmenter() {
        SegmentAssets.model.remove()
        segmentDownload = nil
        banner = Banner(text: String(localized: "Erkennungsmodell entfernt."))
    }

    // MARK: Einstellungen

    var searchKey: String {
        Keychain.get(account: settings.lookup.keychainAccount, shared: false) ?? ""
    }

    /// Der Nachschlagedienst, sofern eingerichtet.
    var lookupClient: IdentityLookup? {
        guard settings.lookup.isComplete, let client else { return nil }
        return IdentityLookup(
            model: client,
            search: SearchClient(config: settings.lookup, apiKey: searchKey))
    }

    func setSearchKey(_ key: String) {
        Keychain.set(key, account: settings.lookup.keychainAccount, shared: false)
        banner = Banner(text: key.isEmpty ? String(localized: "Suchschlüssel gelöscht.")
                                           : String(localized: "Suchschlüssel gespeichert."))
    }

    func setKey(_ key: String, shared: Bool) {
        let account = shared ? Keychain.sharedAccount : "fundus.model.key"
        Keychain.set(key, account: account, shared: shared)
        settings.model.keychainAccount = account
        if shared { SharedEndpoint.write(settings.model) }
        save()
    }

    func endpointChanged() {
        if settings.model.keychainAccount == Keychain.sharedAccount {
            SharedEndpoint.write(settings.model)
        }
        save()
    }

    /// Switches the vector source. The existing index is not quietly thrown away in
    /// the process — what it is stands in the settings, and what happens to it is the
    /// user's decision.
    func setSearchSource(_ source: SearchConfig.Source) {
        settings.search.source = source
        save()
        refreshIndexStatus()
    }
}
