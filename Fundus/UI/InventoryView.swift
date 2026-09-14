import SwiftUI

/// Der Bestand. Die eine Liste, die diese App ist.
///
/// Als `List` und nicht als `ScrollView` mit `LazyVStack`, wie es Faden im Chat
/// macht: Wischgesten gibt es nur in einer Liste, und „Gesehen“ mit einem Wisch ist
/// die Handlung, von der die Verlässlichkeit dieses Bestands abhängt. Sie hinter ein
/// langes Drücken zu legen hieße, sie nicht zu benutzen. Der Preis ist, dass die
/// Liste zurechtgebogen werden muss, damit die Szene hinter ihr durchscheint —
/// das sind vier Zeilen und lohnt sich.
struct InventoryView: View {
    @Environment(AppModel.self) private var model

    @State private var showSettings = false
    @State private var showPlaces = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showManual = false
    @State private var pendingPlace: UUID?
    @State private var onlyStale = false
    /// Der Auftrag, den der Nutzer aus der Reihe angetippt hat.
    @State private var openJob: IntakeJob?

    var body: some View {
        NavigationStack {
            ZStack {
                EH.scene
                BrandWatermark()

                VStack(spacing: 0) {
                    header
                    content
                    IntakeQueueStrip(open: $openJob)
                    actionBar
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ItemDetailView(itemID: id)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPlaces) { PlacesView() }
        .sheet(isPresented: $showManual) {
            ManualEntrySheet(placeID: pendingPlace)
                .presentationDetents([.height(280)])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                model.enqueue([image], placeID: pendingPlace)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker { images in
                model.enqueue(images, placeID: pendingPlace)
            }
        }
        // Der Prüfschritt ist kein Blatt über der Liste, sondern der ganze Bildschirm:
        // dort lenkt alles dahinter von der einzigen Frage ab, die zählt — stimmt,
        // was das Modell gelesen hat.
        //
        // Er springt aber nicht mehr von selbst auf. Wer gerade das nächste Regal
        // fotografiert, will nicht von einer fertigen Aufnahme unterbrochen werden;
        // die meldet sich über die Zeile oben und wartet als Symbol in der Reihe.
        .fullScreenCover(item: $openJob) { job in
            IntakeView(job: job)
        }
    }

    // `@Environment` liefert keine Bindung, und ein lokales `@Bindable` gilt nur in
    // dem Gültigkeitsbereich, in dem es steht — `body` reicht damit nicht bis in
    // `header`. Ausgeschrieben ist es zwei Zeilen länger und an jeder Stelle gültig.
    private var queryBinding: Binding<String> {
        Binding(get: { model.query }, set: { model.query = $0 })
    }

    // MARK: Kopf

    private var header: some View {
        VStack(spacing: 12) {
            AppHeader(title: "Fundus", subtitle: subtitle) {
                HStack(spacing: 8) {
                    RoundIconButton(systemName: "tray.2", label: "Orte") { showPlaces = true }
                    RoundIconButton(systemName: "gearshape", label: "Einstellungen") {
                        showSettings = true
                    }
                }
            }

            if let banner = model.banner {
                BannerView(banner: banner) { model.banner = nil }
            }

            SearchField(text: queryBinding) { model.searchSoon() }

            if staleCount > 0 && model.query.isEmpty {
                filterRow
            }
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.2), value: model.banner)
    }

    private var subtitle: String? {
        guard !model.inventory.items.isEmpty else { return nil }
        let n = model.inventory.items.count
        return "\(n) \(n == 1 ? "Ding" : "Dinge")"
    }

    private var staleCount: Int {
        model.inventory.items.filter { Freshness.of($0) == .stale }.count
    }

    /// Der eine Filter, der sich lohnt.
    ///
    /// Erscheint nur, wenn es etwas zu filtern gibt. Ein Schalter, der auf eine leere
    /// Liste führt, ist ein Versprechen, das die App nicht halten kann — und in einem
    /// frischen Bestand gibt es nichts Unbestätigtes.
    private var filterRow: some View {
        HStack(spacing: 8) {
            chip("Alles", active: !onlyStale) { onlyStale = false }
            chip("Länger nicht gesehen · \(staleCount)", active: onlyStale) { onlyStale = true }
            Spacer()
        }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.eh(13, .footnote, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Color.white : EH.slate)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(active ? EH.navy : EH.surface))
                .overlay(Capsule().stroke(active ? .clear : EH.hair, lineWidth: EH.hairWidth))
        }
        .buttonStyle(EHTap())
    }

    // MARK: Inhalt

    private var content: some View {
        List {
            if !model.query.isEmpty {
                searchResults
            } else if model.inventory.items.isEmpty {
                EmptyNote(
                    label: "Noch nichts drin",
                    text: "Fotografiere ein Regal, eine Schublade, eine Kiste. "
                        + "Dein Modell liest, was darauf ist, und du hakst ab, was stimmt.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                grouped
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.hits.isEmpty {
            EmptyNote(label: "Kein Treffer",
                      text: "Nichts im Bestand passt zu diesem Wort.")
                .plainRow()
        } else {
            ForEach(model.hits) { hit in
                row(hit.item, kind: hit.kind, showPlace: true)
            }
            if model.semanticContributed {
                Text("Einige Treffer kommen aus der Bedeutung, nicht aus dem Namen.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
                    .padding(.top, 10)
                    .plainRow()
            }
        }
    }

    @ViewBuilder
    private var grouped: some View {
        let tree = model.inventory.tree
        ForEach(tree.flattened(), id: \.place.id) { entry in
            let direct = visible(model.inventory.items(at: entry.place.id, includingBelow: false))
            if !direct.isEmpty {
                Section {
                    ForEach(direct) { row($0) }
                } header: {
                    SectionLabel(text: tree.path(of: entry.place.id))
                        .textCase(nil)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: EH.gutter, bottom: 0, trailing: EH.gutter))
            }
        }

        let loose = visible(model.inventory.unplaced)
        if !loose.isEmpty {
            Section {
                ForEach(loose) { row($0) }
            } header: {
                SectionLabel(text: "Ohne Ort").textCase(nil)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: EH.gutter, bottom: 0, trailing: EH.gutter))
        }

        if onlyStale, visible(model.inventory.items).isEmpty {
            EmptyNote(label: "Alles bestätigt",
                      text: "Kein Eintrag ist älter als ein halbes Jahr.")
                .plainRow()
        }
    }

    /// Eine Zeile mit ihren beiden Wischgesten.
    ///
    /// „Gesehen“ links, weil es die häufige und harmlose ist; „Löschen“ rechts, wo
    /// iOS destruktive Gesten erwartet, und ohne `allowsFullSwipe`, damit ein
    /// entschlossener Wisch beim Scrollen keinen Eintrag verliert.
    private func row(_ item: Item, kind: ItemSearch.Kind? = nil, showPlace: Bool = false) -> some View {
        NavigationLink(value: item.id) {
            ItemRow(item: item, kind: kind,
                    placePath: showPlace ? item.placeID.map { model.inventory.tree.path(of: $0) } : nil)
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(EH.hair)
        .listRowInsets(EdgeInsets(top: 0, leading: EH.gutter, bottom: 0, trailing: EH.gutter))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { model.markSeen(item.id) } label: {
                Label("Gesehen", systemImage: "checkmark")
            }
            .tint(EH.good)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { model.delete(item.id) } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func visible(_ items: [Item]) -> [Item] {
        let filtered = onlyStale ? items.filter { Freshness.of($0) == .stale } : items
        return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Handlungsleiste

    /// Unten, weil dort der Daumen ist, und mit der Kamera als gefülltem Knopf, weil
    /// sie der Weg ist, auf dem dieser Bestand entsteht. Von Hand geht auch — aber
    /// wer vierzig Dinge tippen müsste, tippt sie nicht.
    private var actionBar: some View {
        HStack(spacing: 12) {
            placePicker

            Spacer(minLength: 0)

            RoundIconButton(systemName: "plus", label: "Von Hand eintragen", size: 42) {
                showManual = true
            }

            Menu {
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: {
                        Label("Fotografieren", systemImage: "camera")
                    }
                }
                Button { showLibrary = true } label: {
                    Label("Aus der Galerie", systemImage: "photo")
                }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(EH.navy))
            }
            .accessibilityLabel("Regal fotografieren")
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            Rectangle().fill(EH.hair).frame(height: EH.hairWidth)
        }
    }

    /// Wohin das Nächste kommt.
    ///
    /// Steht in der Handlungsleiste und nicht im Prüfschritt, weil man den Ort weiß,
    /// bevor man fotografiert — man steht davor. Danach danach zu fragen heißt, den
    /// Nutzer nach etwas zu fragen, das er der App gerade gezeigt hat.
    private var placePicker: some View {
        Menu {
            ForEach(model.inventory.tree.flattened(), id: \.place.id) { entry in
                Button(model.inventory.tree.path(of: entry.place.id)) {
                    pendingPlace = entry.place.id
                }
            }
            if !model.inventory.places.isEmpty { Divider() }
            Button("Ohne Ort") { pendingPlace = nil }
            Divider()
            Button { showPlaces = true } label: { Label("Orte verwalten", systemImage: "tray.2") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 12, weight: .medium))
                Text(currentPlaceLabel)
                    .font(.eh(13, .footnote))
                    .lineLimit(1)
            }
            .foregroundStyle(EH.slate)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(EH.surface))
            .overlay(Capsule().stroke(EH.hair, lineWidth: EH.hairWidth))
        }
        .accessibilityLabel("Ort für neue Einträge: \(currentPlaceLabel)")
    }

    private var currentPlaceLabel: String {
        pendingPlace.map { model.inventory.tree.path(of: $0) } ?? "Ohne Ort"
    }
}

extension View {
    /// Eine Listenzeile, die keine sein will: ohne Trenner, ohne Untergrund, ohne
    /// Einrückung. Für Hinweise und leere Zustände.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: EH.gutter, bottom: 0, trailing: EH.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

