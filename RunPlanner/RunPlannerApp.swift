import SwiftUI

@main
struct RunPlannerApp: App {
    @State private var store = PlanStore()

    var body: some Scene {
        WindowGroup {
            PlanListView()
                .environment(store)
        }
    }
}
