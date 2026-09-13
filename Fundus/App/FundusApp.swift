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
                .onChange(of: phase) { _, new in
                    // Beim Verschwinden sofort schreiben, nicht verzögert: die
                    // verzögerte Speicherung wartet 400 ms, und eine App, die in
                    // dieser Zeit beendet wird, verliert den letzten Eintrag.
                    if new != .active { Task { await model.saveNow() } }
                }
        }
    }
}
