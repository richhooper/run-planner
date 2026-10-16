import SwiftUI

struct CompleteRunSheet: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let run: PlannedRun

    @State private var workouts: [WorkoutSummary] = []
    @State private var selectedID: UUID?
    @State private var loading = true
    @State private var healthError: String?
    @State private var effort = 5
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading {
                        ProgressView()
                    } else if let healthError {
                        Text(healthError).foregroundStyle(.secondary)
                    } else if workouts.isEmpty {
                        Text("No runs found in Apple Health in the last 14 days.").foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { w in
                        Button {
                            selectedID = selectedID == w.id ? nil : w.id
                        } label: {
                            WorkoutPickRow(workout: w,
                                           selected: selectedID == w.id,
                                           alreadyUsed: store.data.linkedWorkoutIDs.contains(w.id))
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Apple Watch run")
                } footer: {
                    Text("Pick the workout that matches this run, or leave it blank. If none show up, allow access in Settings › Health › Data Access & Devices › Run Planner.")
                }

                Section("How did it feel?") {
                    Stepper(value: $effort, in: 1...10) {
                        HStack {
                            Text("Effort")
                            Spacer()
                            Text("\(effort)/10 · \(Effort.label(effort))").foregroundStyle(.secondary)
                        }
                    }
                    TextField("Notes: legs, weather, how it went…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(run.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: save).bold() }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            workouts = try await HealthService.shared.recentRuns(days: 14)
            // Preselect the latest run from the last 2 days that isn't already attached to another run.
            let used = store.data.linkedWorkoutIDs
            let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
            selectedID = workouts.first { !used.contains($0.id) && $0.start > cutoff }?.id
        } catch {
            healthError = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
        loading = false
    }

    private func save() {
        let workout = workouts.first { $0.id == selectedID }
        store.setCompletion(
            Completion(date: workout?.start ?? .now, effort: effort, notes: notes.nilIfBlank, workout: workout),
            for: run.id
        )
        dismiss()
    }
}

private struct WorkoutPickRow: View {
    let workout: WorkoutSummary
    let selected: Bool
    let alreadyUsed: Bool

    var body: some View {
        HStack {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                    .font(.subheadline.bold())
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
                if alreadyUsed {
                    Text("Already attached to another run").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var summary: String {
        [workout.distanceKm.map(Format.km),
         Format.duration(workout.durationSec),
         workout.paceSecPerKm.map(Format.pace),
         workout.avgHeartRate.map { "\(Int($0)) bpm" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
