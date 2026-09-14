import SwiftUI

/// Das stehende Bild mit den erkannten Gegenständen, zum Antippen.
///
/// Der Grund, warum das mehr ist als Bequemlichkeit: ein Ausschnitt liest sich besser
/// als ein Regal. Schickt man dem Modell ein breites Brett mit zwölf Dingen, zählt es
/// zwölf Dinge und beschreibt jedes halb. Schickt man ihm einen Motor, liest es den
/// Aufdruck. Wer hier drei Gegenstände antippt, bekommt drei Aufnahmen statt einer —
/// und drei brauchbare Einträge statt einer Sammelzeile.
///
/// Vorgewählt ist der Gegenstand in der Mitte. Das ist der häufigste Fall: man hält
/// etwas in der Hand und zielt darauf. Wer etwas anderes meint, tippt es an; wer
/// mehrere meint, tippt mehrere an.
struct ObjectPicker: View {
    @Environment(AppModel.self) private var model

    let image: UIImage
    let placeID: UUID?
    /// Zurück zum Sucher, ohne etwas einzureihen.
    let onDiscard: () -> Void
    /// Eingereiht. Der Sucher macht danach weiter.
    let onTaken: () -> Void

    @State private var objects: [FoundObject] = []
    @State private var chosen: Set<Int> = []
    @State private var searching = true

    var body: some View {
        VStack(spacing: 0) {
            picture
            bar
        }
        .task {
            objects = await ObjectFinder.find(in: image)
            // Die Mitte vorwählen, nicht alles: wer zielt, meint eins.
            if let middle = objects.min(by: { $0.distanceFromCentre < $1.distanceFromCentre }) {
                chosen = [middle.id]
            }
            searching = false
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

                ForEach(objects) { object in
                    let rect = frame(for: object.box, in: geo.size)
                    outline(object)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if searching {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Gegenstände suchen …")
                            .font(EH.meta)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.5)))
                }
            }
        }
    }

    private func outline(_ object: FoundObject) -> some View {
        let picked = chosen.contains(object.id)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(picked ? Color.white.opacity(0.16) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(picked ? .white : .white.opacity(0.65),
                                  lineWidth: picked ? 3 : 1.5))
            .overlay(alignment: .topTrailing) {
                if picked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.white, EH.navy)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if picked { chosen.remove(object.id) } else { chosen.insert(object.id) }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(picked ? "Gewählt" : "Gegenstand")
    }

    private func frame(for box: CGRect, in size: CGSize) -> CGRect {
        Self.frame(for: box, image: image.size, in: size)
    }

    /// Wohin ein Kasten in 0…1 auf dem eingepassten Bild fällt.
    ///
    /// Von Hand gerechnet und nicht von SwiftUI abgefragt: `aspectRatio(.fit)` lässt
    /// oben und unten — oder links und rechts — einen Rand, den die Geometrie der
    /// umgebenden Ansicht nicht kennt. Ohne diese Rechnung liegen alle Rahmen um
    /// denselben Betrag daneben, und zwar gleichmässig genug, dass es aussieht, als
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
                .disabled(searching)
            }
        }
        .padding(.horizontal, EH.gutter)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.black.opacity(0.4))
    }

    private var takeLabel: String {
        switch chosen.count {
        case 0: return "Ganzes Bild"
        case 1: return "1 Ausschnitt"
        case let n: return "\(n) Ausschnitte"
        }
    }

    /// Was der Knopf kostet, bevor er gedrückt wird.
    ///
    /// Jeder Ausschnitt ist eine eigene Aufnahme und damit ein eigener bezahlter
    /// Aufruf. Das gehört sichtbar daneben und nicht in eine Abrechnung hinterher.
    private var note: String {
        if searching { return "Das Gerät sieht sich das Bild an." }
        if objects.isEmpty {
            return "Keine einzelnen Gegenstände erkannt — das ganze Bild geht als eine Aufnahme."
        }
        if chosen.isEmpty { return "Nichts angetippt: das ganze Bild geht als eine Aufnahme." }
        return chosen.count == 1
            ? "Ein Ausschnitt, eine Aufnahme."
            : "\(chosen.count) Ausschnitte, \(chosen.count) Aufnahmen."
    }

    private func take() {
        let pieces = objects
            .filter { chosen.contains($0.id) }
            .compactMap { ObjectFinder.crop(image, to: $0.box) }

        // Nichts angetippt, oder kein Ausschnitt brauchbar: dann eben das ganze Bild.
        // Mit leeren Händen aus diesem Bildschirm zu gehen wäre der falsche Ausgang —
        // das Foto ist gemacht, und es soll irgendwo landen.
        let images = pieces.isEmpty ? [image] : pieces
        model.enqueue(images, placeID: placeID)
        onTaken()
    }
}
