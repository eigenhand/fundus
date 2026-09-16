import SwiftUI

/// The still image on which the user taps what they mean.
///
/// Why this is more than convenience: a cut-out reads better than a shelf. Send the
/// model a wide board with twelve things on it and it counts twelve things and
/// describes each one halfway. Send it a motor and it reads the lettering. Whoever
/// taps three objects here gets three shots instead of one — and three usable entries
/// instead of one collective line.
///
/// How the edge is found depends on what is on the device:
///
///  - **With SAM 2.1**: the tap *is* the question. The model answers where the thing
///    that was pointed at stops. No preselection, no guessing.
///  - **Without**: Apple's instance mask picks out for itself what counts as an
///    object. On a portrait it hits; on a workbench it misses, and that is no
///    accident — it is built for subjects, not for parts.
///
/// Above both stands the drawn box: whoever drags a frame has answered the question
/// themselves, and then none is asked. What lies inside goes into the shot whole — no
/// outline, no white patches, no second cut-out over the same thing.
///
/// Preselected in both cases is the centre. That is the commonest case: you hold
/// something in your hand and aim at it.
struct ObjectPicker: View {
    @Environment(AppModel.self) private var model

    /// The photo — **with the rotation baked in**, see `CameraScreen.shoot`.
    ///
    /// A camera photo stands upright because a flag sits beside it, not because the
    /// pixels lie that way. Whoever displays it sees the flag; whoever takes `cgImage`
    /// does not. Display, tap, box and cut-out have to mean the same frame, otherwise
    /// the mask points somewhere other than the finger — and that is exactly how it
    /// looked on the device.
    ///
    /// The rotation therefore happens once at the source and not here: a view is
    /// rebuilt on every change, and redrawing an image on every rebuild would be a
    /// correction you notice as stutter.
    let image: UIImage
    let placeID: UUID?
    /// Back to the viewfinder without queuing anything.
    let onDiscard: () -> Void
    /// Queued. The viewfinder carries on afterwards.
    let onTaken: () -> Void

    /// What the user tapped — as a mask with SAM, otherwise as a box.
    @State private var picked: [SegmentedObject] = []
    /// The fallback without SAM: what Apple finds by itself.
    @State private var offered: [FoundObject] = []
    @State private var chosenOffers: Set<Int> = []

    @State private var segmenter: Segmenter?
    @State private var preparing = true
    @State private var working = false
    @State private var trouble: String?

    /// The box being dragged, while the finger is down. In view coordinates.
    @State private var band: (from: CGPoint, to: CGPoint)?

    private var usingSam: Bool { segmenter != nil }

    var body: some View {
        VStack(spacing: 0) {
            picture
            bar
        }
        .task { await prepare() }
    }

    // MARK: Vorbereiten

    private func prepare() async {
        if SegmentAssets.looksInstalled {
            let engine = Segmenter()
            do {
                try await engine.encode(image)
                segmenter = engine
                // Preselect the centre: whoever aims means one thing.
                if let middle = try await engine.object(at: CGPoint(x: 0.5, y: 0.5)) {
                    picked = [middle]
                }
                preparing = false
                return
            } catch {
                // No reason to stop here — the fallback will do.
                trouble = (error as? Segmenter.Failure).map(Self.reason) ?? error.localizedDescription
            }
        }
        offered = await ObjectFinder.find(in: image)
        if let middle = offered.min(by: { $0.distanceFromCentre < $1.distanceFromCentre }) {
            chosenOffers = [middle.id]
        }
        preparing = false
    }

    private static func reason(_ failure: Segmenter.Failure) -> String {
        switch failure {
        case .notInstalled: return "Das Erkennungsmodell liegt nicht auf dem Gerät."
        case .broken(let why): return why
        }
    }

    // MARK: Das Bild

    private var picture: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                // With SAM: the outlines lie over the whole image, each in its own
                // layer. The box beside it shows what will be cut.
                ForEach(picked) { object in
                    let rect = frame(for: CGRect(x: 0, y: 0, width: 1, height: 1), in: geo.size)
                    if let mask = object.mask {
                        Image(uiImage: mask)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                    let box = frame(for: object.box, in: geo.size)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2.5)
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .allowsHitTesting(false)
                }

