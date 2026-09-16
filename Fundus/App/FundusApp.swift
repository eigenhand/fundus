import SwiftUI

@main
struct FundusApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            InventoryView()
                .environment(model)
                .task { await model.load() }
                .tint(EH.navy)
                // `apply` redirects the lookup to the chosen language — that is the
                // switch itself. The locale below it makes numbers and dates fit and is
                // at the same time the nudge on which SwiftUI rebuilds the views.
                .onChange(of: model.settings.language, initial: true) { _, language in
                    AppLanguage.apply(language)
                }
                .environment(\.locale, model.settings.language.locale ?? .autoupdatingCurrent)
                // `nil` means: the device decides — and switches at dusk by itself.
                .preferredColorScheme(model.settings.appearance.scheme)
                .onChange(of: phase) { _, new in
                    // Write at once when it goes away, not with a delay: the delayed
                    // save waits 400 ms, and an app killed in that time loses the last
                    // entry.
                    if new != .active { Task { await model.saveNow() } }
                }
        }
    }
}
