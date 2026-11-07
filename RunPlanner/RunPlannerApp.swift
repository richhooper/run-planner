import SwiftUI

@main
struct RunPlannerApp: App {
    @State private var store = PlanStore()
    @State private var watchSync = WatchSync()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PlanListView()
                .environment(store)
                .environment(watchSync)
                // Re-sync the Watch when the app opens, the next run changes or the setting flips.
                .task(id: watchSyncKey) {
                    guard scenePhase == .active else { return }
                    await watchSync.sync(store.data)
                }
        }
    }

    private var watchSyncKey: String {
        let next = store.data.currentPlan?.nextRun?.id.uuidString ?? "none"
        return "\(store.data.sendToWatch)|\(next)|\(scenePhase == .active)"
    }
}
