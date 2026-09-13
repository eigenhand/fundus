import SwiftUI

/// Die wiederkehrenden Kleinteile.

// MARK: - Zeitangaben

/// Auf dem Hauptakteur, weil `RelativeDateTimeFormatter` nicht `Sendable` ist und
/// diese Zeitangaben ausschließlich in Ansichten stehen. Ein
/// `nonisolated(unsafe)` hätte den Compiler beruhigt, ohne die Frage zu
/// beantworten, wer den Formatierer gleichzeitig benutzt.
@MainActor
enum Ago {
    /// „vor 2 Tagen“. Ein Datum wie „13.09.2026“ verlangt vom Leser eine
    /// Subtraktion; bei einer Sichtung ist der Abstand die ganze Aussage.
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .full
        return f
    }()

    static func string(_ date: Date, now: Date = Date()) -> String {
        // Unter einer Stunde sagt der Formatierer „vor 0 Stunden“ — für eine
        // Sichtung, die man gerade selbst gemacht hat, liest sich das wie ein Fehler.
        if now.timeIntervalSince(date) < 3_600 { return "gerade" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Verlässlichkeit

/// Der Zustand einer Sichtung als Punkt und Wort.
///
/// Farbe *und* Wort, nicht nur Farbe: die drei Stufen sind eine Aussage über die
/// Verlässlichkeit eines Eintrags, und die darf nicht daran hängen, ob jemand
/// Grün von Ocker unterscheiden kann.
struct FreshnessMark: View {
    let item: Item
    var showDate = true

    private var freshness: Freshness { Freshness.of(item) }

    private var color: Color {
        switch freshness {
        case .seen:    return EH.good
        case .assumed: return EH.warn
        case .stale:   return EH.bad
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(showDate ? "\(freshness.label) · \(Ago.string(item.lastSeenAt))" : freshness.label)
                .font(EH.meta)
                .foregroundStyle(freshness == .seen ? EH.muted : color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(freshness.label), zuletzt gesehen \(Ago.string(item.lastSeenAt))")
    }
}

// MARK: - Zeile eines Dings

struct ItemRow: View {
    let item: Item
    /// Woher der Treffer kam. `nil` außerhalb der Suche.
    var kind: ItemSearch.Kind?
    /// Der Ortspfad, wenn die Liste nicht schon nach Ort gruppiert ist.
    var placePath: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(EH.answer)
                    .foregroundStyle(EH.navy)
                    .lineLimit(2)

                if !item.note.isEmpty {
                    Text(item.note)
                        .font(EH.bodySmall)
                        .foregroundStyle(EH.slate)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    FreshnessMark(item: item)
                    if let placePath, !placePath.isEmpty {
                        Text(placePath)
                            .font(EH.meta)
                            .foregroundStyle(EH.muted)
                            .lineLimit(1)
                    }
                    if let kind, kind == .semantic {
                        // Nur bei Bedeutung beschriftet. „Name“ an einen
                        // Namenstreffer zu schreiben sagt dem Leser nichts, was er
                        // nicht sieht; „Bedeutung“ sagt ihm, dass die App geraten hat.
                        Text(kind.label)
                            .font(EH.meta)
                            .foregroundStyle(EH.muted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(EH.hair, lineWidth: EH.hairWidth))
                    }
                }
            }

            Spacer(minLength: 0)

            if let amount = item.amountLabel {
                Text(amount)
                    .font(.eh(15, .callout, weight: .medium))
                    .foregroundStyle(EH.slate)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - Abschnittsüberschrift

struct SectionLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            EH.label(text)
            Rectangle()
                .fill(EH.hair)
                .frame(height: EH.hairWidth)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

// MARK: - Das Suchfeld

/// Halbrund bei einer Zeile, wie die Eingabezeile in Faden.
///
/// Derselbe Radius aus derselben Rechnung: `composerHeight / 2`. Die beiden Apps
/// stehen auf demselben Bildschirm, und ein Feld, das hier kastiger wäre als dort,
/// wäre nicht eine andere App, sondern eine schlechtere.
struct SearchField: View {
    @Binding var text: String
    var placeholder = "Was suchst du?"
    var onChange: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EH.muted)

            TextField(placeholder, text: $text)
                .font(EH.body)
                .foregroundStyle(EH.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onChange(of: text) { _, _ in onChange() }

            if !text.isEmpty {
                Button {
                    text = ""
                    onChange()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(EH.muted)
                }
                .buttonStyle(EHTap())
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: EH.composerHeight)
        .background(
            RoundedRectangle(cornerRadius: EH.radiusField, style: .circular)
                .fill(EH.surface))
        .overlay(
            RoundedRectangle(cornerRadius: EH.radiusField, style: .circular)
                .stroke(focused ? EH.hairStrong : EH.hair,
                        lineWidth: focused ? 2 * EH.hairWidth : EH.hairWidth))
    }
}

// MARK: - Meldung

struct BannerView: View {
    let banner: AppModel.Banner
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(banner.text)
                .font(EH.bodySmall)
                .foregroundStyle(banner.tone == .bad ? EH.bad : EH.slate)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EH.muted)
            }
            .buttonStyle(EHTap())
            .accessibilityLabel("Meldung schließen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous)
                .fill(EH.surfaceSunk))
        .overlay(
            RoundedRectangle(cornerRadius: EH.radiusSmall, style: .continuous)
                .stroke(EH.hair, lineWidth: EH.hairWidth))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Kopfzeile

/// Die Wortmarke, gesetzt in der Familie, in der sie gezeichnet wurde.
struct AppHeader<Trailing: View>: View {
    var title = "Fundus"
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.brand(23))
                    .tracking(0.5)
                    .foregroundStyle(EH.navy)
                if let subtitle {
                    Text(subtitle)
                        .font(EH.meta)
                        .foregroundStyle(EH.muted)
                }
            }
            Spacer()
            trailing
        }
    }
}

/// Ein rundes Symbol zum Antippen — die Form, die in Faden die Knöpfe der Kopfzeile
/// haben.
struct RoundIconButton: View {
    let systemName: String
    let label: String
    var prominent = false
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(prominent ? Color.white : EH.navy)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? EH.navy : EH.surface))
                .overlay(Circle().stroke(prominent ? .clear : EH.hairStrong,
                                         lineWidth: EH.hairWidth))
        }
        .buttonStyle(EHTap())
        .accessibilityLabel(label)
    }
}

// MARK: - Leerer Zustand

struct EmptyNote: View {
    let label: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            BrandRule()
            EH.label(label)
            Text(text)
                .font(EH.body)
                .foregroundStyle(EH.slate)
                .lineSpacing(EH.prose)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
