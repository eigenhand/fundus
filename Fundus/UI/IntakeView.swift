import SwiftUI

/// The checking step: what the model read, before it becomes inventory.
///
/// This view is the reason the inventory can be believed. A model reading a shelf
/// miscounts, lumps things together and gets labels wrong — and an inventory that
/// silently takes in model output is worse than none, because it gets believed. What
/// stands here are suggestions, not entries; nothing moves into the inventory without
/// a tick.
///
/// The suggestions come ticked rather than empty: nodding suggestions through is the
/// normal case, striking them out the exception. A list in which you have to set forty
/// ticks yourself gets used once.
struct IntakeView: View {
    @Bindable var job: IntakeJob
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EH.scene
            BrandWatermark()

            VStack(spacing: 0) {
                header

                switch job.phase {
                case .waiting:  waiting
                case .reading:  reading
                case .looking(let done, let total): looking(done: done, total: total)
                case .review:   review
                case .empty:    nothingOnIt
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
            // "Later" and not "Cancel": the job stays in the queue and can be tapped
            // again further along. Whoever really wants to be rid of it holds the
            // symbol in the queue down — that is the rarer case and may have the
            // longer route.
            Button("Später") { dismiss() }
            .font(.eh(15, .callout))
            .foregroundStyle(EH.slate)
            .buttonStyle(EHTap())
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var placeLabel: String {
        job.placeID.map { model.inventory.tree.path(of: $0) } ?? String(localized: "Ohne Ort")
    }

    // MARK: Nachschlagen

    /// Its own step, because it takes seconds and does something other than reading.
    ///
    /// With a counter rather than a spinner: the user should see that paid calls are
    /// running here, and how many are still to come.
    private func looking(done: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            photo(maxHeight: 300)

            VStack(spacing: 8) {
                ProgressView()
                    .tint(EH.slate)
                Text(total == 0
                     ? "Nummern werden nachgeschlagen."
                     : "Nummern werden nachgeschlagen — \(done) von \(total).")
                    .font(EH.bodySmall)
                    .foregroundStyle(EH.slate)
                Text("Was dabei herauskommt, ist ein Vorschlag und ersetzt nichts.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
            }
            Spacer()
        }
        .padding(.horizontal, EH.gutter)
    }

    // MARK: Warten

    /// Queued, but no worker free yet.
    ///
    /// Its own view and not the same spinner as for reading: "waiting" and "running"
    /// ask for different patience, and a spinner that turns while nothing happens is a
    /// lie about the state.
    private var waiting: some View {
        VStack(spacing: 20) {
            photo(maxHeight: 300)

            VStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 20))
                    .foregroundStyle(EH.muted)
                Text("Steht in der Reihe.")
                    .font(EH.bodySmall)
                    .foregroundStyle(EH.slate)
                Text("Es werden \(model.settings.intakeConcurrency) Fotos gleichzeitig gelesen. In den Einstellungen änderbar.")
                    .font(EH.meta)
                    .foregroundStyle(EH.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, EH.gutter)
    }

    // MARK: Lesen

    private var reading: some View {
        VStack(spacing: 20) {
            photo(maxHeight: 300)

            VStack(spacing: 8) {
                ProgressView()
                    .tint(EH.slate)
                Text(job.received == 0
                     ? "Das Modell sieht sich das Bild an."
                     : "Es schreibt — \(job.received) Zeichen.")
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

    // MARK: Nichts drauf

    /// Read, and there was no inventory on it.
    ///
    /// Not a failure, and therefore not in the failure card either: the model
    /// answered, and the answer was "there is nothing here". A cellar window, a photo
    /// that went wrong, a wall. The second attempt stands there all the same —
    /// sometimes only the framing was wrong.
    private var nothingOnIt: some View {
        VStack(spacing: 18) {
            photo(maxHeight: 220)

            HairlineCard(fill: EH.surfaceSunk) {
                VStack(alignment: .leading, spacing: 8) {
                    EH.label("Kein Bestand")
                    Text("Das Modell hat das Foto gelesen und nichts darauf gefunden, was in einen Bestand gehört.")
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                        .lineSpacing(3)
                }
            }

            HStack(spacing: 10) {
                Button("Verwerfen") {
                    model.discard(job)
                    dismiss()
                }
                .buttonStyle(EHButtonStyle(prominent: true))

                Button("Nochmal versuchen") {
                    model.retry(job)
                    dismiss()
                }
                .buttonStyle(EHButtonStyle())
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

            // The photo is still in the job. That is why a second attempt is cheap
            // here — nobody has to go down to the cellar again.
            HStack(spacing: 10) {
                Button("Nochmal versuchen") {
                    model.retry(job)
                    dismiss()
                }
                .buttonStyle(EHButtonStyle(prominent: true))

                Button("Verwerfen") {
                    model.discard(job)
                    dismiss()
                }
                .buttonStyle(EHButtonStyle())
            }
            Spacer()
        }
        .padding(.horizontal, EH.gutter)
    }

    // MARK: Checking

    private var review: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photo(maxHeight: 170)
                        .padding(.bottom, 6)

                    SectionLabel(text: "\(job.result.proposals.count) gefunden")

                    ForEach($job.result.proposals) { $proposal in
                        ProposalRow(proposal: $proposal, existing: existing(for: proposal))
                        Divider().overlay(EH.hair)
                    }

                    if !job.result.unreadable.isEmpty {
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

    /// An entry this suggestion would land on — then the count goes up instead of a
    /// new entry being created. It stands on the row so the user knows it *beforehand*
    /// and does not find a quantity afterwards that they did not expect.
    private func existing(for proposal: Proposal) -> Item? {
        model.inventory.existing(named: proposal.name, at: job.placeID)
    }

    /// What the model saw but could not name.
    ///
    /// That is not a failing but the return on "do not guess": it tells the user where
    /// they have to look themselves. Without this list they would only know that
    /// something is missing, not what.
    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Nicht bestimmbar")
            Text("Das Modell hat es gesehen, konnte es aber nicht benennen. Hier musst du selbst nachsehen.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .padding(.bottom, 2)
            ForEach(job.result.unreadable, id: \.self) { line in
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
            Text("Gelesen von \(job.result.model). Was du übernimmst, behält das als Herkunft und dieses Foto als Beleg.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .lineSpacing(2)
        }
    }

    /// Take over — or, if nothing is ticked, throw the shot away.
    ///
    /// This used to say "take over nothing" on a button that was disabled. The label
    /// promised an action, the button refused it, and whoever had unticked everything
    /// in order to be rid of the shot was stuck. A disabled button is only right when
    /// there is *nothing to do* — here there is something: this shot should go.
    private var commitBar: some View {
        HStack(spacing: 12) {
            let action = job.commitAction
            Button {
                switch action {
                case .take:    model.commit(job)
                case .discard: model.discard(job)
                }
                dismiss()
            } label: {
                Text(action.label)
            }
            .buttonStyle(EHButtonStyle(prominent: action != .discard))

            Spacer()

            Button(allAccepted ? "Alle abwählen" : "Alle wählen") {
                let target = !allAccepted
                for i in job.result.proposals.indices {
                    job.result.proposals[i].accepted = target
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
        !job.result.proposals.isEmpty && job.result.proposals.allSatisfy(\.accepted)
    }

    // MARK: Das Bild

    private func photo(maxHeight: CGFloat) -> some View {
        Image(uiImage: job.image)
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

/// A row in the checking step.
///
/// The name is a text field and not a label: the commonest intervention is not
/// striking out but nudging into shape — "cable USB-C" to "USB-C cable". Whoever can
/// only do that once it is in the inventory does not do it.
private struct ProposalRow: View {
    @Binding var proposal: Proposal
    /// The entry this suggestion would land on.
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

                if let code = proposal.code { codeRow(code) }

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

    /// The identifier and, if it was looked up, the choice that goes with it.
    ///
    /// A single suggestion with a tick used to stand here. Now up to three stand there
    /// with a dot in front, and exactly one can be tapped — or none. That is the whole
    /// change, and it shifts the question: no longer "is this reading correct?", which
    /// nobody here can decide, but "which of these is it?", which anybody holding the
    /// thing in their hand can decide.
    ///
    /// Nothing is selected. A resolved product name stands at the end of a chain made
    /// of a blurred sticker, confusable characters and a search engine that answers
    /// everything — and afterwards it looks more reliable than anything else in the
    /// inventory. The number above it and the differing number beside it make it
    /// checkable.
    @ViewBuilder
    private func codeRow(_ code: ItemCode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: code.origin == .scanned ? "barcode.viewfinder" : "text.viewfinder")
                .font(.system(size: 10))
                .foregroundStyle(EH.muted)
            Text(code.value)
                .font(EH.mono.weight(.medium))
                .foregroundStyle(EH.slate)
            Text(code.origin == .scanned ? "entziffert" : "abgelesen")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
        }

        if let lookup = code.lookup {
            if let reason = lookup.emptyReason {
                // This belongs here too. An empty space under the number looks as if
                // nobody had searched — and leaves the user unsure whether to try
                // again.
                Text("Nachgeschlagen — \(reason).")
                    .font(EH.meta)
                    .foregroundStyle(lookup.failed ? EH.warn : EH.muted)
                    .padding(.top, 3)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(lookup.candidates.count == 1 ? "Ist es das?" : "Welches ist es?")
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)

                    ForEach(Array(lookup.candidates.enumerated()), id: \.offset) { index, candidate in
                        candidateRow(index: index, candidate: candidate)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// One suggestion. A round dot rather than a box, because at most one applies —
    /// and a second tap takes it back again, without needing a "none of these" row for
    /// the purpose.
    private func candidateRow(index: Int, candidate: CodeCandidate) -> some View {
        let picked = proposal.chosenCandidate == index
        return Button {
            proposal.chosenCandidate = picked ? nil : index
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(picked ? EH.navy : EH.hairStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(EH.bodySmall.weight(picked ? .semibold : .medium))
                        .foregroundStyle(EH.navy)
                        .multilineTextAlignment(.leading)
                    Text(candidateCaption(candidate))
                        .font(EH.meta)
                        .foregroundStyle(candidate.match == .exact ? EH.muted : EH.warn)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(EHTap())
        .accessibilityLabel(picked ? String(localized: "Gewählt: \(candidate.title)")
                                    : String(localized: "Vorschlag: \(candidate.title)"))
        .accessibilityHint(candidateCaption(candidate))
    }

    /// How far the suggestion is from the number that was read, and where it comes
    /// from.
    ///
    /// For `near` the differing number stands there instead of the classification:
    /// "there: 42BYGH3701-B-80S80" says more than "almost the same number", because
    /// you can compare it against the lettering in your hand. For `family` the number
    /// in the hit is usually only a stem — there the classification is the more honest
    /// answer.
    private func candidateCaption(_ candidate: CodeCandidate) -> String {
        var parts: [String] = []
        if candidate.match == .near, !candidate.codeSeen.isEmpty {
            parts.append(String(localized: "dort: \(candidate.codeSeen)"))
        } else {
            parts.append(candidate.match.label)
        }
        if !candidate.sourceName.isEmpty { parts.append(candidate.sourceName) }
        return parts.joined(separator: " · ")
    }

    /// Quantity, with "—" for uncounted.
    ///
    /// The dash is not an empty field but a value: the model has said that it cannot
    /// count. Whoever counts for themselves types the number; whoever does not leaves
    /// it standing — and the inventory then claims no quantity.
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
                .accessibilityLabel(Text("Menge verringern"))

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
                    .accessibilityLabel(Text("Menge ungezählt"))
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
            .accessibilityLabel(Text("Menge erhöhen"))
        }
    }
}
