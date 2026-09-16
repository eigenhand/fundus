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
                // `apply` leitet das Nachschlagen auf die gewaehlte Sprache um — das
                // ist die Umstellung selbst. Die Locale darunter macht Zahlen und
                // Daten passend und ist zugleich der Anstoss, auf den SwiftUI die
                // Ansichten neu baut.
                .onChange(of: model.settings.language, initial: true) { _, language in
                    AppLanguage.apply(language)
                }
                .environment(\.locale, model.settings.language.locale ?? .autoupdatingCurrent)
                // `nil` heisst: das Geraet entscheidet — und wechselt zur Daemmerung
                // von selbst mit.
                .preferredColorScheme(model.settings.appearance.scheme)
                .onChange(of: phase) { _, new in
                    // Beim Verschwinden sofort schreiben, nicht verzögert: die
                    // verzögerte Speicherung wartet 400 ms, und eine App, die in
                    // dieser Zeit beendet wird, verliert den letzten Eintrag.
                    if new != .active { Task { await model.saveNow() } }
                }
        }
    }
}