                // Without SAM: the suggestions as tappable frames.
                ForEach(offered) { object in
                    let rect = frame(for: object.box, in: geo.size)
                    offerOutline(object)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if preparing || working {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(preparing ? "Das Bild wird vorbereitet." : "Kante suchen …")
                            .font(EH.meta)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.5)))
                    .allowsHitTesting(false)
                }
            }
            .overlay { rubberBand(in: geo.size) }
            .contentShape(Rectangle())
            // The tap is the question. Only with SAM — without it there is nothing to
            // ask, the answers already stand there as frames.
            .onTapGesture { location in
                guard !preparing, !working else { return }
                guard let point = normalised(location, in: geo.size) else { return }
                // Deselecting always works — even without a model, because dragging
                // works there too. A box you cannot get rid of again would be worse
                // than no box at all.
                if let hit = picked.first(where: { $0.box.contains(point) }) {
                    picked.removeAll { $0.id == hit.id }
                    trouble = nil
                    return
                }
                guard usingSam else { return }
                Task { await tap(point) }
            }
            // Drag instead of tap: circle the object yourself. For the case where a
            // tap hits the wrong thing — something against a busy background, or one
            // that half covers another.
            //
            // Ten points of minimum travel, so a tap stays a tap: at zero minimum
            // travel the drag swallows every touch, and the frames in fallback mode
            // would no longer be tappable.
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard !preparing, !working else { return }
                        band = (value.startLocation, value.location)
                    }
                    .onEnded { value in
                        let drawn = band
                        band = nil
                        guard !preparing, !working, let drawn else { return }
                        guard let box = normalisedBox(from: drawn.from, to: value.location,
                                                      in: geo.size) else { return }
                        circle(box)
                    })
        }
    }

    private func offerOutline(_ object: FoundObject) -> some View {
        let isPicked = chosenOffers.contains(object.id)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isPicked ? Color.white.opacity(0.16) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isPicked ? .white : .white.opacity(0.65),
                                  lineWidth: isPicked ? 3 : 1.5))
            .overlay(alignment: .topTrailing) {
                if isPicked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.white, EH.navy)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isPicked { chosenOffers.remove(object.id) } else { chosenOffers.insert(object.id) }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isPicked ? "Gewählt" : "Gegenstand")
    }

    /// The box while it is being dragged.
    @ViewBuilder
    private func rubberBand(in size: CGSize) -> some View {
        if let band {
            let rect = CGRect(x: min(band.from.x, band.to.x), y: min(band.from.y, band.to.y),
                              width: abs(band.to.x - band.from.x),
                              height: abs(band.to.y - band.from.y))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.12)))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    /// A view point in image coordinates, or nil if it lies beside the image.
    private func normalised(_ point: CGPoint, in size: CGSize) -> CGPoint? {
        let rect = frame(for: CGRect(x: 0, y: 0, width: 1, height: 1), in: size)
        guard rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width,
                       y: (point.y - rect.minY) / rect.height)
    }

    /// Two corners into a box in image coordinates.
    ///
    /// Clipped rather than discarded: whoever drags past the edge means the thing up
    /// to the edge and not "nothing".
    private func normalisedBox(from: CGPoint, to: CGPoint, in size: CGSize) -> CGRect? {
        Self.box(from: from, to: to,
                 picture: Self.frame(for: CGRect(x: 0, y: 0, width: 1, height: 1),
                                     image: image.size, in: size))
    }

    /// The same arithmetic without a view, so that it can be tested.
    ///
    /// Three things sit inside it, and each would be its own small annoyance: the
    /// corners can arrive in any order (dragging from bottom right to top left means
    /// the same box), they can lie beside the image (then the edge applies, not
    /// "nothing"), and a line is not a box.
    nonisolated static func box(from: CGPoint, to: CGPoint, picture: CGRect) -> CGRect? {
        guard picture.width > 0, picture.height > 0 else { return nil }
        func place(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max((p.x - picture.minX) / picture.width, 0), 1),
                    y: min(max((p.y - picture.minY) / picture.height, 0), 1))
        }
        let a = place(from), b = place(to)
        let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                         width: abs(b.x - a.x), height: abs(b.y - a.y))
        return box.width > 0.02 && box.height > 0.02 ? box : nil
    }

    /// A dragged box is the box. No model in between.
    ///
    /// SAM could be asked here, and it would answer: Apple's implementation knows the
    /// box prompt, two points with the labels 2 and 3, and on the Mac it delivers the
    /// edge of the thing in the frame to within two parts per thousand. On a shelf
    /// photo that is exactly the wrong answer. It picks **one** thing inside the box,
    /// and the cut-out gets white patches everywhere the mask did not quite hit the
    /// thing or a second one lay beside it.
    ///
    /// Whoever drags a frame by hand has already said what they mean. A model that
    /// asks the same question again and answers it differently is then not a gain but
    /// a contradiction.
    private func circle(_ box: CGRect) {
        guard Self.isUsable(box, pixels: pixels) else {
            trouble = String(localized: "Der Kasten ist zu klein — daraus liest auch das Modell nichts.")
            return
        }
        trouble = nil
        picked = Self.replacing(picked, by: box)
    }

    /// The dragged box overwrites whatever was already picked at that spot.
    ///
    /// Otherwise one cut-out would lie over another: two paid shots for one thing,
    /// and half of it missing on one of them. What lies elsewhere stays — whoever
    /// tapped two things first and then circles a third means three.
    ///
    /// Static, so the rule can be tested: that a box replaces the old find at its own
    /// spot and not the one at the other edge of the image is not something you can
    /// see in a screenshot.
    nonisolated static func replacing(_ picked: [SegmentedObject], by box: CGRect) -> [SegmentedObject] {
        picked.filter { !overlaps($0.box, box) }
            + [SegmentedObject(id: UUID(), box: box, mask: nil, bits: [], side: 0)]
    }

    /// The pixels of the image, not its points.
    ///
    /// `size` of a `UIImage` is in points, and for an image at scale 2 that would be
    /// half the truth. `ObjectFinder` cuts in pixels, so the measuring here happens in
    /// pixels too.
    private var pixels: CGSize {
        guard let cg = image.cgImage else { return image.size }
        return CGSize(width: cg.width, height: cg.height)
    }

    /// Whether this box can become a cut-out at all.
    ///
    /// The box is in fractions of the image, the limit is in pixels — which is why the
    /// question needs the size of the image. Without it a box that is too small would
    /// vanish silently: `ObjectFinder` returns nothing below `minimumEdge`, the bar
    /// would have promised "1 cut-out", and the whole board would go into the queue.
    /// Better to say straight away that the frame was too small.
    nonisolated static func isUsable(_ box: CGRect, pixels: CGSize) -> Bool {
        let floor = CGFloat(ObjectFinder.minimumEdge)
        return (box.width * pixels.width).rounded() >= floor
            && (box.height * pixels.height).rounded() >= floor
    }

    /// A tap: either deselect a thing that was already picked, or add a new one.
    private func tap(_ point: CGPoint) async {
        guard let segmenter else { return }
        working = true
        trouble = nil
        defer { working = false }
        do {
            guard let object = try await segmenter.object(at: point) else {
                // Saying nothing would be the worst thing here: the user tapped and
                // nothing happened, and they cannot tell whether the app heard them or
                // the model found nothing.
                trouble = String(localized: "Da war keine Kante zu finden. Tippe mitten auf das Ding.")
                return
            }
            // Tapping the same thing twice should not double it.
            guard !picked.contains(where: { Self.overlaps($0.box, object.box) }) else { return }
            picked.append(object)
        } catch {
            trouble = error.localizedDescription
        }
    }

    /// Whether two boxes mean the same thing: more than sixty per cent of the smaller
    /// one lies inside the other.
    nonisolated static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let cut = a.intersection(b)
        guard !cut.isNull else { return false }
        let shared = cut.width * cut.height
        return shared > 0.6 * min(a.width * a.height, b.width * b.height)
    }

    private func frame(for box: CGRect, in size: CGSize) -> CGRect {
        Self.frame(for: box, image: image.size, in: size)
    }

    /// Where a box in 0…1 falls on the fitted image.
    ///
    /// Worked out by hand rather than asked of SwiftUI: `aspectRatio(.fit)` leaves a
    /// margin at the top and bottom — or left and right — that the geometry of the
    /// surrounding view knows nothing about. Without this arithmetic every frame is
    /// off by the same amount, and evenly enough that it looks as if the detection
    /// were wrong rather than the arithmetic.
    ///
    /// Static, so that it can be tested: a screenshot shows that frames lie somewhere,
    /// not that they lie in the right place.
    nonisolated static func frame(for box: CGRect, image: CGSize, in size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, size.width > 0, size.height > 0
        else { return .zero }
        let imageRatio = image.width / image.height
        let areaRatio = size.width / size.height

        var width = size.width, height = size.height
        if imageRatio > areaRatio { height = width / imageRatio } else { width = height * imageRatio }
        let left = (size.width - width) / 2, top = (size.height - height) / 2

        return CGRect(x: left + box.minX * width, y: top + box.minY * height,
                      width: box.width * width, height: box.height * height)
    }

    // MARK: Die Leiste

    private var bar: some View {
        VStack(spacing: 8) {
            Text(note)
                .font(EH.meta)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack(spacing: 12) {
                Button("Verwerfen", action: onDiscard)
                    .font(.eh(15, .callout))
                    .foregroundStyle(.white.opacity(0.85))
                    .buttonStyle(EHTap())

                Spacer(minLength: 0)

                Button(action: take) {
                    Text(takeLabel)
                        .font(.eh(16, .callout, weight: .medium))
                        .foregroundStyle(EH.navy)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(EHTap())
                .disabled(preparing)
            }
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.black.opacity(0.4))
    }

    private var count: Int { usingSam ? picked.count : picked.count + chosenOffers.count }

    private var takeLabel: String {
        switch count {
        case 0: return "Ganzes Bild"
        case 1: return "1 Ausschnitt"
        case let n: return "\(n) Ausschnitte"
        }
    }

    /// What the button costs before it is pressed, and what finds the edge.
    ///
    /// Every cut-out is its own shot and therefore its own paid call. That belongs
    /// visibly beside it and not in a bill afterwards.
    private var note: String {
        if preparing { return "Das Gerät sieht sich das Bild an." }
        if let trouble { return trouble }
        if usingSam {
            if picked.isEmpty {
                return "Tippe an, was du meinst — oder zieh einen Kasten darum."
            }
            return picked.count == 1
                ? "Ein Ausschnitt, eine Aufnahme. Weitere antippen geht."
                : "\(picked.count) Ausschnitte, \(picked.count) Aufnahmen."
        }
        if offered.isEmpty {
            return "Keine einzelnen Gegenstände erkannt — das ganze Bild geht als eine Aufnahme. Mit dem Erkennungsmodell aus den Einstellungen ginge das besser."
        }
        return chosenOffers.isEmpty && picked.isEmpty
            ? "Nichts gewählt: das ganze Bild geht als eine Aufnahme. Einen Kasten ziehen geht auch."
            : "\(count) Ausschnitt\(count == 1 ? "" : "e") — so viele Aufnahmen."
    }

    private func take() {
        // With an outline the object is cut free: the thing stays, the rest turns
        // white. Without an outline — that is, for a box dragged by hand — everything
        // inside it stays, and **without padding**: in the suggestions below, the
        // frame sits on the edge by machine and the lettering beside it would
        // otherwise be lost; here a person dragged it and meant, in doing so, where it
        // should stop.
        let fromPicked = picked.compactMap { object in
            object.bits.isEmpty
                ? ObjectFinder.crop(image, to: object.box, margin: 0)
                : ObjectFinder.cutOut(image, object: object)
        }
        let fromOffers = usingSam ? [] : offered
            .filter { chosenOffers.contains($0.id) }
            .compactMap { ObjectFinder.crop(image, to: $0.box) }
        let pieces = fromPicked + fromOffers

        // Nothing tapped, or no cut-out usable: then the whole image it is. Leaving
        // this screen empty-handed would be the wrong way out — the photo has been
        // taken, and it should end up somewhere.
        let images = pieces.isEmpty ? [image] : pieces
        model.enqueue(images, placeID: placeID)
        onTaken()
    }
}
