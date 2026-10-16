import SwiftUI

struct SettingsView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Run a sub-25 min 5K by March", text: $store.data.goal, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Goal")
                }

                Section {
                    TextField("Age, current running, recent times, injuries, max time for a long run…",
                              text: $store.data.aboutMe, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("About me")
                } footer: {
                    Text("Your goal and these notes go into every AI prompt.")
                }

                Section("Plan shape") {
                    Stepper("\(store.data.runsPerWeek) runs per week", value: $store.data.runsPerWeek, in: 1...7)
                }

                if !store.data.history.isEmpty {
                    Section("Previous blocks") {
                        ForEach(store.data.history) { plan in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.name).font(.headline)
                                Text("\(plan.doneRuns.count)/\(plan.runs.count) runs · \(Format.km(plan.totalKm)) · \(plan.importedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    ShareLink("Export all data (JSON)", item: store.backupJSON)
                } footer: {
                    Text("Everything is stored on this iPhone only. Save a backup to Files now and then.")
                }
            }
            .navigationTitle("Goal & profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
