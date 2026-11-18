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

                if let purpose = run.purpose?.nilIfBlank {
                    Section("Why this run") { Text(purpose) }
                }

                if let points = run.keyPoints?.compactMap(\.nilIfBlank), !points.isEmpty {
                    Section("What matters today") {
                        ForEach(points, id: \.self) { point in
                            Label(point, systemImage: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary, run.color)
                        }
                    }
                }

                if let segments = run.segments, !segments.isEmpty {
                    let layout = run.watchLayout
                    Section {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                            SegmentRow(segment: seg, step: i + 1, run: run, onWatch: layout.isOnWatch(seg))
                        }
                    } header: {
                        Text("Session")
                    } footer: {
                        if store.data.sendToWatch && store.data.currentPlan?.nextRun?.id == run.id {
                            Label("On your Apple Watch now. \(Image(systemName: "bell.fill")) marks the Watch alerts.", systemImage: "applewatch")
                        } else {
                            Text("\(Image(systemName: "bell.fill")) marks what your Apple Watch will alert on.")
                        }
                    }
                }

                if let details = run.details?.nilIfBlank {
                    Section("Coach's notes") { Text(details) }
                }

                if let terms = store.data.currentPlan?.terms(for: run), !terms.isEmpty {
                    Section("Terms explained") {
                        ForEach(terms) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.term).font(.headline)
                                Text(t.meaning).font(.subheadline).foregroundStyle(.secondary)
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

                if let w = run.completion?.workout {
                    if let intervals = w.intervals, !intervals.isEmpty {
                        Section {
                            ForEach(Array(intervals.enumerated()), id: \.offset) { _, stat in IntervalRow(stat: stat) }
                        } header: {
                            Text("Intervals")
                        } footer: {
                            if let note = w.intervalNote { Text(note) }
                        }
                    }
                    if let splits = w.splits, !splits.isEmpty {
                        Section("Km splits") {
                            ForEach(Array(splits.enumerated()), id: \.offset) { _, stat in IntervalRow(stat: stat) }
                        }
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

/// One block of the session, laid out like the Apple Watch workout: the work step with its targets,
/// then the recovery between repeats. A bell marks the target the Watch alerts on.
struct SegmentRow: View {
    let segment: Segment
    let step: Int
    let run: PlannedRun
    let onWatch: Bool

    var body: some View {
        let alert = onWatch ? run.watchAlert(for: segment) : nil
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(segment.color(runColor: run.color))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(step). \(segment.label)").font(.headline)
                    Spacer()
                    Text(segment.summary).font(.headline).monospacedDigit()
                }
                if !onWatch {
                    Label("Before you start · not on Watch", systemImage: "applewatch.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let pace = segment.targetPace?.nilIfBlank ?? segment.paceRange?.text {
                    TargetLine(symbol: "speedometer", label: "Pace", value: pace, isAlert: alert.isPace)
                }
                if let hr = segment.targetHeartRate?.nilIfBlank ?? segment.heartRateRange?.text {
                    TargetLine(symbol: "heart.fill", label: "Heart rate", value: hr, isAlert: alert.isHeartRate)
                }
                if let effort = segment.targetEffort?.nilIfBlank {
                    TargetLine(symbol: "gauge.with.dots.needle.50percent", label: "Effort", value: effort)
                }
                if let alert, !alertShown(alert) {
                    TargetLine(symbol: "applewatch", label: "Watch alert", value: alert.text, isAlert: true)
                }
                if let how = segment.instructions?.nilIfBlank {
                    Text(how).font(.subheadline).foregroundStyle(.secondary)
                }

                if let rec = segment.effectiveRecovery {
                    RecoveryLine(step: rec)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// True when the alert's range is already one of the target lines shown above.
    private func alertShown(_ alert: WatchAlert) -> Bool {
        switch alert {
        case .pace: segment.targetPace?.nilIfBlank != nil || segment.paceRange != nil
        case .heartRate: segment.targetHeartRate?.nilIfBlank != nil || segment.heartRateRange != nil
        }
    }
}

/// The recovery step between repeats, indented under its block.
private struct RecoveryLine: View {
    let step: WatchStep

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label("Between reps: \(step.label ?? "Recovery")", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.bold())
                Spacer()
                Text(step.summary).font(.subheadline.bold()).monospacedDigit()
            }
            if let hr = step.heartRateRange {
                TargetLine(symbol: "heart.fill", label: "Heart rate", value: hr.text, isAlert: step.alert.isHeartRate)
            }
            if let pace = step.paceRange {
                TargetLine(symbol: "speedometer", label: "Pace", value: pace.text, isAlert: step.alert.isPace)
            }
            if let how = step.instructions?.nilIfBlank {
                Text(how).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TargetLine: View {
    let symbol: String
    let label: String
    let value: String
    var isAlert = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
            if isAlert {
                Image(systemName: "bell.fill").foregroundStyle(.orange).accessibilityLabel("Apple Watch alert")
            }
        }
        .font(.subheadline)
    }
}

private extension Optional where Wrapped == WatchAlert {
    var isPace: Bool { if case .pace? = self { true } else { false } }
    var isHeartRate: Bool { if case .heartRate? = self { true } else { false } }
}

/// One Watch step or km split: what you did, with the planned target underneath.
private struct IntervalRow: View {
    let stat: IntervalStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.label).font(stat.purpose == "work" ? .subheadline.bold() : .subheadline)
                Spacer()
                if let p = stat.paceSecPerKm { Text(Format.pace(p)).font(.subheadline.bold()).monospacedDigit() }
            }
            Text(details).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let target = stat.target {
                Text("Target: \(target)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, stat.purpose == "recovery" ? 16 : 0)
    }

    private var details: String {
        var parts = [Format.duration(stat.durationSec)]
        if let km = stat.distanceKm { parts.append(km < 1 ? "\(Int((km * 1000).rounded())) m" : Format.km(km)) }
        if let avg = stat.avgHeartRate {
            parts.append("HR \(Int(avg))" + (stat.maxHeartRate.map { " / \(Int($0)) max" } ?? ""))
        }
        return parts.joined(separator: " · ")
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
