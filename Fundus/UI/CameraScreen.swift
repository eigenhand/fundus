import AVFoundation
import SwiftUI

/// The viewfinder.
///
/// The one button this whole app hangs on: whoever stands in front of a shelf
/// photographs it instead of typing forty lines. `UIImagePickerController` used to sit
/// behind it — one picture, confirm, close. For a thing in your hand that was right,
/// for a walk through a cellar it was not.
///
/// Hence a picker and not a decision: **single photo** does it as before, **documen-
/// tation** leaves the viewfinder open and sends every picture straight into the
/// queue. The difference is not convenience but whether you record a cellar in one
/// pass or in twelve.
struct CameraScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Where the shots go. Settled before anybody presses the shutter — you know it
    /// anyway, you are standing right there.
    ///
    /// As a binding and not a value: the place is chosen here in the viewfinder and
    /// stays in force afterwards. Whoever records twelve boards in a cellar and
    /// changes shelf once should not have to rearrange twelve entries afterwards.
    @Binding var placeID: UUID?

    /// The way through to the places. The viewfinder closes for it — see `placeMenu`.
    let onNewPlace: () -> Void

    @State private var camera = CameraSession()
    @State private var failure: CameraSession.Failure?
    @State private var starting = true
    @State private var mode: CaptureMode = .single
    @State private var flash: AVCaptureDevice.FlashMode = .auto
    /// What was captured in this pass — only as evidence that it worked.
    @State private var taken: [UIImage] = []
    @State private var shutterGlow = false
    @State private var zoom = CameraSession.Zoom()
    /// The zoom level when the two fingers land. Without it every movement would be
    /// absolute rather than relative, and the viewfinder would jump on being touched.
    @State private var pinchStart: CGFloat?
    /// The still image in object mode, while the user is choosing.
    @State private var pendingShot: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if failure == nil {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    // Two fingers, as in any camera. Without smoothing: the gesture
                    // should follow the fingers, not run along behind them.
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
                // The viewfinder stays underneath and keeps running: whoever discards
                // should be able to shoot again at once, without the camera having to
                // switch itself back on first.
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
            .accessibilityLabel(Text("Sucher schliessen"))

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
            .accessibilityLabel(Text("Blitz: \(flash.label)"))
            .disabled(failure != nil)
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 8)
    }

    private var placeLabel: String {
        placeID.map { model.inventory.tree.path(of: $0) } ?? "Ohne Ort"
    }

    /// Where the next shot goes — in the viewfinder and not behind it.
    ///
    /// This used to show only what had been set in the list. That is the wrong order:
    /// you know the place while you are standing in front of it, not before you set
    /// off. Whoever noticed down in the cellar that the shots were going to the old
    /// shelf had to close the viewfinder, change it and open it again — or fix it
    /// afterwards across forty entries.
    private var placeMenu: some View {
        Menu {
            // With ticks rather than as a row of buttons: the question is not "what do
            // I do" but "where am I", and that deserves a visible answer.
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
                // The viewfinder closes, the places open. A sheet over the camera
                // would work too and would be worse: creating a place means sorting a
                // tree — nesting, renaming, checking what is already there. That is
                // not an action for a scrap of paper over the viewfinder. One tap gets
                // you back, and in exchange you always know where you are.
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
        .accessibilityLabel(Text("Ort für die Aufnahmen: \(placeLabel)"))
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

    /// The lenses as buttons, as in the system camera.
    ///
    /// The stops come from the device and not from a list: only the phone knows which
    /// lenses are fitted. On one without an ultra-wide there is only "1×" here, and
    /// then the row disappears altogether — a button without a choice is not one.
    @ViewBuilder
    private var zoomPicker: some View {
        if failure == nil, zoom.stops.count > 1 {
            HStack(spacing: 6) {
                ForEach(zoom.stops, id: \.self) { stop in
                    let active = nearestStop == stop
                    Button {
                        apply(stop, smooth: true)
                    } label: {
                        // The active button carries the real value — whoever stands
                        // between two lenses with their fingers wants to read 1.8×,
                        // not 1×.
                        Text(active ? zoom.label(zoom.current) : zoom.label(stop))
                            .font(.eh(active ? 13 : 12, .caption, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(active ? .black : .white)
                            .frame(minWidth: 40)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(active ? .white : .black.opacity(0.35)))
                    }
                    .buttonStyle(EHTap())
                    .accessibilityLabel(Text("Zoom \(zoom.label(stop))"))
                }
            }
        }
    }

    /// Which button currently applies: the nearest one below the current level.
    private var nearestStop: CGFloat? {
        zoom.stops.last { $0 <= zoom.current + 0.001 } ?? zoom.stops.first
    }

    private func apply(_ factor: CGFloat, smooth: Bool) {
        let wanted = min(max(factor, zoom.minimum), zoom.maximum)
        zoom.current = wanted
        camera.setZoom(wanted, smooth: smooth)
    }

    /// The picker, and beneath it in one line what it means.
    ///
    /// The line is there because "documentation" on its own says nothing. Two words of
    /// explanation are cheaper than a user who never tries the mode because they do
    /// not know what will happen.
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
        .accessibilityLabel(Text("Auslösen"))
    }

    /// The most recent picture, small and on the left.
    ///
    /// In documentation mode it is the only feedback that a shutter press arrived —
    /// the queue lies behind this screen, and without that evidence you end up
    /// photographing the same board twice.
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

    /// Whether the viewfinder stays open after a shot.
    ///
    /// In object mode it does too: whoever taps objects once usually does it again at
    /// the next board.
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

    // MARK: Shutter

    /// The queue has an upper bound, and exceeding it silently would be the worst
    /// case: the user hears the shutter and gets no photo.
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
                // In object mode nothing is queued straight away: first the user says
                // what in the picture they mean.
                if mode == .objects {
                    // Here, once: bake the sensor's rotation into the pixels.
                    // Everything after it — display, tap, mask, cut-out — then works
                    // in the same frame. Before, display and model were ninety degrees
                    // apart.
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

    // MARK: When there is no viewfinder

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
    /// Off → auto → on → off. Three states on one button, because a shelf in a cellar
    /// needs light and a shelf by the window does not.
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
