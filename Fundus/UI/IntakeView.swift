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
            // „Später" und nicht „Abbrechen": der Auftrag bleibt in der Reihe und
            // lässt sich weiter hinten wieder antippen. Wer ihn wirklich loswerden
            // will, hält das Symbol in der Reihe gedrückt — das ist der seltenere
            // Fall und darf den längeren Weg haben.
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
        job.placeID.map { model.inventory.tree.path(of: $0) } ?? "Ohne Ort"
    }

    // MARK: Nachschlagen

    /// Eigener Schritt, weil er Sekunden dauert und etwas anderes tut als das Lesen.
    ///
    /// Mit Zähler statt Kreis: der Nutzer soll sehen, dass hier bezahlte Aufrufe
    /// laufen, und wie viele noch kommen.
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

    /// Eingereiht, aber noch kein Arbeiter frei.
    ///
    /// Eine eigene Ansicht und nicht derselbe Kreis wie beim Lesen: „wartet“ und
    /// „läuft“ verlangen verschiedene Geduld, und ein Kreis, der sich dreht, ohne dass
    /// etwas passiert, ist eine Lüge über den Zustand.
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
                Text("Es werden \(model.settings.intakeConcurrency) Fotos gleichzeitig "
                     + "gelesen. In den Einstellungen änderbar.")
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

    /// Gelesen, und es war kein Bestand darauf.
    ///
    /// Kein Fehlschlag, und deshalb auch nicht in dessen Karte: das Modell hat
    /// geantwortet, die Antwort war „hier ist nichts". Ein Kellerfenster, ein Foto,
    /// das schiefgegangen ist, eine Wand. Der zweite Versuch steht trotzdem da —
    /// manchmal war nur der Ausschnitt falsch.
    private var nothingOnIt: some View {
        VStack(spacing: 18) {
            photo(maxHeight: 220)

            HairlineCard(fill: EH.surfaceSunk) {
                VStack(alignment: .leading, spacing: 8) {
                    EH.label("Kein Bestand")
                    Text("Das Modell hat das Foto gelesen und nichts darauf gefunden, "
                         + "was in einen Bestand gehört.")
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

            // Das Foto liegt noch im Auftrag. Deshalb ist ein zweiter Versuch hier
            // billig — niemand muss nochmal in den Keller.
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

    // MARK: Prüfen

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

    /// Ein Eintrag, auf den dieser Vorschlag fallen würde — dann wird erhöht statt
    /// angelegt. Steht an der Zeile, damit der Nutzer es *vorher* weiß und nicht
    /// hinterher eine Menge findet, die er nicht erwartet hat.
    private func existing(for proposal: Proposal) -> Item? {
        model.inventory.existing(named: proposal.name, at: job.placeID)
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
            Text("Gelesen von \(job.result.model). Was du übernimmst, behält das "
                 + "als Herkunft und dieses Foto als Beleg.")
                .font(EH.meta)
                .foregroundStyle(EH.muted)
                .lineSpacing(2)
        }
    }

    /// Übernehmen — oder, wenn nichts angehakt ist, die Aufnahme wegwerfen.
    ///
    /// Hier stand „Nichts übernehmen" auf einem Knopf, der abgeschaltet war. Die
    /// Beschriftung versprach eine Handlung, der Knopf verweigerte sie, und wer alles
    /// abgewählt hatte, um die Aufnahme loszuwerden, saß fest. Ein abgeschalteter
    /// Knopf ist nur dann richtig, wenn es *nichts zu tun* gibt — hier gibt es etwas:
    /// diese Aufnahme soll weg.
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

    /// Die Kennung und, falls nachgeschlagen, die Auswahl dazu.
    ///
    /// Hier stand ein einzelner Vorschlag mit einem Häkchen. Jetzt stehen bis zu drei
    /// mit einem Punkt davor, und genau einer lässt sich antippen — oder keiner. Das
    /// ist die ganze Änderung, und sie verschiebt die Frage: nicht mehr „ist diese
    /// Deutung richtig?“, was niemand hier entscheiden kann, sondern „welches davon
    /// ist es?“, was jeder entscheiden kann, der das Ding in der Hand hält.
    ///
    /// Ausgewählt ist nichts. Ein aufgelöster Produktname steht am Ende einer Kette
    /// aus unscharfem Aufkleber, verwechselbaren Zeichen und einer Suchmaschine, die
    /// auf alles antwortet — und sieht danach verlässlicher aus als alles andere im
    /// Bestand. Die Nummer darüber und die abweichende Nummer daneben machen ihn
    /// nachprüfbar.
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
                // Auch das gehört hin. Eine leere Stelle unter der Nummer sieht aus,
                // als hätte niemand gesucht — und lässt den Nutzer nicht wissen, ob
                // er es noch einmal versuchen soll.
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

    /// Ein Vorschlag. Runder Punkt statt Kästchen, weil höchstens einer gilt — und
    /// ein zweites Antippen nimmt ihn wieder zurück, ohne dass es dafür eine Zeile
    /// „keiner davon“ braucht.
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
        .accessibilityLabel((picked ? "Gewählt: " : "Vorschlag: ") + candidate.title)
        .accessibilityHint(candidateCaption(candidate))
    }

    /// Wie weit der Vorschlag von der gelesenen Nummer entfernt ist, und woher er
    /// kommt.
    ///
    /// Bei `near` steht die abweichende Nummer statt der Einstufung: „dort:
    /// 42BYGH3701-B-80S80“ sagt mehr als „fast dieselbe Nummer“, weil man es mit dem
    /// Aufdruck in der Hand vergleichen kann. Bei `family` ist die Nummer im Treffer
    /// meist nur ein Stamm — da ist die Einstufung die ehrlichere Auskunft.
    private func candidateCaption(_ candidate: CodeCandidate) -> String {
        var parts: [String] = []
        if candidate.match == .near, !candidate.codeSeen.isEmpty {
            parts.append("dort: \(candidate.codeSeen)")
        } else {
            parts.append(candidate.match.label)
        }
        if !candidate.sourceName.isEmpty { parts.append(candidate.sourceName) }
        return parts.joined(separator: " · ")
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
