import AVFoundation
import SwiftUI

/// Der Sucher.
///
/// Der eine Knopf, an dem diese App hängt: wer vor einem Regal steht, fotografiert es,
/// statt vierzig Zeilen zu tippen. Bisher lag dahinter `UIImagePickerController` —
/// ein Bild, bestätigen, zu. Für ein Ding in der Hand war das richtig, für einen
/// Kellergang nicht.
///
/// Deshalb ein Wähler und nicht eine Entscheidung: **Einzelfoto** macht es wie vorher,
/// **Doku** lässt den Sucher offen und schickt jedes Bild sofort in die Reihe. Der
/// Unterschied ist nicht Bequemlichkeit, sondern ob man einen Keller in einem Gang
/// aufnimmt oder in zwölf.
struct CameraScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Wohin die Aufnahmen kommen. Steht schon fest, bevor jemand auslöst — man weiß
    /// es ja, man steht davor.
    ///
    /// Als Bindung und nicht als Wert: der Ort wird hier im Sucher gewählt und gilt
    /// danach weiter. Wer im Keller zwölf Bretter aufnimmt und dabei einmal das Regal
    /// wechselt, soll nicht hinterher zwölf Einträge umräumen.
    @Binding var placeID: UUID?

    /// Der Weg zu den Orten. Der Sucher schliesst sich dabei — siehe `placeMenu`.
    let onNewPlace: () -> Void

    @State private var camera = CameraSession()
    @State private var failure: CameraSession.Failure?
    @State private var starting = true
    @State private var mode: CaptureMode = .single
    @State private var flash: AVCaptureDevice.FlashMode = .auto
    /// Was in diesem Durchgang aufgenommen wurde — nur als Beleg, dass es geklappt hat.
    @State private var taken: [UIImage] = []
    @State private var shutterGlow = false
    @State private var zoom = CameraSession.Zoom()
    /// Der Stand beim Ansetzen der zwei Finger. Ohne ihn waere jede Bewegung
    /// absolut statt relativ, und der Sucher spraenge beim Anfassen.
    @State private var pinchStart: CGFloat?
    /// Das stehende Bild im Objekte-Modus, solange der Nutzer auswählt.
    @State private var pendingShot: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if failure == nil {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    // Zwei Finger, wie in jeder Kamera. Ohne Glaetten: die Geste soll
                    // den Fingern folgen und nicht hinterherlaufen.
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let start = pinchStart ?? zoom.current
                                if pinchStart == nil { pinchStart = start }
                                apply(start * value.magnification, smooth: false)
                            }
                            .onEnded { _ in pinchStart = nil })
            }

            if shutterGlow {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            if let shot = pendingShot {
                // Der Sucher bleibt darunter stehen und läuft weiter: wer verwirft,
                // soll sofort wieder auslösen können, ohne dass sich die Kamera erst
                // wieder einschaltet.
                ObjectPicker(image: shot, placeID: placeID,
                             onDiscard: { pendingShot = nil },
                             onTaken: {
                                 pendingShot = nil
                                 taken.append(shot)
                             })
                    .background(.black)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if let failure { trouble(failure) }
                    Spacer(minLength: 0)
                    bottomBar
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            mode = model.settings.captureMode
            failure = await camera.start()
            zoom = camera.zoom
            starting = false
        }
        .onDisappear { camera.stop() }
    }

    // MARK: Oben

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(EHTap())
            .accessibilityLabel("Sucher schliessen")

            Spacer(minLength: 8)

            placeMenu

            Spacer(minLength: 8)

            Button {
                flash = flash.next
                camera.flashMode = flash
            } label: {
                Image(systemName: flash.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(flash == .off ? .white.opacity(0.6) : .white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(EHTap())
            .accessibilityLabel("Blitz: \(flash.label)")
            .disabled(failure != nil)
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 8)
    }

    private var placeLabel: String {
        placeID.map { model.inventory.tree.path(of: $0) } ?? "Ohne Ort"
    }

    /// Wohin die nächste Aufnahme kommt — im Sucher und nicht dahinter.
    ///
    /// Bisher stand hier nur, was in der Liste eingestellt war. Das ist die falsche
    /// Reihenfolge: man weiß den Ort, während man davor steht, und nicht, bevor man
    /// losgeht. Wer erst im Keller merkt, dass die Aufnahmen ins alte Regal laufen,
    /// musste den Sucher schliessen, umstellen und wieder öffnen — oder es hinterher
    /// an vierzig Einträgen richten.
    private var placeMenu: some View {
        Menu {
            // Mit Haken statt als Knopfreihe: die Frage ist nicht „was tun", sondern
            // „wo bin ich", und darauf gehört eine sichtbare Antwort.
            Picker("Ort", selection: $placeID) {
                Text("Ohne Ort").tag(UUID?.none)
                ForEach(model.inventory.tree.flattened(), id: \.place.id) { entry in
                    Text(model.inventory.tree.path(of: entry.place.id))
                        .tag(UUID?.some(entry.place.id))
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button {
                // Der Sucher geht zu, die Orte gehen auf. Ein Blatt über der Kamera
                // ginge auch und wäre schlechter: einen Ort anzulegen heisst, einen
                // Baum zu sortieren — unterordnen, umbenennen, nachsehen, was schon
                // da ist. Das ist keine Handlung für einen Zettel über dem Sucher.
                // Zurück kommt man mit einem Tipp, und dafür weiss man jedes Mal,
                // wo man steht.
                onNewPlace()
                dismiss()
            } label: {
                Label("Ort anlegen …", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 5) {
                Text(placeLabel)
                    .font(EH.meta)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
        .accessibilityLabel("Ort für die Aufnahmen: \(placeLabel)")
    }

    // MARK: Unten

    private var bottomBar: some View {
        VStack(spacing: 14) {
            zoomPicker
            modePicker

            HStack(alignment: .center) {
                lastShot
                Spacer(minLength: 0)
                shutter
                Spacer(minLength: 0)
                done
            }
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(.black.opacity(0.35))
    }

    /// Die Linsen als Knöpfe, wie in der Kamera des Systems.
    ///
    /// Die Stellen kommen vom Gerät und nicht aus einer Liste: welche Linsen verbaut
    /// sind, weiß nur das Telefon. Auf einem ohne Ultraweitwinkel steht hier nur
    /// „1×", und dann bleibt die Zeile ganz weg — ein Knopf ohne Wahl ist keiner.
    @ViewBuilder
    private var zoomPicker: some View {
        if failure == nil, zoom.stops.count > 1 {
            HStack(spacing: 6) {
                ForEach(zoom.stops, id: \.self) { stop in
                    let active = nearestStop == stop
                    Button {
                        apply(stop, smooth: true)
                    } label: {
                        // Auf dem aktiven Knopf steht der wirkliche Wert — wer mit den
                        // Fingern zwischen zwei Linsen steht, will 1,8× lesen und
                        // nicht 1×.
                        Text(active ? zoom.label(zoom.current) : zoom.label(stop))
                            .font(.eh(active ? 13 : 12, .caption, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(active ? .black : .white)
                            .frame(minWidth: 40)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(active ? .white : .black.opacity(0.35)))
                    }
                    .buttonStyle(EHTap())
                    .accessibilityLabel("Zoom \(zoom.label(stop))")
                }
            }
        }
    }

    /// Welcher Knopf gerade gilt: der nächstgelegene unterhalb des Stands.
    private var nearestStop: CGFloat? {
        zoom.stops.last { $0 <= zoom.current + 0.001 } ?? zoom.stops.first
    }

    private func apply(_ factor: CGFloat, smooth: Bool) {
        let wanted = min(max(factor, zoom.minimum), zoom.maximum)
        zoom.current = wanted
        camera.setZoom(wanted, smooth: smooth)
    }

    /// Der Wähler, und darunter in einer Zeile, was er bedeutet.
    ///
    /// Die Zeile steht da, weil „Doku" allein nichts sagt. Zwei Wörter Erklärung sind
    /// billiger als ein Nutzer, der den Modus nie ausprobiert, weil er nicht weiß,
    /// was passiert.
    private var modePicker: some View {
        VStack(spacing: 5) {
            Picker("Modus", selection: Binding(
                get: { mode },
                set: { mode = $0; model.settings.captureMode = $0; model.save() })) {
                ForEach(CaptureMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Text(mode.hint)
                .font(EH.meta)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var shutter: some View {
        Button(action: shoot) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(queueIsFull ? 0.3 : 0.9), lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white.opacity(queueIsFull ? 0.3 : 1))
                    .frame(width: 58, height: 58)
                    .scaleEffect(shutterGlow ? 0.86 : 1)
            }
        }
        .buttonStyle(EHTap())
        .disabled(failure != nil || starting || queueIsFull)
        .accessibilityLabel("Auslösen")
    }

    /// Das zuletzt aufgenommene Bild, klein und links.
    ///
    /// Im Doku-Modus ist es die einzige Rückmeldung, dass ein Auslöser angekommen ist —
    /// die Reihe liegt hinter diesem Bildschirm, und ohne diesen Beleg fotografiert man
    /// im Zweifel zweimal dasselbe Brett.
    @ViewBuilder
    private var lastShot: some View {
        if let image = taken.last {
            HStack(spacing: 8) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.8), lineWidth: 1))
                if taken.count > 1 {
                    Text("\(taken.count)")
                        .font(.eh(15, .callout, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 84, alignment: .leading)
        } else {
            Color.clear.frame(width: 84, height: 42)
        }
    }

    /// Ob der Sucher nach einer Aufnahme offen bleibt.
    ///
    /// Im Objekte-Modus bleibt er es auch: wer einmal Gegenstände antippt, tut es
    /// meistens noch einmal am nächsten Brett.
    private var staysOpen: Bool { mode != .single }

    @ViewBuilder
    private var done: some View {
        if staysOpen {
            Button("Fertig") { dismiss() }
                .font(.eh(16, .callout, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 84, alignment: .trailing)
                .buttonStyle(EHTap())
        } else {
            Color.clear.frame(width: 84, height: 42)
        }
    }

    // MARK: Auslösen

    /// Die Reihe hat eine Obergrenze, und sie still zu überschreiten wäre der
    /// schlechteste Fall: der Nutzer hört den Auslöser und bekommt kein Foto.
    private var queueIsFull: Bool { model.jobs.count >= IntakeSchedule.maxQueued }

    private func shoot() {
        guard failure == nil, !queueIsFull else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeOut(duration: 0.06)) { shutterGlow = true }
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeIn(duration: 0.12)) { shutterGlow = false }
        }

        camera.capture { image in
            Task { @MainActor in
                // Im Objekte-Modus wird nicht sofort eingereiht: erst sagt der Nutzer,
                // was auf dem Bild er meint.
                if mode == .objects {
                    // Hier, einmal: die Drehung des Sensors in die Pixel zeichnen.
                    // Alles danach — Anzeige, Fingertipp, Maske, Ausschnitt — rechnet
                    // dann im selben Rahmen. Vorher lagen Anzeige und Modell um
                    // neunzig Grad auseinander.
                    let upright = image.scaledDown(maxEdge: 1_400)
                    withAnimation(.easeOut(duration: 0.15)) { pendingShot = upright }
                    return
                }
                model.enqueue([image], placeID: placeID)
                taken.append(image)
                if mode == .single { dismiss() }
            }
        }
    }

    // MARK: Wenn kein Sucher da ist

    private func trouble(_ failure: CameraSession.Failure) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.7))
            Text(failure.message)
                .font(EH.bodySmall)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
        }
    }
}

private extension AVCaptureDevice.FlashMode {
    /// Aus → Automatik → An → Aus. Drei Zustände an einem Knopf, weil ein Regal im
    /// Keller Licht braucht und ein Regal am Fenster keines.
    var next: AVCaptureDevice.FlashMode {
        switch self {
        case .off:  return .auto
        case .auto: return .on
        case .on:   return .off
        @unknown default: return .auto
        }
    }

    var symbol: String {
        switch self {
        case .off:  return "bolt.slash"
        case .auto: return "bolt.badge.a"
        case .on:   return "bolt.fill"
        @unknown default: return "bolt.badge.a"
        }
    }

    var label: String {
        switch self {
        case .off:  return "aus"
        case .auto: return "automatisch"
        case .on:   return "an"
        @unknown default: return "automatisch"
        }
    }
}
