import SwiftUI

/// The inventory. The one list this app is.
///
/// As a `List` and not as a `ScrollView` with a `LazyVStack`, the way Faden does it in
/// the chat: swipe actions only exist in a list, and "seen" with one swipe is the act
/// the reliability of this inventory depends on. Putting it behind a long press would
/// mean not using it. The price is that the list has to be bent into shape so that the
/// scene behind it shows through — that is four lines and worth it.
struct InventoryView: View {
    @Environment(AppModel.self) private var model

    @State private var showSettings = false
    @State private var places: PlacesSheet?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showManual = false
    @State private var pendingPlace: UUID?
    /// The viewfinder has asked for the places. The sheet only opens once it is gone —
    /// there is no such thing as two full screens at once.
    @State private var wantsPlaces = false

    /// Why the places are open, and not merely that they are.
    ///
    /// As a `sheet(item:)` and not as a flag with a second marker beside it, and that
    /// is measured rather than taste: with two separate states SwiftUI builds the sheet
    /// with whatever it happens to see as it opens, and here that was the old value —
    /// the place was created and landed nowhere, and the line "from the viewfinder"
    /// appeared only one change later. With `item` the reason travels along with the
    /// presentation and cannot be out of step.
    private enum PlacesSheet: Int, Identifiable {
        case list, forCamera
        var id: Int { rawValue }
    }
    @State private var onlyStale = false
    /// The job the user tapped in the queue.
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
        .sheet(item: $places) { entry in
            PlacesView(adopt: entry == .forCamera ? { pendingPlace = $0 } : nil)
        }
        .sheet(isPresented: $showManual) {
            ManualEntrySheet(placeID: pendingPlace)
                .presentationDetents([.height(280)])
        }
        // The viewfinder sends you to the places by closing itself. The sheet opens
        // only afterwards and not at the same time: a sheet requested while a full
        // screen is still going away does not appear — it silently fails, and the user
        // has tapped "create place" and finds themselves looking at the list.
        .fullScreenCover(isPresented: $showCamera,
                         onDismiss: {
                             guard wantsPlaces else { return }
                             wantsPlaces = false
                             places = .forCamera
                         }) {
            CameraScreen(placeID: $pendingPlace, onNewPlace: { wantsPlaces = true })
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker { images in
                model.enqueue(images, placeID: pendingPlace)
            }
        }
        // The checking step is not a sheet over the list but the whole screen:
        // everything behind it distracts from the one question that counts — is what
        // the model read correct.
        //
        // It no longer opens by itself, though. Whoever is photographing the next shelf
        // does not want to be interrupted by a finished shot; that one announces itself
        // through the line at the top and waits as a symbol in the queue.
        .fullScreenCover(item: $openJob) { job in
            IntakeView(job: job)
        }
    }

    // `@Environment` gives no binding, and a local `@Bindable` only applies within the
    // scope it stands in — so `body` does not reach into `header`. Written out it is
    // two lines longer and valid everywhere.
    private var queryBinding: Binding<String> {
        Binding(get: { model.query }, set: { model.query = $0 })
    }

    // MARK: Kopf

    private var header: some View {
        VStack(spacing: 12) {
            AppHeader(title: "Fundus", subtitle: subtitle) {
                HStack(spacing: 8) {
                    RoundIconButton(systemName: "tray.2", label: "Orte") { places = .list }
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
        return n == 1 ? String(localized: "1 Ding") : String(localized: "\(n) Dinge")
    }

    private var staleCount: Int {
        model.inventory.items.filter { Freshness.of($0) == .stale }.count
    }

    /// The one filter that is worth having.
    ///
    /// Appears only when there is something to filter. A switch that leads to an empty
    /// list is a promise the app cannot keep — and in a fresh inventory there is
    /// nothing unconfirmed.
    private var filterRow: some View {
        HStack(spacing: 8) {
            chip("Alles", active: !onlyStale) { onlyStale = false }
            chip("Länger nicht gesehen · \(staleCount)", active: onlyStale) { onlyStale = true }
            Spacer()
        }
    }

    private func chip(_ text: LocalizedStringKey, active: Bool, action: @escaping () -> Void) -> some View {
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
                    text: "Fotografiere ein Regal, eine Schublade, eine Kiste. Dein Modell liest, was darauf ist, und du hakst ab, was stimmt.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if model.client == nil {
                    modelHint.plainRow()
                }
            } else {
                grouped
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Without a model the camera leads nowhere, and nothing on this screen said where
    /// one is set up. One line and the way there — only while it is missing.
    private var modelHint: some View {
        VStack(spacing: 12) {
            Text("Dafür braucht Fundus zuerst dein Modell: Endpoint, Schlüssel und Modellname, unter Einstellungen → Modell.")
                .font(EH.bodySmall)
                .foregroundStyle(EH.muted)
                .lineSpacing(EH.prose)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("Modell einrichten") { showSettings = true }
                .buttonStyle(EHButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
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
                    SectionLabel(text: LocalizedStringKey(tree.path(of: entry.place.id)))
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

    /// A row with its two swipe actions.
    ///
    /// "Seen" on the left, because it is the frequent and harmless one; "delete" on the
    /// right, where iOS expects destructive gestures, and without `allowsFullSwipe`, so
    /// that a decisive swipe while scrolling does not lose an entry.
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

    /// At the bottom, because that is where the thumb is, and with the camera as the
    /// filled button, because it is the route by which this inventory comes into being.
    /// By hand works too — but whoever would have to type forty things does not type
    /// them.
    private var actionBar: some View {
        HStack(spacing: 12) {
            placePicker

            Spacer(minLength: 0)

            RoundIconButton(systemName: "plus", label: "Von Hand eintragen", size: 42) {
                showManual = true
            }

            Menu {
                if CameraSession.isAvailable {
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
                    .foregroundStyle(EH.onAccent)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(EH.navy))
            }
            .accessibilityLabel(Text("Regal fotografieren"))
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            Rectangle().fill(EH.hair).frame(height: EH.hairWidth)
        }
    }

    /// Where the next one goes.
    ///
    /// It stands in the action bar and not in the checking step, because you know the
    /// place before you take the photo — you are standing in front of it. Asking
    /// afterwards means asking the user about something they have just shown the app.
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
            Button { places = .list } label: { Label("Orte verwalten", systemImage: "tray.2") }
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
        .accessibilityLabel(Text("Ort für neue Einträge: \(currentPlaceLabel)"))
    }

    private var currentPlaceLabel: String {
        pendingPlace.map { model.inventory.tree.path(of: $0) } ?? String(localized: "Ohne Ort")
    }
}

extension View {
    /// A list row that does not want to be one: no separator, no background, no inset.
    /// For notes and empty states.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: EH.gutter, bottom: 0, trailing: EH.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

