import SwiftUI

struct RunDetailView: View {
    @Environment(PlanStore.self) private var store
    let runID: UUID

    @State private var showComplete = false
    @State private var showSkip = false
    @State private var skipReason = ""

    var body: some View {
        if let run = store.run(runID) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label((run.type ?? "run").capitalized, systemImage: run.symbol)
                            .font(.subheadline.bold())
                            .foregroundStyle(run.color)
                        Text(run.title).font(.largeTitle.bold())
                        let target = run.targetSummary()
                        if !target.isEmpty {
                            Text(target).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if let effort = run.targetEffort {
                        LabeledContent("Effort", value: effort)
                    }
                }

                if let details = run.details?.nilIfBlank {
                    Section("How to run it") { Text(details) }
                }

                if let segments = run.segments, !segments.isEmpty {
                    Section("Session") {
                        ForEach(segments) { seg in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(seg.label).font(.headline)
                                    Spacer()
                                    Text(seg.summary).monospacedDigit()
                                }
                                if let intensity = seg.intensity {
                                    Text(intensity).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let c = run.completion {
                    Section(c.skipped ? "Skipped" : "Completed") {
                        LabeledContent("Date", value: Format.day(c.date))
                        if let w = c.workout { WorkoutStats(workout: w) }
                        if let e = c.effort { LabeledContent("Effort", value: "\(e)/10 · \(Effort.label(e))") }
                        if let notes = c.notes { Text(notes).foregroundStyle(.secondary) }
                        Button("Undo", role: .destructive) { store.setCompletion(nil, for: runID) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if run.completion == nil {
                    HStack(spacing: 12) {
                        Button("Skip") { showSkip = true }
                            .buttonStyle(.bordered)
                        Button {
                            showComplete = true
                        } label: {
                            Label("Mark complete", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showComplete) {
                CompleteRunSheet(run: run).environment(store)
            }
            .alert("Skip this run?", isPresented: $showSkip) {
                TextField("Why? (optional)", text: $skipReason)
                Button("Skip run") {
                    store.setCompletion(Completion(date: .now, skipped: true, notes: skipReason.nilIfBlank), for: runID)
                    skipReason = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The reason is passed on to your AI coach.")
            }
        } else {
            ContentUnavailableView("Run not found", systemImage: "questionmark.circle")
        }
    }
}

struct WorkoutStats: View {
    let workout: WorkoutSummary

    var body: some View {
        if let km = workout.distanceKm { LabeledContent("Distance", value: Format.km(km)) }
        LabeledContent("Time", value: Format.duration(workout.durationSec))
        if let p = workout.paceSecPerKm { LabeledContent("Pace", value: Format.pace(p)) }
        if let hr = workout.avgHeartRate { LabeledContent("Avg heart rate", value: "\(Int(hr)) bpm") }
        if let hr = workout.maxHeartRate { LabeledContent("Max heart rate", value: "\(Int(hr)) bpm") }
        if let up = workout.elevationGainM { LabeledContent("Elevation gain", value: "\(Int(up)) m") }
        if let kcal = workout.activeKcal { LabeledContent("Active energy", value: "\(Int(kcal)) kcal") }
    }
}
