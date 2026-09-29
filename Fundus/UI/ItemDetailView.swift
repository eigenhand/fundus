import SwiftUI

/// One thing, close up.
///
/// The most prominent button is "seen" and not "save". Saving happens by itself —
/// changes run into the inventory when a field loses focus. A sighting is the one act
/// nobody can carry out automatically, and the entire reliability of this app hangs on
/// its being easy.
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
                    // The entry was deleted while this view was open.
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

            if let code = item.code, !code.value.isEmpty {
                SectionLabel(text: "Kennung")
                codeCard(code)
            }

            SectionLabel(text: "Herkunft")
            provenance(item)
        }
        .padding(.horizontal, EH.gutter)
        .padding(.bottom, 40)
    }

    /// The number on the thing, and what a search made of it.
    ///
    /// The two side by side and not inside one another: the number is the only thing
    /// about an entry that can be checked without picking the thing up. Whoever stands
    /// in front of the shelf later and finds something other than what stands here sees
    /// at once what the claim rested on — the number, the query, the source and the
    /// date.
    private func codeCard(_ code: ItemCode) -> some View {
        HairlineCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: code.origin == .scanned
                          ? "barcode.viewfinder" : "text.viewfinder")
                        .font(.system(size: 12))
                        .foregroundStyle(EH.muted)
                    Text(code.value)
                        .font(EH.mono.weight(.medium))
                        .foregroundStyle(EH.navy)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    // The kind of code, translated here and not in `ItemCode`: the same label
                    // also goes into the (German) prompt.
                    Text(LocalizedStringKey(code.label))
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                }

                Text(code.origin == .scanned
                     ? "Vom Geraet aus dem Strichcode entziffert — zeichengenau."
                     : "Vom Modell aus dem Foto abgelesen. Kann Lesefehler enthalten.")
                    .font(EH.meta)
                    .foregroundStyle(code.origin == .scanned ? EH.muted : EH.warn)

                if let lookup = code.lookup, let reason = lookup.emptyReason {
                    Divider().overlay(EH.hair)
                    Text(String(localized: "Nachgeschlagen nach \(lookup.query) — \(reason).")
                         + " " + Ago.string(lookup.searchedAt))
                        .font(EH.meta)
                        .foregroundStyle(lookup.failed ? EH.warn : EH.muted)
                } else if let lookup = code.lookup, let best = lookup.best, !best.title.isEmpty {
                    Divider().overlay(EH.hair)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(best.title)
                            .font(EH.bodySmall.weight(.medium))
                            .foregroundStyle(EH.navy)
                        if !best.summary.isEmpty {
                            Text(best.summary)
                                .font(EH.bodySmall)
                                .foregroundStyle(EH.slate)
                                .lineSpacing(2)
                        }
                        Text(lookupTrail(lookup, best: best))
                            .font(EH.meta)
                            .foregroundStyle(lookup.chosen == nil ? EH.warn : EH.muted)
                        if let url = URL(string: best.sourceURL), !best.sourceURL.isEmpty {
                            Link(best.sourceURL, destination: url)
                                .font(EH.meta)
                                .foregroundStyle(EH.slate)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// The chain in one line: what was searched for, how near the hit lay, whether
    /// somebody confirmed it, and when that was.
    ///
    /// "Not taken over" stands there explicitly and in the warning colour. A suggestion
    /// nobody tapped otherwise looks exactly like one somebody checked — and that
    /// difference is the only thing that makes this line worth having.
    private func lookupTrail(_ lookup: CodeLookup, best: CodeCandidate) -> String {
        var parts = [String(localized: "gesucht nach \(lookup.query)")]
        if !best.codeSeen.isEmpty {
            parts.append(String(localized: "gefunden als \(best.codeSeen)"))
        } else if best.match != .exact {
            parts.append(best.match.label)
        }
        if lookup.chosen == nil {
            parts.append(lookup.candidates.count > 1
                         ? String(localized: "einer von \(lookup.candidates.count), nicht übernommen")
                         : String(localized: "nicht übernommen"))
        }
        parts.append(Ago.string(lookup.searchedAt))
        return parts.joined(separator: " · ")
    }

    /// The sighting, right at the top and as a card.
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
        // Write when the field loses focus, not on every keystroke: otherwise every
        // letter throws the vector away and puts the embedding back in the queue.
        .onDisappear(perform: commit)
    }

    private func labelledField(_ label: LocalizedStringKey, text: Binding<String>,
                               placeholder: LocalizedStringKey = "", axis: Axis = .horizontal) -> some View {
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
                Text(draft?.placeID.map { model.inventory.tree.path(of: $0) } ?? String(localized: "Ohne Ort"))
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

    /// Who wrote this entry, and when.
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
            // An entry without a name is not an entry. Rather than deleting it — which
            // the user did not ask for — bring the previous name back.
            draft = model.inventory.item(itemID)
            return
        }
        model.update(item)
        draft = model.inventory.item(itemID)
    }
}
