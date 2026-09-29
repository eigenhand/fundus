import SwiftUI

/// Die wiederkehrenden Kleinteile.

// MARK: - Zeitangaben

/// On the main actor, because `RelativeDateTimeFormatter` is not `Sendable` and these
/// timestamps stand exclusively in views. A `nonisolated(unsafe)` would have calmed the
/// compiler without answering the question of who uses the formatter at the same time.
@MainActor
enum Ago {
    /// "2 days ago". A date like "13.09.2026" asks the reader to do a subtraction; for
    /// a sighting the distance is the whole statement.
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func string(_ date: Date, now: Date = Date()) -> String {
        // Under an hour the formatter says "0 hours ago" — for a sighting you have just
        // made yourself, that reads like a bug.
        if now.timeIntervalSince(date) < 3_600 { return String(localized: "gerade") }
        // Set on every call: the language can change while the app runs.
        formatter.locale = AppLanguage.interfaceLocale
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Reliability

/// The state of a sighting as a dot and a word.
///
/// Colour *and* word, not colour alone: the three grades are a statement about how far
/// an entry can be relied on, and that must not hang on whether somebody can tell green
/// from ochre.
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
        .accessibilityLabel(Text("\(freshness.label), zuletzt gesehen \(Ago.string(item.lastSeenAt))"))
    }
}

// MARK: - Zeile eines Dings

struct ItemRow: View {
    let item: Item
    /// Where the hit came from. `nil` outside the search.
    var kind: ItemSearch.Kind?
    /// The place path, when the list is not already grouped by place.
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
                        // Labelled only for meaning. Writing "name" on a name hit tells
                        // the reader nothing they cannot see; "meaning" tells them the
                        // app has guessed.
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

// MARK: - Section heading

struct SectionLabel: View {
    let text: LocalizedStringKey
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

/// Fully rounded at one line, like the composer in Faden.
///
/// The same radius from the same arithmetic: `composerHeight / 2`. The two apps stand
/// on the same screen, and a field that were boxier here than there would not be a
/// different app but a worse one.
struct SearchField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "Was suchst du?"
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
                .accessibilityLabel(Text("Suche leeren"))
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
            .accessibilityLabel(Text("Meldung schließen"))
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

/// The wordmark, set in the family it was drawn in.
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

/// A round symbol to tap — the shape the header buttons have in Faden.
struct RoundIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
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
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Leerer Zustand

struct EmptyNote: View {
    let label: LocalizedStringKey
    let text: LocalizedStringKey

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
