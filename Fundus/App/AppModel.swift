import SwiftUI

/// Der Zustand der App an einer Stelle.
///
/// Der Bestand ist ein Werttyp und liegt hier als eine Eigenschaft: laden, ändern,
/// speichern. Was an Nebenläufigkeit nötig ist — Dateien, Netz, das lokale Modell —
/// steckt hinter Aktoren, und alles, was die Oberfläche sieht, bleibt auf dem
/// Hauptakteur. Das ist wenig Architektur für eine ganze App, und für einige hundert
/// Dinge ist mehr auch nicht nötig.
@Observable @MainActor
final class AppModel {

    var inventory = Inventory()
    var settings = AppSettings()

    // MARK: Suche

    var query = ""
    var hits: [ItemSearch.Hit] = []
    /// Ob die Ähnlichkeitssuche zum letzten Ergebnis beigetragen hat. Steht in der
    /// Fußzeile der Trefferliste, denn es ist ein Unterschied, ob die App gesucht
    /// oder verstanden hat.
    var semanticContributed = false
    private var searchTask: Task<Void, Never>?

    // MARK: Aufnahme

    /// Läuft eine Aufnahme, steht hier ihr Zustand. `nil` heißt: keine.
    var intake: IntakeState?

    // MARK: Index

    var indexStatus = Indexer.Status()
    var isIndexing = false
    var indexNote = ""

    // MARK: Meldungen

    /// Eine Zeile, die oben einläuft. Fehler gehören hierher und nicht in die
    /// Konsole — was der Nutzer nicht sieht, ist für ihn nicht passiert.
    var banner: Banner?

    struct Banner: Equatable {
        enum Tone { case info, bad }
        var text: String
        var tone: Tone = .info
    }

    private var saveTask: Task<Void, Never>?

    // MARK: Laden und Speichern

    func load() async {
        settings = await Store.shared.loadSettings()
        inventory = await Store.shared.loadInventory()
        adoptSharedEndpointIfNeeded()
        refreshIndexStatus()
        // Was beim letzten Mal keinen Vektor bekam, bekommt ihn jetzt. Ohne Aufhebens
        // und ohne die Oberfläche aufzuhalten.
        if settings.indexAutomatically { Task { await indexPending() } }
    }

    /// Nimmt einen Endpoint, den eine Schwester-App hinterlegt hat.
    ///
    /// Nur, wenn hier noch keiner steht — eine eingerichtete App soll sich nicht von
    /// einer anderen umkonfigurieren lassen. Der eingebaute Beta-Schlüssel hat
    /// Vorrang, weil ein TestFlight-Build für sich funktionieren muss.
    private func adoptSharedEndpointIfNeeded() {
        if BundledSetup.isManaged, !settings.model.isComplete {
            Keychain.set(BundledSetup.apiKey, account: BundledSetup.keychainAccount)
            settings.model.baseURL = BundledSetup.baseURL
            settings.model.path = BundledSetup.chatPath
            settings.model.model = BundledSetup.chatModel
            settings.model.maxOutputTokens = BundledSetup.maxOutputTokens
            settings.model.keychainAccount = BundledSetup.keychainAccount
            save()
            return
        }
        guard !settings.model.isComplete, let shared = SharedEndpoint.read() else { return }
        settings.model.baseURL = shared.baseURL
        settings.model.path = shared.path
        settings.model.model = shared.model
        settings.model.keychainAccount = shared.keychainAccount
        save()
        banner = Banner(text: "Endpoint von \(shared.writtenBy) übernommen.")
    }

    /// Speichert verzögert. Zwanzig Tastendrücke in einem Namensfeld sollen nicht
    /// zwanzig Schreibvorgänge in eine Datei sein, die Spind synchronisiert.
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

    /// Sofort und ohne Verzögerung — für den Moment, in dem die App in den
    /// Hintergrund geht.
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
        // Der Vektor gilt für den Text. Ändert sich der Text, ist der Vektor falsch —
        // nicht kaputt, sondern zum vorigen Namen gehörend, was schlimmer ist.
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

