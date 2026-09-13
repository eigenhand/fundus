import SwiftUI

/// Der Prüfschritt: was das Modell gelesen hat, bevor daraus Bestand wird.
///
/// Diese Ansicht ist der Grund, warum man dem Bestand glauben kann. Ein Modell, das
/// ein Regal liest, verzählt sich, fasst zusammen und liest Etiketten falsch — und
/// ein Bestand, der Modellausgabe stillschweigend aufnimmt, ist schlechter als
/// keiner, weil man ihm glaubt. Hier stehen Vorschläge, keine Einträge; nichts
/// wandert in den Bestand ohne Häkchen.
///
/// Die Vorschläge sind angehakt und nicht leer: Vorschläge abzunicken ist der
/// Normalfall, Streichen die Ausnahme. Eine Liste, in der man vierzig Häkchen selbst
/// setzen muss, benutzt man einmal.
struct IntakeView: View {
    @Bindable var state: IntakeState
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EH.scene
            BrandWatermark()

            VStack(spacing: 0) {
                header

                switch state.phase {
                case .reading:  reading
                case .review:   review
                case .failed(let message): failure(message)
                }
            }
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aufnahme")
                    .font(.brand(21))
                    .foregroundStyle(EH.navy)
                Text(placeLabel)
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }
            Spacer()
            Button("Abbrechen") {
                model.cancelIntake()
                dismiss()
            }
            .font(.eh(15, .callout))
            .foregroundStyle(EH.slate)
            .buttonStyle(EHTap())
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var placeLabel: String {
        state.placeID.map { model.inventory.tree.path(of: $0) } ?? "Ohne Ort"
    }

    // MARK: Lesen

    private var reading: some View {
        VStack(spacing: 20) {
            photo(maxHeight: 300)

            VStack(spacing: 8) {
                ProgressView()
                    .tint(EH.slate)
                Text(state.received == 0
                     ? "Das Modell sieht sich das Bild an."
                     : "Es schreibt — \(state.received) Zeichen.")
                    .font(EH.bodySmall)
                    .foregroundStyle(EH.slate)
                Text("Bei einem vollen Regal dauert das eine halbe Minute.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }
            Spacer()
        }
        .padding(.horizontal, EH.gutter)
    }

    // MARK: Fehlschlag

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            photo(maxHeight: 220)

            HairlineCard {
                VStack(alignment: .leading, spacing: 8) {
                    EH.label("Nicht gelesen")
                    Text(message)
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                        .lineSpacing(3)
                }
            }

            // Das Bild ist schon gespeichert, bevor der Aufruf lief. Deshalb ist ein
            // zweiter Versuch hier billig — niemand muss nochmal in den Keller.
            HStack(spacing: 10) {
                Button("Nochmal versuchen") {
                    let image = state.image
                    let place = state.placeID
                    let hint = state.hint
                    model.cancelIntake()
                    model.startIntake(image: image, placeID: place, hint: hint)
                }
                .buttonStyle(EHButtonStyle(prominent: true))

                Button("Schließen") {
                    model.cancelIntake()
                    dismiss()
                }
                .buttonStyle(EHButtonStyle())
            }
            Spacer()
        }
        .padding(.horizontal, EH.gutter)
    }

    // MARK: Prüfen

    private var review: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photo(maxHeight: 170)
                        .padding(.bottom, 6)

                    SectionLabel(text: "\(state.result.proposals.count) gefunden")

                    ForEach($state.result.proposals) { $proposal in
                        ProposalRow(proposal: $proposal, existing: existing(for: proposal))
                        Divider().overlay(EH.hair)
                    }

                    if !state.result.unreadable.isEmpty {
                        unreadable
                    }

                    provenanceNote
                }
                .padding(.horizontal, EH.gutter)
                .padding(.bottom, 20)
            }

            commitBar
        }
    }

    /// Ein Eintrag, auf den dieser Vorschlag fallen würde — dann wird erhöht statt
    /// angelegt. Steht an der Zeile, damit der Nutzer es *vorher* weiß und nicht
    /// hinterher eine Menge findet, die er nicht erwartet hat.
    private func existing(for proposal: Proposal) -> Item? {
        model.inventory.existing(named: proposal.name, at: state.placeID)
    }

    /// Was das Modell gesehen, aber nicht bestimmt hat.
    ///
    /// Das ist kein Fehler, sondern die Gegenleistung für „rate nicht“: es sagt dem
    /// Nutzer, wo er selbst nachsehen muss. Ohne diese Liste wüsste er nur, dass
    /// etwas fehlt, aber nicht, was.
    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Nicht bestimmbar")
            Text("Das Modell hat es gesehen, konnte es aber nicht benennen. "
                 + "Hier musst du selbst nachsehen.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .padding(.bottom, 2)
            ForEach(state.result.unreadable, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(EH.hairStrong)
                        .frame(width: 3, height: 3)
                        .offset(y: 6)
                    Text(line)
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                }
            }
        }
    }

    private var provenanceNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(EH.hair)
                .frame(height: EH.hairWidth)
                .padding(.vertical, 16)
            Text("Gelesen von \(state.result.model). Was du übernimmst, behält das "
                 + "als Herkunft und dieses Foto als Beleg.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .lineSpacing(2)
        }
    }

    private var commitBar: some View {
        HStack(spacing: 12) {
            let n = state.acceptedCount
            Button {
                model.commitIntake()
                dismiss()
            } label: {
                Text(n == 0 ? "Nichts übernehmen" : "\(n) übernehmen")
            }
            .buttonStyle(EHButtonStyle(prominent: n > 0))
            .disabled(n == 0)

            Spacer()

            Button(allAccepted ? "Alle abwählen" : "Alle wählen") {
                let target = !allAccepted
                for i in state.result.proposals.indices {
                    state.result.proposals[i].accepted = target
                }
            }
            .font(.eh(14, .footnote))
            .foregroundStyle(EH.slate)
            .buttonStyle(EHTap())
        }
        .padding(.horizontal, EH.gutter)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            Rectangle().fill(EH.hair).frame(height: EH.hairWidth)
        }
    }

    private var allAccepted: Bool {
        !state.result.proposals.isEmpty && state.result.proposals.allSatisfy(\.accepted)
    }

    // MARK: Das Bild

    private func photo(maxHeight: CGFloat) -> some View {
        Image(uiImage: state.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous)
                    .stroke(EH.hair, lineWidth: EH.hairWidth))
    }
}

