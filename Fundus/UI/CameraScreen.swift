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
    let placeID: UUID?

    @State private var camera = CameraSession()
    @State private var failure: CameraSession.Failure?
    @State private var starting = true
    @State private var mode: CaptureMode = .single
    @State private var flash: AVCaptureDevice.FlashMode = .auto
    /// Was in diesem Durchgang aufgenommen wurde — nur als Beleg, dass es geklappt hat.
    @State private var taken: [UIImage] = []
    @State private var shutterGlow = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if failure == nil {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            }

            if shutterGlow {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if let failure { trouble(failure) }
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .task {
            mode = model.settings.captureMode
            failure = await camera.start()
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

            Text(placeLabel)
                .font(EH.meta)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))

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

    // MARK: Unten

    private var bottomBar: some View {
        VStack(spacing: 14) {
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
            .frame(maxWidth: 260)

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

    @ViewBuilder
    private var done: some View {
        if mode == .doku {
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
