import SwiftUI

/// Das stehende Bild, auf dem der Nutzer antippt, was er meint.
///
/// Der Grund, warum das mehr ist als Bequemlichkeit: ein Ausschnitt liest sich besser
/// als ein Regal. Schickt man dem Modell ein breites Brett mit zwölf Dingen, zählt es
/// zwölf Dinge und beschreibt jedes halb. Schickt man ihm einen Motor, liest es den
/// Aufdruck. Wer hier drei Gegenstände antippt, bekommt drei Aufnahmen statt einer —
/// und drei brauchbare Einträge statt einer Sammelzeile.
///
/// Wie die Kante gefunden wird, hängt davon ab, was auf dem Gerät liegt:
///
///  - **Mit SAM 2.1**: der Fingertipp *ist* die Frage. Das Modell antwortet, wo das
///    Ding aufhört, auf das gezeigt wurde. Keine Vorauswahl, kein Raten.
///  - **Ohne**: Apples Instanzmaske sucht sich selbst aus, was ein Gegenstand ist.
///    Bei einem Portrait trifft sie; bei einer Werkbank liegt sie daneben, und das
///    ist kein Zufall — sie ist für Motive gebaut, nicht für Bauteile.
///
/// Vorgewählt ist beide Male die Mitte. Das ist der häufigste Fall: man hält etwas in
/// der Hand und zielt darauf.
struct ObjectPicker: View {
    @Environment(AppModel.self) private var model

    /// Das Foto — **mit eingezeichneter Drehung**, siehe `CameraScreen.shoot`.
    ///
    /// Ein Kamerafoto steht aufrecht, weil ein Merker danebensteht, nicht weil die
    /// Pixel so liegen. Wer es anzeigt, sieht den Merker; wer `cgImage` nimmt, sieht
    /// ihn nicht. Anzeige, Fingertipp, Kasten und Ausschnitt müssen denselben Rahmen
    /// meinen, sonst zeigt die Maske woandershin als der Finger — und genau so sah es
    /// auf dem Gerät aus.
    ///
    /// Gedreht wird deshalb einmal an der Quelle und nicht hier: eine Ansicht wird bei
    /// jeder Änderung neu gebaut, und ein Bild bei jedem Neubau neu zu zeichnen wäre
    /// eine Korrektur, die man am Ruckeln merkt.
    let image: UIImage
    let placeID: UUID?
    /// Zurück zum Sucher, ohne etwas einzureihen.
    let onDiscard: () -> Void
    /// Eingereiht. Der Sucher macht danach weiter.
    let onTaken: () -> Void

    /// Was der Nutzer angetippt hat — mit SAM als Maske, sonst als Kasten.
    @State private var picked: [SegmentedObject] = []
    /// Der Rückfall ohne SAM: was Apple von sich aus findet.
    @State private var offered: [FoundObject] = []
    @State private var chosenOffers: Set<Int> = []

    @State private var segmenter: Segmenter?
    @State private var preparing = true
    @State private var working = false
    @State private var trouble: String?

