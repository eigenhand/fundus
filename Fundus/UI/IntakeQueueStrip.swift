import SwiftUI

/// Die Reihe der laufenden Aufnahmen, als Streifen über der Handlungsleiste.
///
/// Das ist die eine Ansicht, die aus „ein Foto nach dem anderen“ eine Werkbank macht.
/// Vorher belegte jede Aufnahme den ganzen Bildschirm, bis sie durch war — wer zwölf
/// Fotos von einem Regalgang mitbrachte, wartete zwölfmal. Jetzt liegt jedes Foto als
/// Symbol in der Reihe, arbeitet für sich, und der Nutzer fotografiert weiter.
///
/// Das Foto **ist** das Symbol, und zwar solange, bis es zugeordnet ist. Ein Name
/// stünde dort nicht — den kennt ja noch niemand, das ist der Sinn der Sache. Ein
/// Platzhalter wäre in der Reihe von zwölf gleich aussehenden Kacheln unbrauchbar:
/// welches Regalbrett gemeint ist, weiß man am Bild in einer Zehntelsekunde und an
/// „Aufnahme 7“ gar nicht.
struct IntakeQueueStrip: View {
    @Environment(AppModel.self) private var model
    /// Welchen Auftrag der Nutzer angetippt hat.
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
                // Der Streifen wächst nicht mit: bei zwanzig Aufträgen soll die Liste
                // darunter nicht auf einen Spalt zusammenschrumpfen.
                .frame(height: 62)
            }
            .padding(.horizontal, EH.gutter)
            .padding(.bottom, 8)
        }
    }

    /// „3 in Arbeit · 2 zu prüfen“ — und nur die Teile, die es gerade gibt.
    private var summary: String {
        let busy = model.jobs.filter { $0.phase.isBusy }.count
        let waiting = model.jobs.filter { $0.phase.isWaiting }.count
        let ready = model.jobs.filter { $0.phase == .review }.count
        let empty = model.jobs.filter { $0.phase == .empty }.count
        let failed = model.jobs.filter { if case .failed = $0.phase { return true } else { return false } }.count

        var parts: [String] = []
        if busy > 0 { parts.append("\(busy) in Arbeit") }
        if waiting > 0 { parts.append("\(waiting) wartet") }
        if ready > 0 { parts.append("\(ready) zu prüfen") }
        if empty > 0 { parts.append("\(empty) ohne Bestand") }
        if failed > 0 { parts.append("\(failed) fehlgeschlagen") }
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

    /// Was noch arbeitet, liegt unter einem Schleier. Was fertig ist, liegt frei —
    /// das ist der Unterschied, den man im Vorbeigehen sehen muss.
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

    /// Grau für „nichts drauf", rot nur für einen echten Fehlschlag.
    private func badgeTint(_ phase: IntakeJob.Phase) -> Color {
        switch phase {
        case .failed: return EH.bad
        case .empty:  return EH.hairStrong
        default:      return EH.navy
        }
    }

    private func spoken(_ job: IntakeJob) -> String {
        switch job.phase {
        case .waiting:  return "Aufnahme, wartet in der Reihe"
        case .reading:  return "Aufnahme, wird gelesen"
        case .looking:  return "Aufnahme, Nummern werden nachgeschlagen"
        case .review:   return "Aufnahme, \(job.result.proposals.count) Vorschläge zum Prüfen"
        case .empty:    return "Aufnahme gelesen, kein Bestand auf dem Foto"
        case .failed:   return "Aufnahme fehlgeschlagen"
        }
    }
}
