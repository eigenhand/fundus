import SwiftUI

/// The places.
///
/// A tree you can build while standing in front of it: tap "cellar", "shelf 2"
/// underneath it, done. Renaming happens in the row, because a place called "box" needs
/// a better name by the second box at the latest.
struct PlacesView: View {
    /// Arrived from the viewfinder: then the newly created place becomes the one being
    /// photographed into.
    ///
    /// Without that the detour would be short but empty — you create "shelf 4", go back
    /// into the viewfinder and photograph into "shelf 3", because that is where the
    /// picker still stands. And at exactly the moment when you are least likely to
    /// check.
    var adopt: ((UUID) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newParent: UUID?
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var deleting: Place?

    var body: some View {
        ZStack {
            EH.scene
            VStack(spacing: 0) {
                header
                list
                adder
            }
        }
        .confirmationDialog(deleting.map { "„\($0.name)“ löschen?" } ?? "",
                            isPresented: .init(get: { deleting != nil },
                                               set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let place = deleting { model.removePlace(place.id) }
                deleting = nil
            }
        } message: {
            if let place = deleting {
                let n = model.inventory.items(at: place.id).count
                Text(n == 0
                     ? "Der Ort und alle Unterorte werden gelöscht."
                     : "Der Ort und alle Unterorte werden gelöscht. \(n) \(n == 1 ? "Ding liegt" : "Dinge liegen") danach nirgends — gelöscht wird davon nichts.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Orte")
                .font(.brand(21))
                .foregroundStyle(EH.navy)
            Spacer()
            Button("Fertig") { dismiss() }
                .font(.eh(15, .callout))
                .foregroundStyle(EH.slate)
                .buttonStyle(EHTap())
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var list: some View {
        List {
            if model.inventory.places.isEmpty {
                EmptyNote(label: "Keine Orte",
                          text: "Ein Ort ist, wo etwas liegt: Keller, Regal 2, Kiste C. Ohne Orte geht es auch — dann liegt alles auf einem Haufen.")
                    .plainRow()
            }
            ForEach(model.inventory.tree.flattened(), id: \.place.id) { entry in
                row(entry.place, depth: entry.depth)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private func row(_ place: Place, depth: Int) -> some View {
        let count = model.inventory.items(at: place.id).count
        return HStack(spacing: 10) {
            if depth > 0 {
                Rectangle()
                    .fill(EH.hair)
                    .frame(width: EH.hairWidth, height: 16)
                    .padding(.leading, CGFloat(depth - 1) * 14)
            }

            if renaming == place.id {
                TextField("Name", text: $renameText)
                    .font(EH.body)
                    .foregroundStyle(EH.navy)
                    .submitLabel(.done)
                    .onSubmit {
                        model.inventory.renamePlace(place.id, to:
                            renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                        model.save()
                        renaming = nil
                    }
            } else {
                Text(place.name)
                    .font(EH.body)
                    .foregroundStyle(EH.navy)
                    .onTapGesture {
                        renameText = place.name
                        renaming = place.id
                    }
            }

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
                    .monospacedDigit()
            }

            Button {
                newParent = place.id
            } label: {
                Image(systemName: newParent == place.id ? "plus.circle.fill" : "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(newParent == place.id ? EH.navy : EH.muted)
            }
            .buttonStyle(EHTap())
            .accessibilityLabel(Text("Unterort in \(place.name) anlegen"))
        }
        .padding(.vertical, 10)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(EH.hair)
        .listRowInsets(EdgeInsets(top: 0, leading: EH.gutter, bottom: 0, trailing: EH.gutter))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = place } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private var adder: some View {
        VStack(alignment: .leading, spacing: 8) {
            if adopt != nil {
                Text("Aus dem Sucher: der neue Ort ist danach gewählt. Zurück geht es über die Kamera.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }

            if let parent = newParent {
                HStack(spacing: 6) {
                    Text("unter \(model.inventory.tree.path(of: parent))")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                    Button {
                        newParent = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(EH.muted)
                    }
                    .buttonStyle(EHTap())
                    .accessibilityLabel(Text("Nicht unterordnen"))
                }
            }

            HStack(spacing: 10) {
                TextField("Neuer Ort", text: $newName)
                    .font(EH.body)
                    .foregroundStyle(EH.navy)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .padding(.horizontal, 14)
                    .frame(height: EH.composerHeight)
                    .background(
                        RoundedRectangle(cornerRadius: EH.radiusField, style: .circular)
                            .fill(EH.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: EH.radiusField, style: .circular)
                            .stroke(EH.hair, lineWidth: EH.hairWidth))

                RoundIconButton(systemName: "plus", label: "Ort anlegen",
                                prominent: !newName.trimmingCharacters(in: .whitespaces).isEmpty,
                                size: EH.composerHeight, action: commit)
            }
        }
        .padding(.horizontal, EH.gutter)
        .padding(.vertical, 12)
        .background(alignment: .top) {
            Rectangle().fill(EH.hair).frame(height: EH.hairWidth)
        }
    }

    private func commit() {
        guard let place = model.addPlace(name: newName, under: newParent) else { return }
        newName = ""
        adopt?(place.id)
        // Der Elternort bleibt stehen: wer „Regal 1“ anlegt, legt gleich „Regal 2“ an.
    }
}