    /// Der aufgezogene Kasten, solange der Finger liegt. In Ansichtskoordinaten.
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
                // Die Mitte vorwählen: wer zielt, meint eins.
                if let middle = try await engine.object(at: CGPoint(x: 0.5, y: 0.5)) {
                    picked = [middle]
                }
                preparing = false
                return
            } catch {
                // Kein Grund, hier stehen zu bleiben — der Rückfall tut es auch.
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

                // Mit SAM: die Umrisse liegen über dem ganzen Bild, jeder in seiner
                // eigenen Ebene. Der Kasten daneben zeigt, was geschnitten wird.
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

                // Ohne SAM: die Vorschläge als antippbare Rahmen.
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
            // Der Fingertipp ist die Frage. Nur mit SAM — ohne es gibt es nichts zu
            // fragen, da stehen die Antworten schon als Rahmen da.
            .onTapGesture { location in
                guard !preparing, !working else { return }
                guard let point = normalised(location, in: geo.size) else { return }
                // Abwählen geht immer — auch ohne Modell, denn gezogen werden kann
                // auch dort. Ein Kasten, den man nicht mehr loswird, waere schlimmer
                // als gar keiner.
                if let hit = picked.first(where: { $0.box.contains(point) }) {
                    picked.removeAll { $0.id == hit.id }
                    trouble = nil
                    return
                }
                guard usingSam else { return }
                Task { await tap(point) }
            }
            // Ziehen statt tippen: den Gegenstand selbst einkreisen. Für den Fall,
            // dass ein Tipp das Falsche trifft — ein Ding vor unruhigem Hintergrund,
            // oder eines, das ein anderes halb verdeckt.
            //
            // Zehn Punkte Mindestweg, damit ein Tipp ein Tipp bleibt: bei null
            // Mindestweg schluckt das Ziehen jede Berührung, und die Rahmen im
            // Rückfallmodus wären nicht mehr antippbar.
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
                        Task { await circle(box) }
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

    /// Der Kasten, solange gezogen wird.
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

    /// Ein Punkt der Ansicht in Bildkoordinaten, oder nil, wenn er neben dem Bild liegt.
    private func normalised(_ point: CGPoint, in size: CGSize) -> CGPoint? {
        let rect = frame(for: CGRect(x: 0, y: 0, width: 1, height: 1), in: size)
        guard rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width,
                       y: (point.y - rect.minY) / rect.height)
    }

    /// Zwei Ecken in einen Kasten in Bildkoordinaten.
    ///
    /// Beschnitten statt verworfen: wer über den Rand hinauszieht, meint das Ding bis
    /// zum Rand und nicht „nichts".
    private func normalisedBox(from: CGPoint, to: CGPoint, in size: CGSize) -> CGRect? {
        Self.box(from: from, to: to,
                 picture: Self.frame(for: CGRect(x: 0, y: 0, width: 1, height: 1),
                                     image: image.size, in: size))
    }

    /// Dieselbe Rechnung ohne Ansicht, damit sie prüfbar ist.
    ///
    /// Drei Dinge stecken darin, und jedes wäre ein eigener kleiner Ärger: die Ecken
    /// können in beliebiger Reihenfolge kommen (wer von rechts unten nach links oben
    /// zieht, meint denselben Kasten), sie können neben dem Bild liegen (dann gilt
    /// der Rand, nicht „nichts"), und ein Strich ist kein Kasten.
    static func box(from: CGPoint, to: CGPoint, picture: CGRect) -> CGRect? {
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

    /// Ein aufgezogener Kasten: mit SAM wird daraus die Kante des Dings darin, ohne
    /// SAM bleibt es der Kasten selbst.
    private func circle(_ box: CGRect) async {
        trouble = nil
        guard let segmenter else {
            // Ohne Modell ist der gezogene Kasten die Auswahl. Das ist kein Notbehelf,
            // sondern genau das, was der Nutzer gezeichnet hat.
            picked.append(SegmentedObject(id: UUID(), box: box, mask: nil, bits: [], side: 0))
            return
        }
        working = true
        defer { working = false }
        do {
            guard let object = try await segmenter.object(in: box) else {
                // Der Kasten ist nicht verloren, nur ungenauer: SAM hat nichts
                // gefunden, der Nutzer hat aber etwas gemeint.
                picked.append(SegmentedObject(id: UUID(), box: box, mask: nil, bits: [], side: 0))
                return
            }
            guard !picked.contains(where: { overlaps($0.box, object.box) }) else { return }
            picked.append(object)
        } catch {
            trouble = error.localizedDescription
        }
    }

    /// Ein Tipp: entweder ein schon gewähltes Ding wieder abwählen, oder ein neues
    /// dazunehmen.
    private func tap(_ point: CGPoint) async {
        guard let segmenter else { return }
        working = true
        trouble = nil
        defer { working = false }
        do {
            guard let object = try await segmenter.object(at: point) else {
                // Stillschweigen waere hier das Schlechteste: der Nutzer hat getippt
                // und nichts ist passiert, und er weiss nicht, ob die App ihn gehoert
                // hat oder das Modell nichts gefunden hat.
                trouble = "Da war keine Kante zu finden. Tippe mitten auf das Ding."
                return
            }
            // Zweimal auf dasselbe zu tippen soll es nicht verdoppeln.
            guard !picked.contains(where: { overlaps($0.box, object.box) }) else { return }
            picked.append(object)
        } catch {
            trouble = error.localizedDescription
        }
    }

    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let cut = a.intersection(b)
        guard !cut.isNull else { return false }
        let shared = cut.width * cut.height
        return shared > 0.6 * min(a.width * a.height, b.width * b.height)
    }

    private func frame(for box: CGRect, in size: CGSize) -> CGRect {
        Self.frame(for: box, image: image.size, in: size)
    }

    /// Wohin ein Kasten in 0…1 auf dem eingepassten Bild fällt.
    ///
    /// Von Hand gerechnet und nicht von SwiftUI abgefragt: `aspectRatio(.fit)` lässt
    /// oben und unten — oder links und rechts — einen Rand, den die Geometrie der
    /// umgebenden Ansicht nicht kennt. Ohne diese Rechnung liegen alle Rahmen um
    /// denselben Betrag daneben, und zwar gleichmäßig genug, dass es aussieht, als
    /// stimme die Erkennung nicht statt die Rechnung.
    ///
    /// Statisch, damit sie prüfbar ist: ein Screenshot zeigt, dass Rahmen irgendwo
    /// liegen, nicht dass sie richtig liegen.
    static func frame(for box: CGRect, image: CGSize, in size: CGSize) -> CGRect {
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

    /// Was der Knopf kostet, bevor er gedrückt wird, und woran die Kante gefunden wird.
    ///
    /// Jeder Ausschnitt ist eine eigene Aufnahme und damit ein eigener bezahlter
    /// Aufruf. Das gehört sichtbar daneben und nicht in eine Abrechnung hinterher.
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
            return "Keine einzelnen Gegenstände erkannt — das ganze Bild geht als eine "
                 + "Aufnahme. Mit dem Erkennungsmodell aus den Einstellungen ginge das besser."
        }
        return chosenOffers.isEmpty && picked.isEmpty
            ? "Nichts gewählt: das ganze Bild geht als eine Aufnahme. Einen Kasten "
            + "ziehen geht auch."
            : "\(count) Ausschnitt\(count == 1 ? "" : "e") — so viele Aufnahmen."
    }

    private func take() {
        // Mit SAM wird freigestellt, nicht nur geschnitten: der Gegenstand bleibt, der
        // Rest wird weiss. Ohne SAM gibt es keinen Umriss, nur einen Kasten — dort
        // bleibt es beim Ausschnitt.
        // Mit Umriss wird freigestellt, ohne bleibt es beim Kasten — das trifft die
        // Rahmen aus dem Rückfallmodus und die von Hand gezogenen, bei denen SAM
        // nichts gefunden hat.
        let fromPicked = picked.compactMap { object in
            object.bits.isEmpty
                ? ObjectFinder.crop(image, to: object.box)
                : ObjectFinder.cutOut(image, object: object)
        }
        let fromOffers = usingSam ? [] : offered
            .filter { chosenOffers.contains($0.id) }
            .compactMap { ObjectFinder.crop(image, to: $0.box) }
        let pieces = fromPicked + fromOffers

        // Nichts angetippt, oder kein Ausschnitt brauchbar: dann eben das ganze Bild.
        // Mit leeren Händen aus diesem Bildschirm zu gehen wäre der falsche Ausgang —
        // das Foto ist gemacht, und es soll irgendwo landen.
        let images = pieces.isEmpty ? [image] : pieces
        model.enqueue(images, placeID: placeID)
        onTaken()
    }
}
