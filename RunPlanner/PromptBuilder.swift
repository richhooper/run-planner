import Foundation

/// Builds the text you paste into Claude (or any AI) to get your next block of runs.
enum PromptBuilder {
    static func prompt(for data: AppData, recentRuns: [WorkoutSummary]) -> String {
        let isFirstPlan = data.currentPlan == nil && data.history.isEmpty
        var sections: [String] = []

        sections.append(isFirstPlan
            ? "You are my running coach. I use a simple iPhone app that lists my runs in order (no calendar dates, I fit them around my week) and I record every run on my Apple Watch. Please write my first 4-week block of runs."
            : "You are my running coach. I use a simple iPhone app that lists my runs in order (no calendar dates, I fit them around my week) and I record every run on my Apple Watch. Below is my goal, the block you last planned for me, and what I actually did. Please review it and write my next 4-week block.")

        sections.append("## My goal\n" + (data.goal.nilIfBlank ?? "(Not set yet, so ask me.)"))

        var about = data.aboutMe.nilIfBlank.map { $0 + "\n" } ?? ""
        about += "I want to run \(data.runsPerWeek) times per week."
        sections.append("## About me\n" + about)

        if let plan = data.currentPlan {
            sections.append(blockReport(plan))
        }

        if !data.history.isEmpty {
            let lines = data.history.prefix(6).map { "- " + blockSummary($0) }
            sections.append("## Earlier blocks (most recent first)\n" + lines.joined(separator: "\n"))
        }

        let linked = data.linkedWorkoutIDs
        let others = recentRuns.filter { !linked.contains($0.id) }
        if !others.isEmpty {
            let title = isFirstPlan
                ? "## My recent runs from Apple Watch (last 6 weeks)"
                : "## Other runs from Apple Watch in the last 6 weeks (not part of the plan)"
            sections.append(title + "\n" + others.map { "- \(Format.day($0.start)): \(stats($0))" }.joined(separator: "\n"))
        }

        sections.append(request(data, isFirstPlan: isFirstPlan))
        return sections.joined(separator: "\n\n")
    }

    // MARK: Pieces

    private static func blockReport(_ plan: TrainingPlan) -> String {
        var lines = ["## Current block: \(plan.name)"]
        if let notes = plan.coachNotes?.nilIfBlank { lines.append("Your notes for this block: \(notes)") }
        lines.append(blockSummary(plan))
        lines.append("")

        for (i, run) in plan.runs.enumerated() {
            var head = "\(i + 1). "
            if let w = run.week { head += "Week \(w) · " }
            head += run.title
            if let t = run.type { head += " (\(t))" }
            lines.append(head)

            let target = run.targetSummary(includeEffort: true)
            if !target.isEmpty { lines.append("   Planned: \(target)") }
            if let segs = run.segments, !segs.isEmpty {
                lines.append("   Session: " + segs.map { seg in
                    [seg.label, seg.summary, seg.intensity].compactMap { $0?.nilIfBlank }.joined(separator: " ")
                }.joined(separator: "; "))
            }

            switch run.completion {
            case nil:
                lines.append("   Actual: not done yet")
            case let c? where c.skipped:
                lines.append("   Actual: skipped")
            case let c?:
                var actual = "   Actual (\(Format.day(c.date))): " + (c.workout.map(stats) ?? "done, no watch data")
                if let e = c.effort { actual += " · effort \(e)/10" }
                lines.append(actual)
            }
            if let notes = run.completion?.notes?.nilIfBlank { lines.append("   My notes: \(notes)") }
        }
        return lines.joined(separator: "\n")
    }

    private static func blockSummary(_ plan: TrainingPlan) -> String {
        let done = plan.doneRuns.count
        let notDone = plan.runs.count - plan.resolvedCount
        var s = "\(plan.name): \(done) of \(plan.runs.count) runs done"
        if plan.skippedCount > 0 { s += ", \(plan.skippedCount) skipped" }
        if notDone > 0 { s += ", \(notDone) not done yet" }
        let workouts = plan.doneRuns.compactMap { $0.completion?.workout }
        if plan.totalKm > 0 { s += ", \(Format.km(plan.totalKm)) total" }
        let timed = workouts.filter { $0.distanceKm != nil }
        let km = timed.compactMap(\.distanceKm).reduce(0, +)
        if km > 0 { s += ", avg pace \(Format.pace(timed.map(\.durationSec).reduce(0, +) / km))" }
        let hrs = workouts.compactMap(\.avgHeartRate)
        if !hrs.isEmpty { s += ", avg HR \(Int(hrs.reduce(0, +) / Double(hrs.count)))" }
        return s + "."
    }

    private static func stats(_ w: WorkoutSummary) -> String {
        var parts: [String] = []
        if let km = w.distanceKm { parts.append("\(Format.km(km)) in \(Format.duration(w.durationSec))") }
        else { parts.append(Format.duration(w.durationSec)) }
        if let p = w.paceSecPerKm { parts.append(Format.pace(p)) }
        if let avg = w.avgHeartRate {
            parts.append("avg HR \(Int(avg))" + (w.maxHeartRate.map { " / max \(Int($0))" } ?? ""))
        }
        if let up = w.elevationGainM, up >= 1 { parts.append("+\(Int(up)) m climb") }
        if w.indoor == true { parts.append("treadmill") }
        return parts.joined(separator: " · ")
    }

    private static func request(_ data: AppData, isFirstPlan: Bool) -> String {
        var s = "## What I need\n"
        if isFirstPlan {
            s += "If anything important is missing (current weekly running, recent race times, injuries), ask me before writing the plan. "
        } else {
            s += "Start with a short review of how this block went against my goal. Base progression on what I actually did, not just what was planned: consolidate if I missed runs, struggled or my heart rate ran high, and progress if it felt comfortable. "
        }
        s += "Write 4 weeks with \(data.runsPerWeek) runs per week, listed in the order I should do them. Mix easy, long and quality sessions to suit my goal, and keep easy runs genuinely easy.\n\n"
        s += "After any feedback, give the plan as ONE ```json code block in exactly this format (my app reads it):\n\n"
        s += schema
        return s
    }

    static let schema = """
    ```json
    {
      "name": "Block 2: 10K build",
      "coachNotes": "What this block focuses on and why (2-4 sentences).",
      "runs": [
        {
          "week": 1,
          "title": "Easy run",
          "type": "easy",
          "targetDistanceKm": 5,
          "targetDurationMin": 32,
          "targetPace": "6:20-6:40 /km",
          "targetEffort": "Zone 2, conversational",
          "description": "Relaxed and chatty. Finish with 4 x 20 s strides."
        },
        {
          "week": 1,
          "title": "400 m repeats",
          "type": "intervals",
          "targetDurationMin": 40,
          "description": "Warm up well; run the reps fast but controlled.",
          "segments": [
            { "label": "Warm-up jog", "durationMin": 10, "intensity": "easy" },
            { "label": "Fast", "distanceKm": 0.4, "repeats": 6, "intensity": "5K pace, 90 s jog between" },
            { "label": "Cool-down jog", "durationMin": 10, "intensity": "easy" }
          ]
        }
      ]
    }
    ```
    Rules: "type" is one of easy, long, tempo, intervals, hills, recovery, strides, race, walk-run. Only "title" is required; leave out anything that doesn't apply (e.g. no "segments" for steady runs). Numbers must be plain numbers, not strings.
    """
}
