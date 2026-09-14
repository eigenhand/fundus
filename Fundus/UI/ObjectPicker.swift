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
            .contentShape(Rectangle())
            // Der Fingertipp ist die Frage. Nur mit SAM — ohne es gibt es nichts zu
            // fragen, da stehen die Antworten schon als Rahmen da.
            .onTapGesture { location in
                guard usingSam, !preparing, !working else { return }
                let rect = frame(for: CGRect(x: 0, y: 0, width: 1, height: 1), in: geo.size)
                guard rect.contains(location) else { return }
                let point = CGPoint(x: (location.x - rect.minX) / rect.width,
                                    y: (location.y - rect.minY) / rect.height)
                Task { await tap(point) }
            }
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

    /// Ein Tipp: entweder ein schon gewähltes Ding wieder abwählen, oder ein neues
    /// dazunehmen.
    private func tap(_ point: CGPoint) async {
        if let hit = picked.first(where: { $0.box.contains(point) }) {
            picked.removeAll { $0.id == hit.id }
            trouble = nil
            return
        }
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

    private var count: Int { usingSam ? picked.count : chosenOffers.count }

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
            if picked.isEmpty { return "Tippe an, was du meinst — oder nimm das ganze Bild." }
            return picked.count == 1
                ? "Ein Ausschnitt, eine Aufnahme. Weitere antippen geht."
                : "\(picked.count) Ausschnitte, \(picked.count) Aufnahmen."
        }
        if offered.isEmpty {
            return "Keine einzelnen Gegenstände erkannt — das ganze Bild geht als eine "
                 + "Aufnahme. Mit dem Erkennungsmodell aus den Einstellungen ginge das besser."
        }
        return chosenOffers.isEmpty
            ? "Nichts angetippt: das ganze Bild geht als eine Aufnahme."
            : "\(chosenOffers.count) Ausschnitt\(chosenOffers.count == 1 ? "" : "e") — so viele Aufnahmen."
    }

    private func take() {
        // Mit SAM wird freigestellt, nicht nur geschnitten: der Gegenstand bleibt, der
        // Rest wird weiss. Ohne SAM gibt es keinen Umriss, nur einen Kasten — dort
        // bleibt es beim Ausschnitt.
        let pieces = usingSam
            ? picked.compactMap { ObjectFinder.cutOut(image, object: $0) }
            : offered.filter { chosenOffers.contains($0.id) }
                     .compactMap { ObjectFinder.crop(image, to: $0.box) }

        // Nichts angetippt, oder kein Ausschnitt brauchbar: dann eben das ganze Bild.
        // Mit leeren Händen aus diesem Bildschirm zu gehen wäre der falsche Ausgang —
        // das Foto ist gemacht, und es soll irgendwo landen.
        let images = pieces.isEmpty ? [image] : pieces
        model.enqueue(images, placeID: placeID)
        onTaken()
    }
}
