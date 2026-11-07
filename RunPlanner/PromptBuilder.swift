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
                    var s = [seg.label, seg.summary].compactMap(\.nilIfBlank).joined(separator: " ")
                    if !seg.targetSummary.isEmpty { s += " (\(seg.targetSummary))" }
                    return s
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
        s += guidance + "\n\n"
        s += "After any feedback, give the plan as ONE ```json code block in exactly this format (my app reads it):\n\n"
        s += schema
        return s
    }

    /// How to write each run so I can follow it on the day without looking anything up.
    static let guidance = """
    ### How to write each run
    I'm not an expert, and my app shows each run on its own screen, so every run must make sense on its own without me doing any research:
    - "purpose": 1-2 sentences on why this run is in the plan and what it builds.
    - "keyPoints": the 2-4 things that matter most today, in plain words (e.g. "Keep heart rate under 145, even if that means walking up hills").
    - "segments": break EVERY run into the blocks I'll actually do, in order: warm-up, main part (reps, strides, drills, steady running…) and cool-down. A steady easy run can be a single block. My app shows each block as a step with its targets.
    - Make targets explicit for every block, as numbers wherever possible:
      - "targetPace" as a range in min/km (e.g. "6:20-6:40 /km"), based on my actual paces above.
      - "targetHeartRate" as a bpm range (e.g. "130-145 bpm"), with the zone if useful. Work it out from my watch heart-rate data. If you can't be sure, say it's an estimate in the plan's "coachNotes".
      - "targetEffort" as RPE out of 10 plus a feel (e.g. "RPE 3/10, can chat in full sentences").
      - For repeats, give "repeats", the length of each rep ("durationMin" or "distanceKm") and a "recoveryStep" for what happens between reps.
    - "instructions": how to do the block: form cues, what it should feel like, when to back off.
    - "glossary": explain every running term you use (e.g. strides, tempo, RPE, Zone 2, fartlek, cadence, negative split) in 1-2 plain sentences, once for the whole block. Use the term exactly as written in the runs, because my app matches it to show the explanation on each run.

    ### Apple Watch
    My app sends each run to my Apple Watch as a custom workout, so don't include Watch setup tips. Each segment becomes one Watch block:
    - A first segment with "kind": "warmup" becomes the Watch warm-up, and a last segment with "kind": "cooldown" becomes the Watch cool-down. "drills" segments before the warm-up stay off the Watch.
    - Every other segment becomes a block of "repeats" × (work step + "recoveryStep"). The work step ends after "distanceKm" or "durationMin"; with neither, I press to move on.
    - Give the alert ranges as numbers only: "alertPace" in min/km (e.g. "5:40-5:50") and "alertHeartRate" in bpm (e.g. "100-145"). Include both where both matter.
    - Set the top of every alert range to the top of the TARGET, not a hard ceiling. If easy runs are "aim under 145, ceiling 150", use "100-145" so the Watch warns me at 145, while there's still room to slow down. The bottom of a heart-rate range only needs to be low enough not to trigger on walk breaks (about 100 for easy running).
    - The Watch can alert on only one per step: heart rate for warm-ups, easy and long running and cool-downs, pace for reps, strides and tempo. Add "watchAlert": "pace" or "heartRate" only to override that.
    - "recoveryStep": { "label", "durationMin" or "distanceKm", "alertHeartRate" (e.g. "100-140", so I know to slow down enough), "instructions" }.
    """

    static let schema = """
    ```json
    {
      "name": "Block 2: 10K build",
      "coachNotes": "What this block focuses on and why (2-4 sentences). Note here if heart-rate targets are estimates.",
      "glossary": [
        { "term": "Zone 2", "meaning": "An easy heart-rate range where you can talk in full sentences. It builds aerobic fitness without tiring you out." },
        { "term": "Strides", "meaning": "Short, smooth accelerations of about 20 s up to roughly mile pace, then a full walk back. They practise good form and leg speed without being hard work." }
      ],
      "runs": [
        {
          "week": 1,
          "title": "Easy run + strides",
          "type": "easy",
          "targetDistanceKm": 5,
          "targetDurationMin": 34,
          "targetPace": "6:20-6:40 /km",
          "targetEffort": "Zone 2, conversational",
          "purpose": "Builds your aerobic base. The strides at the end keep your legs quick without adding fatigue.",
          "keyPoints": ["Stay under 145 bpm, even if you have to slow down", "Strides should feel fast but relaxed, never a sprint"],
          "segments": [
            { "label": "Easy run", "kind": "main", "durationMin": 30, "targetPace": "6:20-6:40 /km", "targetHeartRate": "130-145 bpm (Zone 2)", "targetEffort": "RPE 3/10, can chat", "alertPace": "6:20-6:40", "alertHeartRate": "130-145", "instructions": "Start slower than you think and let the pace come to you." },
            { "label": "Strides", "kind": "strides", "durationMin": 0.33, "repeats": 4, "targetEffort": "RPE 7/10, fast but smooth", "instructions": "Build up over the first 5 s, hold, then ease off. Tall posture, quick light feet.",
              "recoveryStep": { "label": "Walk back", "durationMin": 1, "instructions": "Walk back to the start." } }
          ]
        },
        {
          "week": 1,
          "title": "400 m repeats",
          "type": "intervals",
          "targetDurationMin": 40,
          "purpose": "Teaches your body to run at 5K race pace and improves your top-end speed.",
          "keyPoints": ["Run every rep at the same pace; don't go out too fast", "Stop if your form falls apart"],
          "segments": [
            { "label": "Warm-up", "kind": "warmup", "durationMin": 10, "targetHeartRate": "under 140 bpm", "targetEffort": "RPE 2-3/10", "alertHeartRate": "110-140" },
            { "label": "400 m reps", "kind": "reps", "distanceKm": 0.4, "repeats": 6, "targetPace": "5:00-5:10 /km", "targetHeartRate": "will reach 165-175 bpm by the end of each rep", "targetEffort": "RPE 8/10", "alertPace": "5:00-5:10", "instructions": "Aim for even splits. The last rep should feel hard but doable.",
              "recoveryStep": { "label": "Easy jog", "durationMin": 1.5, "alertHeartRate": "100-140", "instructions": "Jog or walk until your breathing settles." } },
            { "label": "Cool-down", "kind": "cooldown", "durationMin": 10, "targetEffort": "RPE 2/10", "alertHeartRate": "100-140" }
          ]
        }
      ]
    }
    ```
    Rules: "type" is one of easy, long, tempo, intervals, hills, recovery, strides, race, walk-run. Segment "kind" is one of warmup, main, reps, strides, drills, cooldown. Only "title" (run) and "label" (segment) are required; leave out a field rather than guessing it. Numbers must be plain numbers, not strings; times under a minute are fractions of a minute (20 s = 0.33).
    """
}
