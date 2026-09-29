import SwiftUI

/// The queue of running shots, as a strip above the action bar.
///
/// This is the one view that turns "one photo after another" into a workbench. Before,
/// every shot held the whole screen until it was through — whoever brought twelve
/// photos back from a walk along a shelf waited twelve times. Now every photo sits in
/// the queue as a thumbnail, works away on its own, and the user carries on taking
/// pictures.
///
/// The photo **is** the thumbnail, and stays so until it has been assigned. A name
/// could not stand there — nobody knows it yet, that is the whole point. A placeholder
/// would be useless in a row of twelve identical-looking tiles: which shelf board is
/// meant is something you know from the picture in a tenth of a second and from "shot
/// 7" not at all.
struct IntakeQueueStrip: View {
    @Environment(AppModel.self) private var model
    /// Which job the user tapped.
    @Binding var open: IntakeJob?

    var body: some View {
        if !model.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    EH.label("Aufnahmen")
                    Text(summary)
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                    Spacer(minLength: 0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.jobs) { job in
                            tile(job)
                        }
                    }
                    .padding(.vertical, 2)
                }
                // The strip does not grow with it: at twenty jobs the list underneath
                // should not shrink to a slit.
                .frame(height: 62)
            }
            .padding(.horizontal, EH.gutter)
            .padding(.bottom, 8)
        }
    }

    /// "3 running · 2 to check" — and only the parts that currently exist.
    private var summary: String {
        let busy = model.jobs.filter { $0.phase.isBusy }.count
        let waiting = model.jobs.filter { $0.phase.isWaiting }.count
        let ready = model.jobs.filter { $0.phase == .review }.count
        let empty = model.jobs.filter { $0.phase == .empty }.count
        let failed = model.jobs.filter { if case .failed = $0.phase { return true } else { return false } }.count

        var parts: [String] = []
        if busy > 0 { parts.append(String(localized: "\(busy) in Arbeit")) }
        if waiting > 0 { parts.append(String(localized: "\(waiting) wartet")) }
        if ready > 0 { parts.append(String(localized: "\(ready) zu prüfen")) }
        if empty > 0 { parts.append(String(localized: "\(empty) ohne Bestand")) }
        if failed > 0 { parts.append(String(localized: "\(failed) fehlgeschlagen")) }
        return parts.joined(separator: " · ")
    }

    private func tile(_ job: IntakeJob) -> some View {
        Button {
            open = job
        } label: {
            Image(uiImage: job.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { scrim(job.phase) }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(border(job.phase), lineWidth: job.phase == .review ? 1.5 : EH.hairWidth)
                }
                .overlay(alignment: .bottomTrailing) { badge(job) }
        }
        .buttonStyle(EHTap())
        .contextMenu {
            switch job.phase {
            case .failed, .empty:
                Button { model.retry(job) } label: {
                    Label("Nochmal versuchen", systemImage: "arrow.clockwise")
                }
            default:
                EmptyView()
            }
            Button(role: .destructive) { model.discard(job) } label: {
                Label("Verwerfen", systemImage: "trash")
            }
        }
        .accessibilityLabel(spoken(job))
    }

    /// What is still working lies under a veil. What is finished lies clear — that is
    /// the difference you have to be able to see in passing.
    @ViewBuilder
    private func scrim(_ phase: IntakeJob.Phase) -> some View {
        switch phase {
        case .waiting:
            ZStack {
                Color.black.opacity(0.38)
                Image(systemName: "hourglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .reading, .looking:
            ZStack {
                Color.black.opacity(0.38)
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .review, .empty, .failed:
            Color.clear
        }
    }

    private func border(_ phase: IntakeJob.Phase) -> Color {
        switch phase {
        case .review: return EH.navy
        case .empty:  return EH.hairStrong
        case .failed: return EH.bad
        default:      return EH.hair
        }
    }

    @ViewBuilder
    private func badge(_ job: IntakeJob) -> some View {
        if let text = job.badge {
            Text(text)
                .font(.eh(11, .caption2, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(EH.onAccent)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(badgeTint(job.phase)))
                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                .offset(x: 5, y: 5)
        }
    }

    /// Grey for "nothing on it", red only for a real failure.
    private func badgeTint(_ phase: IntakeJob.Phase) -> Color {
        switch phase {
        case .failed: return EH.bad
        case .empty:  return EH.hairStrong
        default:      return EH.navy
        }
    }

    private func spoken(_ job: IntakeJob) -> String {
        switch job.phase {
        case .waiting:  return String(localized: "Aufnahme, wartet in der Reihe")
        case .reading:  return String(localized: "Aufnahme, wird gelesen")
        case .looking:  return String(localized: "Aufnahme, Nummern werden nachgeschlagen")
        case .review:   return String(localized: "Aufnahme, \(job.result.proposals.count) Vorschläge zum Prüfen")
        case .empty:    return String(localized: "Aufnahme gelesen, kein Bestand auf dem Foto")
        case .failed:   return String(localized: "Aufnahme fehlgeschlagen")
        }
    }
}