/// Eine Zeile im Prüfschritt.
///
/// Der Name ist ein Textfeld und keine Beschriftung: der häufigste Eingriff ist
/// nicht Streichen, sondern Zurechtrücken — „Kabel USB-C“ zu „USB-C-Kabel“. Wer das
/// erst im Bestand tun kann, tut es nicht.
private struct ProposalRow: View {
    @Binding var proposal: Proposal
    /// Der Eintrag, auf den dieser Vorschlag fallen würde.
    let existing: Item?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                proposal.accepted.toggle()
            } label: {
                Image(systemName: proposal.accepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
                    .foregroundStyle(proposal.accepted ? EH.navy : EH.hairStrong)
            }
            .buttonStyle(EHTap())
            .accessibilityLabel(proposal.accepted ? "Ausgewählt: \(proposal.name)"
                                                  : "Nicht ausgewählt: \(proposal.name)")

            VStack(alignment: .leading, spacing: 5) {
                TextField("Name", text: $proposal.name)
                    .font(EH.answer)
                    .foregroundStyle(EH.navy)

                if !proposal.note.isEmpty {
                    Text(proposal.note)
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                        .lineLimit(2)
                }

                if let existing {
                    Text(existing.quantity.map {
                        "steht schon da (\($0)\(existing.unit.isEmpty ? "" : " " + existing.unit)) — wird erhöht"
                    } ?? "steht schon da — wird zusammengelegt")
                        .font(EH.meta)
                        .foregroundStyle(EH.warn)
                }
            }

            Spacer(minLength: 0)

            quantityControl
        }
        .padding(.vertical, 10)
        .opacity(proposal.accepted ? 1 : 0.45)
    }

    /// Menge, mit „—“ für ungezählt.
    ///
    /// Das Minus ist kein leeres Feld, sondern ein Wert: das Modell hat gesagt, es
    /// kann nicht zählen. Wer selbst nachzählt, tippt die Zahl; wer es nicht tut,
    /// lässt es stehen — und der Bestand behauptet dann keine Menge.
    private var quantityControl: some View {
        HStack(spacing: 6) {
            if let q = proposal.quantity {
                Button {
                    proposal.quantity = q > 1 ? q - 1 : nil
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EH.slate)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(EH.surfaceSunk))
                }
                .buttonStyle(EHTap())
                .accessibilityLabel("Menge verringern")

                Text("\(q)")
                    .font(.eh(15, .callout, weight: .medium))
                    .foregroundStyle(EH.navy)
                    .monospacedDigit()
                    .frame(minWidth: 20)
            } else {
                Text("—")
                    .font(.eh(15, .callout))
                    .foregroundStyle(EH.muted)
                    .frame(minWidth: 20)
                    .accessibilityLabel("Menge ungezählt")
            }

            Button {
                proposal.quantity = (proposal.quantity ?? 0) + 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EH.slate)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(EH.surfaceSunk))
            }
            .buttonStyle(EHTap())
            .accessibilityLabel("Menge erhöhen")
        }
    }
}
