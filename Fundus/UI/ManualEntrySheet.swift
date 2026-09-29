import SwiftUI

/// Entering by hand.
///
/// Not an emergency exit but the second route, with equal standing. The photo is faster
/// for a whole shelf; for a single thing you happen to be holding, typing is faster than
/// photographing, waiting and ticking off. Which is why the field takes focus at once
/// and the button adds another without closing the sheet: whoever enters three things
/// enters them one after another.
struct ManualEntrySheet: View {
    let placeID: UUID?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantity = ""
    @State private var unit = ""
    @State private var added: [String] = []
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            EH.scene
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Von Hand")
                            .font(.brand(19))
                            .foregroundStyle(EH.navy)
                        Text(placeID.map { model.inventory.tree.path(of: $0) } ?? String(localized: "Ohne Ort"))
                            .font(EH.meta)
                            .foregroundStyle(EH.muted)
                    }
                    Spacer()
                    Button("Fertig") { dismiss() }
                        .font(.eh(15, .callout))
                        .foregroundStyle(EH.slate)
                        .buttonStyle(EHTap())
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    TextField("Was ist es?", text: $name)
                        .font(EH.body)
                        .foregroundStyle(EH.navy)
                        .focused($nameFocused)
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
                }

                HStack(spacing: 10) {
                    TextField("Menge", text: $quantity)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                    TextField("Einheit", text: $unit)
                }
                .font(EH.bodySmall)
                .foregroundStyle(EH.navy)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous)
                        .fill(EH.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous)
                        .stroke(EH.hair, lineWidth: EH.hairWidth))
                .padding(.top, 10)

                Button("Eintragen", action: commit)
                    .buttonStyle(EHButtonStyle(prominent: true))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 14)

                if !added.isEmpty {
                    Text("Eingetragen: \(added.reversed().joined(separator: ", "))")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                        .lineLimit(2)
                        .padding(.top, 12)
                }

                Spacer()
            }
            .padding(.horizontal, EH.gutter)
            .padding(.top, 18)
        }
        .onAppear { nameFocused = true }
    }

    private func commit() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        model.add(name: clean, quantity: Int(quantity.filter(\.isNumber)),
                  unit: unit.trimmingCharacters(in: .whitespaces), placeID: placeID)
        added.append(clean)
        name = ""
        quantity = ""
        // Die Einheit bleibt stehen: wer „Packung“ tippt, tippt meist mehrere.
        nameFocused = true
    }
}