    /// „Gesehen.“ Die Handlung, auf der die Verlässlichkeit dieser App beruht.
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
            banner = Banner(text: "\(affected) \(affected == 1 ? "Ding liegt" : "Dinge liegen") jetzt nirgends.")
        }
    }

    // MARK: Suche

    /// Sucht verzögert. Der Text läuft sofort durch — das kostet nichts —, die
    /// Bedeutung erst, wenn das Tippen aufhört.
    func searchSoon() {
        let text = ItemSearch.text(query, in: inventory.items)
        hits = ItemSearch.merge(text)
        semanticContributed = false

        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unter drei Zeichen findet Bedeutung nichts Sinnvolles, kostet aber bei
        // einem Endpoint eine Anfrage pro Tastendruck.
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
            // Still. Die Textsuche hat schon geantwortet, und eine Fehlermeldung für
            // etwas, das der Nutzer nicht angefordert hat, ist Lärm.
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
        guard let first = vectors.first else { throw EmbeddingError.failed("Kein Vektor erhalten.") }
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

    /// Holt nach, was noch keinen brauchbaren Vektor hat.
    ///
    /// In Häppchen, damit ein großer Bestand die Oberfläche nicht blockiert, und mit
    /// Zwischenspeichern: bricht es ab — kein Netz, App im Hintergrund, Modell nicht
    /// geladen —, ist die Arbeit bis dahin nicht verloren.
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
            indexNote = "\(Indexer.status(inventory.items, model: model).needsWork) offen"

            let vectors: [[Float]]
            do {
                vectors = try await embed(pending.map(\.embeddableText))
            } catch {
                banner = Banner(text: "Index: \(error.localizedDescription)", tone: .bad)
                return
            }
            guard vectors.count == pending.count else {
                banner = Banner(text: "Index: unerwartete Anzahl Vektoren.", tone: .bad)
                return
            }

            for (item, vector) in zip(pending, vectors) {
                guard let i = inventory.items.firstIndex(where: { $0.id == item.id }) else { continue }
                // Gegen den Text prüfen, der eingebettet wurde: wer während des
                // Durchlaufs einen Namen ändert, bekäme sonst den Vektor des alten.
                guard inventory.items[i].embeddableText == item.embeddableText else { continue }
                inventory.items[i].embedding = vector
                inventory.items[i].embeddingStamp = EmbeddingStamp(model: model, dimension: vector.count)
            }
            save()
            if Task.isCancelled { return }
        }
    }

    /// Wirft alle Vektoren weg und baut neu. Für den Wechsel der Quelle.
    func reindexAll() async {
        for i in inventory.items.indices {
            inventory.items[i].embedding = nil
            inventory.items[i].embeddingStamp = nil
        }
        save()
        refreshIndexStatus()
        await indexPending()
    }

    /// Löscht den Index, ohne neu zu bauen. Gibt Platz frei und macht die
    /// Ähnlichkeitssuche aus, ohne einen Eintrag anzurühren.
    func dropIndex() {
        for i in inventory.items.indices {
            inventory.items[i].embedding = nil
            inventory.items[i].embeddingStamp = nil
        }
        save()
        refreshIndexStatus()
        banner = Banner(text: "Index gelöscht. Die Namenssuche findet weiter alles.")
    }

    // MARK: Aufnahme

    /// Schickt ein Foto zum Lesen und öffnet den Prüfschritt.
    ///
    /// Das Bild wird *vor* dem Aufruf gespeichert, nicht nach der Bestätigung. Es
    /// ist der Beleg zur Aufnahme, und es soll auch dann noch da sein, wenn der
    /// Aufruf fehlschlägt — dann kann man es nochmal versuchen, ohne noch einmal in
    /// den Keller zu gehen.
    func startIntake(image: UIImage, placeID: UUID?, hint: String) {
        guard let client else {
            banner = Banner(text: "Kein Modell eingerichtet — ohne Endpoint kann niemand das Foto lesen.",
                            tone: .bad)
            return
        }
        let state = IntakeState(image: image, placeID: placeID, hint: hint)
        intake = state

        let placePath = placeID.map { inventory.tree.path(of: $0) }
        let existing = placeID.map { inventory.items(at: $0, includingBelow: false).map(\.name) }
            ?? inventory.unplaced.map(\.name)

        Task { [weak self] in
            do {
                let result = try await PhotoIntake(client: client).read(
                    image: image, placePath: placePath, existingNames: existing,
                    hint: hint,
                    onDelta: { piece in
                        Task { @MainActor in state.received += piece.count }
                    })
                guard let self, self.intake === state else { return }
                state.result = result
                state.phase = .review
                if result.isEmpty {
                    state.phase = .failed("Auf dem Bild war nichts Bestandsfähiges zu erkennen.")
                }
            } catch {
                guard let self, self.intake === state else { return }
                state.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Übernimmt, was der Nutzer angehakt hat.
    ///
    /// Erst hier entsteht ein Eintrag. Alles davor waren Vorschläge, und der
    /// Unterschied ist der Grund, warum man diesem Bestand glauben kann.
    @discardableResult
    func commitIntake() -> (added: Int, increased: Int) {
        guard let state = intake else { return (0, 0) }
        let photoID = PhotoStore.save(state.image)

        var added = 0, increased = 0
        for proposal in state.result.proposals where proposal.accepted {
            switch inventory.absorb(proposal, at: state.placeID, photoID: photoID,
                                    model: state.result.model) {
            case .added:     added += 1
            case .increased: increased += 1
            case .skipped:   break
            }
        }
        intake = nil
        save()
        refreshIndexStatus()
        if settings.indexAutomatically { Task { await indexPending() } }

        if added + increased > 0 {
            var parts: [String] = []
            if added > 0 { parts.append("\(added) neu") }
            if increased > 0 { parts.append("\(increased) erhöht") }
            banner = Banner(text: parts.joined(separator: ", ") + ".")
        }
        return (added, increased)
    }

    func cancelIntake() { intake = nil }

    // MARK: Einstellungen

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

    /// Wechselt die Vektorquelle. Der bestehende Index wird dabei nicht heimlich
    /// weggeworfen — was er ist, steht in den Einstellungen, und was damit passiert,
    /// entscheidet der Nutzer.
    func setSearchSource(_ source: SearchConfig.Source) {
        settings.search.source = source
        save()
        refreshIndexStatus()
    }
}

/// Der Zustand einer laufenden Aufnahme.
///
/// Eigener Typ, weil eine Aufnahme vier Phasen hat und jede etwas anderes anzeigt.
/// Als vier Bools in `AppModel` wären davon sechzehn Zustände darstellbar, von denen
/// zwölf Unsinn sind.
@Observable @MainActor
final class IntakeState {
    enum Phase: Equatable {
        case reading
        case review
        case failed(String)
    }

    var phase: Phase = .reading
    var image: UIImage
    var placeID: UUID?
    var hint: String
    var result = IntakeResult()
    /// Was schon vom Modell angekommen ist — nur, damit sichtbar ist, dass etwas
    /// passiert. Das rohe JSON zu zeigen wäre schlechter als ein Kreis; gezeigt wird
    /// die Anzahl der Zeichen.
    var received = 0

    init(image: UIImage, placeID: UUID?, hint: String) {
        self.image = image
        self.placeID = placeID
        self.hint = hint
    }

    var acceptedCount: Int { result.proposals.filter(\.accepted).count }
}
