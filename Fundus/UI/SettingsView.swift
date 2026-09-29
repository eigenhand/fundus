import SwiftUI

/// Settings. Four questions: which model, where the vectors come from, where the data
/// lives, and what is in the index.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var lookupKey = ""
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
                    intakeSection
                    lookupSection
                    searchSection
                    indexSection
                    storageSection
                    interfaceSection
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
            Text("Kein Eintrag wird angerührt. Die Namenssuche findet weiter alles, die Suche nach Bedeutung nicht mehr.")
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

        VStack(spacing: 0) {
            field("Adresse", text: Binding(
                get: { model.settings.model.baseURL },
                set: { model.settings.model.baseURL = $0 }),
                  placeholder: String(localized: "https://api.beispiel.ai"))
            Divider().overlay(EH.hair)
            field("Pfad", text: Binding(
                get: { model.settings.model.path },
                set: { model.settings.model.path = $0 }),
                  placeholder: "/v1/chat/completions", mono: true)
            Divider().overlay(EH.hair)
            field("Modell", text: Binding(
                get: { model.settings.model.model },
                set: { model.settings.model.model = $0 }),
                  placeholder: String(localized: "anbieter/modellname"), mono: true)
            Divider().overlay(EH.hair)
            keyField
            Divider().overlay(EH.hair)
            tokenField
        }
        .onDisappear { model.endpointChanged() }

        Toggle(isOn: $shareKey) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modellzugang gemeinsam ablegen")
                    .font(EH.bodySmall)
                    .foregroundStyle(EH.navy)
                Text("Legt Adresse und Modell im gemeinsamen Ordner der eigenhand-Apps ab und den Schlüssel in der gemeinsamen Schlüsselbundgruppe. Andere eigenhand-Apps könnten beides dort lesen – heute tut das noch keine.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }
        }
        .tint(EH.navy)
        .padding(.vertical, 12)

        probeRow
    }

    /// Visible and adjustable, because the right number depends on the model.
    ///
    /// A reasoning model spends the budget twice: first on thinking, then on writing.
    /// Whoever runs into the limit should be able to change it here rather than having
    /// to wait for a new build.
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
            Text("Reasoning-Modelle brauchen den Vorrat doppelt — erst zum Nachdenken, dann zum Schreiben. Zu wenig sieht aus wie eine leere Antwort.")
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

    /// "Check" rather than "save": whether an endpoint reads images is the question
    /// this app hangs on, and nobody should have it put to them for the first time with
    /// their first photo of a shelf.
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

    // MARK: Nummern nachschlagen

    /// Off until somebody enters a key.
    ///
    /// The same premise as for the model: the app brings no infrastructure of its own.
    /// And here silence would be more expensive than there — with the search switched
    /// on, a number from the user's cellar leaves the device.
    /// How many photos are read at once.
    ///
    /// A setting and not a constant, because the right number does not depend on the
    /// app but on the provider: one accepts six calls side by side, the next throttles
    /// from two onwards and answers with 429. The app can know neither, and the user
    /// notices both at once.
    @ViewBuilder
    private var intakeSection: some View {
        SectionLabel(text: "Aufnahme")

        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: Binding(
                get: { model.settings.intakeConcurrency },
                set: { model.settings.intakeConcurrency = $0; model.save() }),
                    in: IntakeSchedule.concurrencyRange) {
                HStack(spacing: 8) {
                    Text("Gleichzeitig lesen")
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.navy)
                    Text("\(model.settings.intakeConcurrency)")
                        .font(EH.mono.weight(.medium))
                        .foregroundStyle(EH.navy)
                        .monospacedDigit()
                }
            }
            .tint(EH.navy)

            segmenterRow

            Text("Fotos kommen in eine Reihe und werden nebeneinander gelesen. Mehr gleichzeitig heisst frueher fertig \u{2014} bis der Anbieter drosselt. Wer 429 oder Zeitablaeufe sieht, stellt es herunter. Die Reihe fasst \(IntakeSchedule.maxQueued) Aufnahmen.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .lineSpacing(2)
        }
        .padding(.vertical, 12)
    }

    /// The model for tapping in object mode.
    ///
    /// Eighty megabytes, which is why it says here what they buy and what happens
    /// without them — a button with a number behind it and no reason given is either
    /// never pressed or pressed blindly.
    @ViewBuilder
    private var segmenterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Gegenstaende erkennen")
                    .font(EH.bodySmall)
                    .foregroundStyle(EH.navy)
                Spacer(minLength: 0)

                switch model.segmentDownload {
                case .downloading(let done, let total):
                    Text(total > 0 ? "\(done * 100 / total) %" : "laedt …")
                        .font(EH.meta)
                        .foregroundStyle(EH.slate)
                        .monospacedDigit()
                case .failed, .finished, .none:
                    if model.segmenterInstalled {
                        Button("Entfernen") { model.removeSegmenter() }
                            .font(.eh(14, .footnote))
                            .foregroundStyle(EH.slate)
                            .buttonStyle(EHTap())
                    } else {
                        Button("Laden (80 MB)") { model.downloadSegmenter() }
                            .font(.eh(14, .footnote, weight: .medium))
                            .foregroundStyle(EH.navy)
                            .buttonStyle(EHTap())
                    }
                }
            }

            if case .downloading(let done, let total) = model.segmentDownload, total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(EH.navy)
            }

            Text(model.segmenterInstalled
                 ? "Im Objekte-Modus tippst du auf ein Ding, und das Geraet sagt, wo es aufhoert. Liegt auf dem Geraet (\(ByteCountFormatter.string(fromByteCount: model.segmenterBytes, countStyle: .file)))."
                 : "Ohne dieses Modell sucht sich das Geraet im Objekte-Modus selbst aus, was ein Gegenstand ist — das ist fuer Portraits gebaut und liegt an einer Werkbank oft daneben. Mit ihm entscheidet dein Finger. Segment Anything 2.1 von Apple, Apache-2.0, laeuft auf dem Geraet.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .lineSpacing(2)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var lookupSection: some View {
        SectionLabel(text: "Nummern nachschlagen")

        Toggle(isOn: Binding(
            get: { model.settings.lookup.enabled },
            set: { model.settings.lookup.enabled = $0; model.save() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kennungen im Netz aufloesen")
                    .font(EH.bodySmall)
                    .foregroundStyle(EH.navy)
                Text("Steht auf einem Ding eine Herstellernummer, oder entziffert das Geraet einen Strichcode, sucht die App danach und legt bis zu drei Moeglichkeiten vor. Ausgewaehlt ist keine: du tippst die richtige an, oder keine. Die Nummer steht daneben.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
                    .lineSpacing(2)
            }
        }
        .tint(EH.navy)
        .padding(.vertical, 12)

        if model.settings.lookup.enabled {
            VStack(spacing: 0) {
                field("Adresse", text: Binding(
                    get: { model.settings.lookup.url },
                    set: { model.settings.lookup.url = $0; model.save() }),
                      placeholder: "https://api.search.brave.com/res/v1/web/search",
                      mono: true)
                Divider().overlay(EH.hair)
                field("Schluessel-Kopfzeile", text: Binding(
                    get: { model.settings.lookup.keyHeader },
                    set: { model.settings.lookup.keyHeader = $0; model.save() }),
                      placeholder: "X-Subscription-Token", mono: true)
                Divider().overlay(EH.hair)
                searchKeyField
            }

            Text("Voreingestellt auf Brave Search — derselbe Schluessel, den Faden benutzt. Jeder Dienst geht, der JSON mit Titel, Adresse und Beschreibung liefert. Hoechstens \(IdentityLookup.maxPerIntake) Nummern je Aufnahme: ein voller Werkzeugkoffer kostet sonst vierzig Suchen und vierzig Modellaufrufe fuer eine Liste, die vielleicht verworfen wird.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .lineSpacing(2)
                .padding(.top, 8)
        }
    }

    private var searchKeyField: some View {
        VStack(alignment: .leading, spacing: 3) {
            EH.label("Suchschluessel")
            HStack(spacing: 10) {
                SecureField(model.searchKey.isEmpty ? "BSA…" : "hinterlegt",
                            text: $lookupKey)
                    .font(EH.mono)
                    .foregroundStyle(EH.navy)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !lookupKey.isEmpty {
                    Button("Speichern") {
                        model.setSearchKey(lookupKey)
                        lookupKey = ""
                    }
                    .font(EH.bodySmall.weight(.medium))
                    .foregroundStyle(EH.navy)
                    .buttonStyle(EHTap())
                }
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Suche

    @ViewBuilder
    private var searchSection: some View {
        SectionLabel(text: "Suche")

        Text("Die Namenssuche läuft immer und braucht nichts. Für die Suche nach Bedeutung — „das Kabel mit dem eckigen Stecker“ — werden Vektoren gebraucht, und die kommen von hier.")
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
                      placeholder: String(localized: "anbieter/embedding-modell"), mono: true)
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
                         ? "Apples Modell, 108 MB, 8 ms je Eintrag. Gröber, aber ohne Netz — und ein Keller hat selten Empfang."
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

    /// What is in the index, counted rather than asserted.
    ///
    /// Exactly the view Faden was missing: "usable / foreign / absent", and which models
    /// are in there at all. Without it, changing the source is a change whose
    /// consequences you only notice once the search stops finding anything.
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

    private func count(_ label: LocalizedStringKey, _ n: Int, _ color: Color) -> some View {
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

    // MARK: Interface

    // Stands far down: whoever opens the app for the first time has to set up a model.
    // The language is something you go looking for when you go looking for it.
    @ViewBuilder
    private var interfaceSection: some View {
        SectionLabel(text: "Oberfläche")
        HStack {
            Text("Sprache")
                .font(EH.body)
                .foregroundStyle(EH.navy)
            Spacer()
            Picker("Sprache", selection: Binding(
                get: { model.settings.language },
                set: { model.settings.language = $0; model.save() })) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(EH.navy)
            // An identifier and not text: this picker's label carries its own selection
            // in it, and a test looking for that label would, after a switch, be
            // looking for something other than before.
            .accessibilityIdentifier("language-picker")
        }
        .padding(.vertical, 4)
        HStack {
            Text("Erscheinungsbild")
                .font(EH.body)
                .foregroundStyle(EH.navy)
            Spacer()
            Picker("Erscheinungsbild", selection: Binding(
                get: { model.settings.appearance },
                set: { model.settings.appearance = $0; model.save() })) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(EH.navy)
            .accessibilityIdentifier("appearance-picker")
        }
        .padding(.vertical, 4)
        // A literal and not a concatenation: Xcode only enters whole strings into the
        // catalogue. A sentence assembled with + can never be translated, and nobody
        // notices — it simply stays in German.
        Text("Gilt für die Oberfläche. Systemdialoge — etwa die Frage nach der Kamera — folgen weiterhin der Spracheinstellung des Geräts.")
            .font(EH.meta)
            .foregroundStyle(EH.muted)
            .lineSpacing(3)
    }

    // MARK: About

    @ViewBuilder
    private var aboutSection: some View {
        SectionLabel(text: "Fundus")
        Text("Ein Lagerbestand fürs iPhone, der nichts mitbringt außer der Oberfläche. Modell, Endpoint und Schlüssel kommen von dir. Kein Konto, kein Zwischenserver, keine Telemetrie.")
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

    private func field(_ label: LocalizedStringKey, text: Binding<String>,
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

/// The system share sheet, for the exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `sheet(item:)` needs `Identifiable`; a URL is identified by itself.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
