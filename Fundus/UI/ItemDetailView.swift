import SwiftUI

/// Ein Ding, von nahem.
///
/// Der auffälligste Knopf ist „Gesehen“ und nicht „Speichern“. Speichern passiert
/// von selbst — Änderungen laufen beim Verlassen des Feldes in den Bestand. Eine
/// Sichtung ist die eine Handlung, die niemand automatisch erledigen kann, und die
/// ganze Verlässlichkeit dieser App hängt daran, dass sie leicht ist.
struct ItemDetailView: View {
    let itemID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Item?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            EH.scene
            ScrollView {
                if let item = draft {
                    content(item)
                } else {
                    // Der Eintrag wurde gelöscht, während diese Ansicht offen war.
                    EmptyNote(label: "Nicht mehr da",
                              text: "Dieser Eintrag ist gelöscht.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(draft?.name ?? "")
                    .font(.eh(16, .callout, weight: .medium))
                    .foregroundStyle(EH.navy)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(EH.slate)
                }
            }
        }
        .onAppear { draft = model.inventory.item(itemID) }
        .confirmationDialog("Diesen Eintrag löschen?", isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                model.delete(itemID)
                dismiss()
            }
        } message: {
            Text("Das Foto bleibt erhalten.")
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            seenCard(item)

            SectionLabel(text: "Eintrag")
            fields

            SectionLabel(text: "Ort")
            placeRow

            if !item.photoIDs.isEmpty {
                SectionLabel(text: item.photoIDs.count == 1 ? "Beleg" : "Belege")
                photos(item)
            }

            SectionLabel(text: "Herkunft")
            provenance(item)
        }
        .padding(.horizontal, EH.gutter)
        .padding(.bottom, 40)
    }

    /// Die Sichtung, ganz oben und als Karte.
    private func seenCard(_ item: Item) -> some View {
        HairlineCard(fill: Freshness.of(item) == .seen ? EH.surface : EH.surfaceSunk) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    FreshnessMark(item: item, showDate: false)
                    Text("Zuletzt gesehen \(Ago.string(item.lastSeenAt))")
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                }
                Spacer()
                Button {
                    model.markSeen(itemID)
                    draft = model.inventory.item(itemID)
                } label: {
                    Text("Gesehen")
                }
                .buttonStyle(EHButtonStyle(prominent: Freshness.of(item) != .seen))
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 0) {
            labelledField("Name", text: Binding(
                get: { draft?.name ?? "" },
                set: { draft?.name = $0 }))

            Divider().overlay(EH.hair)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    EH.label("Menge")
                    TextField("—", text: Binding(
                        get: { draft?.quantity.map(String.init) ?? "" },
                        set: { draft?.quantity = Int($0.filter(\.isNumber)) }))
                        .keyboardType(.numberPad)
                        .font(EH.body)
                        .foregroundStyle(EH.navy)
                        .monospacedDigit()
                }
                .frame(width: 80)

                VStack(alignment: .leading, spacing: 3) {
                    EH.label("Einheit")
                    TextField("Stück", text: Binding(
                        get: { draft?.unit ?? "" },
                        set: { draft?.unit = $0 }))
                        .font(EH.body)
                        .foregroundStyle(EH.navy)
                }
            }
            .padding(.vertical, 11)
            .onSubmit(commit)

            Divider().overlay(EH.hair)

            labelledField("Notiz", text: Binding(
                get: { draft?.note ?? "" },
                set: { draft?.note = $0 }), placeholder: "Farbe, Größe, Zustand …", axis: .vertical)
        }
        // Beim Verlassen des Feldes schreiben, nicht bei jedem Tastendruck: sonst
        // wirft jede Buchstabe den Vektor weg und stellt die Einbettung neu in die
        // Warteschlange.
        .onDisappear(perform: commit)
    }

    private func labelledField(_ label: String, text: Binding<String>,
                               placeholder: String = "", axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            EH.label(label)
            TextField(placeholder, text: text, axis: axis)
                .font(EH.body)
                .foregroundStyle(EH.navy)
                .lineLimit(axis == .vertical ? 1 ... 6 : 1 ... 1)
                .onSubmit(commit)
        }
        .padding(.vertical, 11)
    }

    private var placeRow: some View {
        Menu {
            ForEach(model.inventory.tree.flattened(), id: \.place.id) { entry in
                Button(model.inventory.tree.path(of: entry.place.id)) {
                    draft?.placeID = entry.place.id
                    commit()
                }
            }
            if !model.inventory.places.isEmpty { Divider() }
            Button("Ohne Ort") {
                draft?.placeID = nil
                commit()
            }
        } label: {
            HStack {
                Text(draft?.placeID.map { model.inventory.tree.path(of: $0) } ?? "Ohne Ort")
                    .font(EH.body)
                    .foregroundStyle(EH.navy)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(EH.muted)
            }
            .padding(.vertical, 12)
        }
    }

    private func photos(_ item: Item) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(item.photoIDs, id: \.self) { id in
                    if let image = PhotoStore.load(id) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: EH.radiusSmall,
                                                        style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous)
                                    .stroke(EH.hair, lineWidth: EH.hairWidth))
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    /// Wer diesen Eintrag geschrieben hat, und wann.
    private func provenance(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.provenance.label.prefix(1).uppercased() + item.provenance.label.dropFirst())
                .font(EH.bodySmall)
                .foregroundStyle(EH.slate)
            Text("Angelegt \(Ago.string(item.provenance.at))")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
            if let stamp = item.embeddingStamp {
                Text("Im Suchindex: \(stamp.model), \(stamp.dimension) Dimensionen")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            } else {
                Text("Nicht im Suchindex — über den Namen findbar, nicht über die Bedeutung.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }
        }
        .padding(.vertical, 10)
    }

    private func commit() {
        guard var item = draft else { return }
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.name.isEmpty else {
            // Ein Eintrag ohne Namen ist kein Eintrag. Statt ihn zu löschen — was
            // der Nutzer nicht verlangt hat — den vorigen Namen zurückholen.
            draft = model.inventory.item(itemID)
            return
        }
        model.update(item)
        draft = model.inventory.item(itemID)
    }
}
