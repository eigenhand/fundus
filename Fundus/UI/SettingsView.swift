import SwiftUI

/// Einstellungen. Vier Fragen: welches Modell, woher die Vektoren, wo die Daten
/// liegen, und was im Index steckt.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var shareKey = true
    @State private var probing = false
    @State private var probeResult: VisionProbe.Outcome?
    @State private var assetState = AssetState.unknown
    @State private var exportURL: URL?
    @State private var confirmDrop = false

    private enum AssetState { case unknown, missing, loading, present, failed(String) }

    var body: some View {
        ZStack {
            EH.scene
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    modelSection
                    searchSection
                    indexSection
                    storageSection
                    aboutSection
                }
                .padding(.horizontal, EH.gutter)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: prime)
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
        .confirmationDialog("Suchindex löschen?", isPresented: $confirmDrop,
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { model.dropIndex() }
        } message: {
            Text("Kein Eintrag wird angerührt. Die Namenssuche findet weiter alles, "
                 + "die Suche nach Bedeutung nicht mehr.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Einstellungen")
                .font(.brand(21))
                .foregroundStyle(EH.navy)
            Spacer()
            Button("Fertig") { dismiss() }
                .font(.eh(15, .callout))
                .foregroundStyle(EH.slate)
                .buttonStyle(EHTap())
        }
        .padding(.top, 18)
    }

    // MARK: Modell

    @ViewBuilder
    private var modelSection: some View {
        SectionLabel(text: "Modell")

        if BundledSetup.isManaged {
            HairlineCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dieser Build bringt einen Zugang mit.")
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                    Text("\(BundledSetup.providerName) · \(BundledSetup.chatModel)")
                        .font(EH.mono)
                        .foregroundStyle(EH.muted)
                    Text("Für die Testrunde. Eine normal installierte Fundus bringt "
                         + "keinen Zugang mit — dann stehen hier die Felder.")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                }
            }
        } else {
            VStack(spacing: 0) {
                field("Adresse", text: Binding(
                    get: { model.settings.model.baseURL },
                    set: { model.settings.model.baseURL = $0 }),
                      placeholder: "https://api.beispiel.ai")
                Divider().overlay(EH.hair)
                field("Pfad", text: Binding(
                    get: { model.settings.model.path },
                    set: { model.settings.model.path = $0 }),
                      placeholder: "/v1/chat/completions", mono: true)
                Divider().overlay(EH.hair)
                field("Modell", text: Binding(
                    get: { model.settings.model.model },
                    set: { model.settings.model.model = $0 }),
                      placeholder: "anbieter/modellname", mono: true)
                Divider().overlay(EH.hair)
                keyField
                Divider().overlay(EH.hair)
                tokenField
            }
            .onDisappear { model.endpointChanged() }

            Toggle(isOn: $shareKey) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mit Spind und Faden teilen")
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.navy)
                    Text("Legt Adresse und Modell im gemeinsamen Ordner ab und den "
                         + "Schlüssel in der gemeinsamen Schlüsselbundgruppe. Wer eine "
                         + "der Apps einrichtet, hat alle eingerichtet.")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                }
            }
            .tint(EH.navy)
            .padding(.vertical, 12)
        }

        probeRow
    }

    /// Sichtbar und verstellbar, weil die richtige Zahl vom Modell abhaengt.
    ///
    /// Ein Reasoning-Modell verbraucht den Vorrat zweimal: erst zum Nachdenken, dann
    /// zum Schreiben. Wer in die Grenze laeuft, soll das hier aendern koennen und
    /// nicht auf einen neuen Build warten muessen.
    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 3) {
            EH.label("Ausgabetoken, hoechstens")
            HStack(spacing: 10) {
                TextField("32000", value: Binding(
                    get: { model.settings.model.maxOutputTokens },
                    set: { model.settings.model.maxOutputTokens = max(256, min(200_000, $0)) }),
                          format: .number.grouping(.never))
                    .font(EH.mono)
                    .foregroundStyle(EH.navy)
                    .keyboardType(.numberPad)
                Spacer(minLength: 0)
            }
            Text("Reasoning-Modelle brauchen den Vorrat doppelt — erst zum Nachdenken, "
                 + "dann zum Schreiben. Zu wenig sieht aus wie eine leere Antwort.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .padding(.top, 2)
        }
        .padding(.vertical, 12)
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 3) {
            EH.label("Schlüssel")
            HStack(spacing: 10) {
                SecureField(model.apiKey.isEmpty ? "sk-…" : "hinterlegt", text: $key)
                    .font(EH.mono)
                    .foregroundStyle(EH.navy)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !key.isEmpty {
                    Button("Speichern") {
                        model.setKey(key, shared: shareKey)
                        key = ""
                    }
                    .font(.eh(13, .footnote, weight: .medium))
                    .foregroundStyle(EH.navy)
                    .buttonStyle(EHTap())
                }
            }
        }
        .padding(.vertical, 11)
    }

    /// „Prüfen“ statt „Speichern“: ob ein Endpoint Bilder liest, ist die Frage, an
    /// der diese App hängt, und niemand sollte sie erst beim ersten Regalfoto
    /// gestellt bekommen.
    @ViewBuilder
    private var probeRow: some View {
        HStack(spacing: 12) {
            Button(probing ? "Prüft …" : "Bilder prüfen") {
                Task { await probe() }
            }
            .buttonStyle(EHButtonStyle())
            .disabled(probing || model.client == nil)

            if probing { ProgressView().tint(EH.slate) }
            Spacer()
        }
        .padding(.top, 12)

        if let probeResult {
            HairlineCard(fill: probeResult.isGood ? EH.surface : EH.surfaceSunk) {
                Text(probeResult.text)
                    .font(EH.bodySmall)
                    .foregroundStyle(probeResult.isGood ? EH.good : EH.bad)
                    .lineSpacing(3)
            }
            .padding(.top, 8)
        }
    }

    private func probe() async {
        guard let client = model.client else { return }
        probing = true
        probeResult = await VisionProbe.run(client: client)
        probing = false
    }

    // MARK: Suche

    @ViewBuilder
    private var searchSection: some View {
        SectionLabel(text: "Suche")

        Text("Die Namenssuche läuft immer und braucht nichts. Für die Suche nach "
             + "Bedeutung — „das Kabel mit dem eckigen Stecker“ — werden Vektoren "
             + "gebraucht, und die kommen von hier.")
            .font(EH.bodySmall)
            .foregroundStyle(EH.slate)
            .lineSpacing(3)
            .padding(.bottom, 12)

        ForEach(SearchConfig.Source.allCases, id: \.self) { source in
            sourceRow(source)
        }

        if model.settings.search.source == .onDevice {
            assetRow
        } else {
            VStack(spacing: 0) {
                Divider().overlay(EH.hair)
                field("Einbettungsmodell", text: Binding(
                    get: { model.settings.search.embeddingModel },
                    set: { model.settings.search.embeddingModel = $0; model.save() }),
                      placeholder: "anbieter/embedding-modell", mono: true)
            }
        }
    }

    private func sourceRow(_ source: SearchConfig.Source) -> some View {
        let active = model.settings.search.source == source
        return Button {
            model.setSearchSource(source)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(active ? EH.navy : EH.hairStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source == .onDevice ? "Auf dem Gerät" : "Über den Endpoint")
                        .font(EH.body)
                        .foregroundStyle(EH.navy)
                    Text(source == .onDevice
                         ? "Apples Modell, 108 MB, 8 ms je Eintrag. Gröber, aber ohne Netz — "
                           + "und ein Keller hat selten Empfang."
                         : "Genauer, kostet aber bei jeder Suche eine Anfrage.")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
        }
        .buttonStyle(EHTap())
    }

    @ViewBuilder
    private var assetRow: some View {
        switch assetState {
        case .present:
            Text("Das Modell liegt auf dem Gerät.")
                .font(EH.meta)
                .foregroundStyle(EH.good)
                .padding(.vertical, 8)
        case .missing, .failed:
            VStack(alignment: .leading, spacing: 8) {
                if case .failed(let message) = assetState {
                    Text(message)
                        .font(EH.meta)
                        .foregroundStyle(EH.bad)
                        .lineSpacing(2)
                }
                Button("Modell laden (108 MB)") {
                    Task { await loadAssets() }
                }
                .buttonStyle(EHButtonStyle())
            }
            .padding(.vertical, 8)
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(EH.slate)
                Text("Lädt. Das System sagt nicht, wie weit es ist.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }
            .padding(.vertical, 8)
        case .unknown:
            Text("Dieses Gerät kennt das lokale Modell nicht.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .padding(.vertical, 8)
        }
    }

    private func loadAssets() async {
        assetState = .loading
        do {
            try await LocalEmbedder.requestAssets()
            assetState = LocalEmbedder.hasAssets ? .present : .missing
            if LocalEmbedder.hasAssets { await model.indexPending() }
        } catch {
            assetState = LocalEmbedder.hasAssets ? .present : .failed(error.localizedDescription)
        }
    }

    // MARK: Index

    /// Was im Index steckt, gezählt statt behauptet.
    ///
    /// Genau die Ansicht, die in Faden gefehlt hat: „nutzbar / fremd / fehlt“, und
    /// welche Modelle überhaupt drinliegen. Ohne sie ist ein Wechsel der Quelle eine
    /// Änderung, deren Folgen man erst merkt, wenn die Suche nichts mehr findet.
    @ViewBuilder
    private var indexSection: some View {
        SectionLabel(text: "Suchindex")

        let status = model.indexStatus
        HairlineCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    count("nutzbar", status.usable, EH.good)
                    count("fremd", status.foreign, EH.warn)
                    count("fehlt", status.missing, EH.muted)
                }

                if let dimension = status.dimension {
                    Text("\(model.settings.search.effectiveModel) · \(dimension) Dimensionen")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                }

                if status.byModel.count > 1 || (status.byModel.keys.first.map {
                    EmbeddingStamp.normalise($0) != EmbeddingStamp.normalise(model.settings.search.effectiveModel)
                } ?? false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Im Index liegen:")
                            .font(EH.meta)
                            .foregroundStyle(EH.muted)
                        ForEach(status.byModel.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                            Text("\(entry.value)× \(entry.key)")
                                .font(EH.mono)
                                .foregroundStyle(EH.muted)
                        }
                    }
                }

                if model.isIndexing {
                    HStack(spacing: 8) {
                        ProgressView().tint(EH.slate)
                        Text(model.indexNote)
                            .font(EH.meta)
                            .foregroundStyle(EH.muted)
                    }
                }
            }
        }

        Toggle(isOn: Binding(
            get: { model.settings.indexAutomatically },
            set: { model.settings.indexAutomatically = $0; model.save() })) {
            Text("Neue Einträge automatisch einbetten")
                .font(EH.bodySmall)
                .foregroundStyle(EH.navy)
        }
        .tint(EH.navy)
        .padding(.vertical, 12)

        HStack(spacing: 10) {
            Button(status.needsWork > 0 ? "Nachholen (\(status.needsWork))" : "Neu aufbauen") {
                Task {
                    if status.needsWork > 0 { await model.indexPending() }
                    else { await model.reindexAll() }
                }
            }
            .buttonStyle(EHButtonStyle())
            .disabled(model.isIndexing || status.total == 0)

            if status.usable + status.foreign > 0 {
                Button("Index löschen") { confirmDrop = true }
                    .buttonStyle(EHButtonStyle())
            }
            Spacer()
        }
    }

    private func count(_ label: String, _ n: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(n)")
                .font(.eh(20, .title3, weight: .medium))
                .foregroundStyle(n > 0 ? color : EH.muted)
                .monospacedDigit()
            Text(label)
                .font(EH.meta)
                .foregroundStyle(EH.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Speicher

    @ViewBuilder
    private var storageSection: some View {
        SectionLabel(text: "Wo die Daten liegen")

        VStack(alignment: .leading, spacing: 8) {
            Text(SharedContainer.describe)
                .font(EH.bodySmall)
                .foregroundStyle(SharedContainer.isShared ? EH.slate : EH.warn)
                .lineSpacing(3)

            let bytes = PhotoStore.totalBytes()
            if bytes > 0 {
                Text("Fotos: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }

            Text("Klartext-JSON. Der Bestand gehört dir, nicht dieser App.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
        }
        .padding(.vertical, 4)

        Button("Bestand ausgeben") {
            Task { exportURL = await Store.shared.exportInventory(model.inventory) }
        }
        .buttonStyle(EHButtonStyle())
        .padding(.top, 10)
    }

    // MARK: Über

    @ViewBuilder
    private var aboutSection: some View {
        SectionLabel(text: "Fundus")
        Text("Ein Lagerbestand fürs iPhone, der nichts mitbringt außer der Oberfläche. "
             + "Modell, Endpoint und Schlüssel kommen von dir. Kein Konto, kein "
             + "Zwischenserver, keine Telemetrie.")
            .font(EH.bodySmall)
            .foregroundStyle(EH.slate)
            .lineSpacing(3)
            .padding(.vertical, 4)
        Text("eigenhand.dev")
            .font(EH.meta)
            .foregroundStyle(EH.muted)
            .padding(.top, 6)
    }

    // MARK: Kleinteile

    private func field(_ label: String, text: Binding<String>,
                       placeholder: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            EH.label(label)
            TextField(placeholder, text: text)
                .font(mono ? EH.mono : EH.body)
                .foregroundStyle(EH.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 11)
    }

    private func prime() {
        shareKey = model.settings.model.keychainAccount == Keychain.sharedAccount
        model.refreshIndexStatus()
        if !LocalEmbedder.isSupported { assetState = .unknown }
        else { assetState = LocalEmbedder.hasAssets ? .present : .missing }
    }
}

/// Das Teilen-Blatt des Systems, für die ausgegebene Datei.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `sheet(item:)` braucht `Identifiable`; eine URL ist durch sich selbst bestimmt.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
