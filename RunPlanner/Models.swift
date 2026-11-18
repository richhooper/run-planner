import Foundation

// MARK: - App data (everything the app stores, in one JSON file)

struct AppData: Codable {
    var goal: String = ""
    var aboutMe: String = ""
    var runsPerWeek: Int = 3
    var sendToWatch: Bool = false
    var currentPlan: TrainingPlan?
    var history: [TrainingPlan] = []   // finished blocks, newest first

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        aboutMe = try c.decodeIfPresent(String.self, forKey: .aboutMe) ?? ""
        runsPerWeek = try c.decodeIfPresent(Int.self, forKey: .runsPerWeek) ?? 3
        sendToWatch = try c.decodeIfPresent(Bool.self, forKey: .sendToWatch) ?? false
        currentPlan = try c.decodeIfPresent(TrainingPlan.self, forKey: .currentPlan)
        history = try c.decodeIfPresent([TrainingPlan].self, forKey: .history) ?? []
    }

    /// Apple Health workouts already attached to a planned run.
    var linkedWorkoutIDs: Set<UUID> {
        let plans = (currentPlan.map { [$0] } ?? []) + history
        return Set(plans.flatMap { $0.runs.compactMap { $0.completion?.workout?.id } })
    }
}

// MARK: - Plan (this is also the JSON format the AI returns)

struct TrainingPlan: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var coachNotes: String?
    var glossary: [GlossaryTerm]?
    var runs: [PlannedRun]
    var importedAt: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Training block"
        coachNotes = try c.decodeIfPresent(String.self, forKey: .coachNotes)
        glossary = try c.decodeIfPresent([GlossaryTerm].self, forKey: .glossary)
        runs = try c.decode([PlannedRun].self, forKey: .runs)
        importedAt = (try? c.decodeIfPresent(Date.self, forKey: .importedAt)) ?? .now
    }

    /// Glossary entries whose term is mentioned anywhere in the run.
    func terms(for run: PlannedRun) -> [GlossaryTerm] {
        let text = run.searchableText.lowercased()
        return (glossary ?? []).filter { !$0.term.trimmed.isEmpty && text.contains($0.term.trimmed.lowercased()) }
    }

    var weeks: [Int] { Array(Set(runs.map { $0.week ?? 0 })).sorted() }
    func runsInWeek(_ week: Int) -> [PlannedRun] { runs.filter { ($0.week ?? 0) == week } }
    func number(of run: PlannedRun) -> Int { (runs.firstIndex { $0.id == run.id } ?? 0) + 1 }

    var nextRun: PlannedRun? { runs.first { $0.completion == nil } }
    var isFinished: Bool { nextRun == nil }
    var resolvedCount: Int { runs.filter { $0.completion != nil }.count }
    var doneRuns: [PlannedRun] { runs.filter(\.isDone) }
    var skippedCount: Int { runs.filter(\.isSkipped).count }
    var totalKm: Double { doneRuns.compactMap { $0.completion?.workout?.distanceKm }.reduce(0, +) }
}

struct PlannedRun: Codable, Identifiable, Hashable {
    var id: UUID
    var week: Int?
    var title: String
    var type: String?
    var targetDistanceKm: Double?
    var targetDurationMin: Double?
    var targetPace: String?
    var targetEffort: String?
    var purpose: String?          // why this run is in the plan
    var keyPoints: [String]?      // the few things that matter most today
    var details: String?
    var segments: [Segment]?
    var completion: Completion?

    enum CodingKeys: String, CodingKey {
        case id, week, title, type, targetDistanceKm, targetDurationMin, targetPace, targetEffort
        case purpose, keyPoints
        case details = "description"
        case segments, completion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        week = try c.decodeIfPresent(Int.self, forKey: .week)
        title = try c.decode(String.self, forKey: .title)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        targetDistanceKm = try c.decodeIfPresent(Double.self, forKey: .targetDistanceKm)
        targetDurationMin = try c.decodeIfPresent(Double.self, forKey: .targetDurationMin)
        targetPace = try c.decodeIfPresent(String.self, forKey: .targetPace)
        targetEffort = try c.decodeIfPresent(String.self, forKey: .targetEffort)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose)
        keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        segments = try c.decodeIfPresent([Segment].self, forKey: .segments)
        completion = try c.decodeIfPresent(Completion.self, forKey: .completion)
    }

    var isDone: Bool { completion.map { !$0.skipped } ?? false }
    var isSkipped: Bool { completion?.skipped ?? false }

    func targetSummary(includeEffort: Bool = false) -> String {
        var parts: [String] = []
        if let d = targetDistanceKm { parts.append("\(Format.number(d)) km") }
        if let m = targetDurationMin { parts.append("\(Format.number(m)) min") }
        if let p = targetPace { parts.append(p) }
        if includeEffort, let e = targetEffort { parts.append(e) }
        return parts.joined(separator: " · ")
    }

    var searchableText: String {
        var parts = [title, type, targetPace, targetEffort, purpose, details].compactMap { $0 }
        parts += keyPoints ?? []
        for seg in segments ?? [] {
            parts += [seg.label, seg.kind, seg.targetPace, seg.targetHeartRate, seg.targetEffort, seg.recovery, seg.instructions]
                .compactMap { $0 }
        }
        return parts.joined(separator: " ")
    }
}

/// One block of a run, e.g. "Warm-up", "Strides" or "6 × 400 m".
struct Segment: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var kind: String?             // warmup, main, reps, strides, drills, recovery, cooldown
    var durationMin: Double?
    var distanceKm: Double?
    var repeats: Int?
    var targetPace: String?
    var targetHeartRate: String?
    var targetEffort: String?
    var recovery: String?         // what to do between repeats (text)
    var instructions: String?
    // Apple Watch: alert ranges, which one to use, and the recovery step between repeats
    var alertPace: String?        // "5:40-5:50" min/km
    var alertHeartRate: String?   // "120-150" bpm
    var watchAlert: String?       // "pace" or "heartRate" to override the default
    var recoveryStep: WatchStep?

    enum CodingKeys: String, CodingKey {
        case label, kind, durationMin, distanceKm, repeats
        case targetPace, targetHeartRate, targetEffort, recovery, instructions
        case alertPace, alertHeartRate, watchAlert, recoveryStep
    }

    /// Older plans stored a single free-text "intensity".
    private enum LegacyKeys: String, CodingKey { case intensity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        durationMin = try c.decodeIfPresent(Double.self, forKey: .durationMin)
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        repeats = try c.decodeIfPresent(Int.self, forKey: .repeats)
        targetPace = try c.decodeIfPresent(String.self, forKey: .targetPace)
        targetHeartRate = try c.decodeIfPresent(String.self, forKey: .targetHeartRate)
        targetEffort = try c.decodeIfPresent(String.self, forKey: .targetEffort)
            ?? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(String.self, forKey: .intensity)
        recovery = try c.decodeIfPresent(String.self, forKey: .recovery)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        alertPace = try c.decodeIfPresent(String.self, forKey: .alertPace)
        alertHeartRate = try c.decodeIfPresent(String.self, forKey: .alertHeartRate)
        watchAlert = try c.decodeIfPresent(String.self, forKey: .watchAlert)
        recoveryStep = try c.decodeIfPresent(WatchStep.self, forKey: .recoveryStep)
    }

    /// `kind`, or a guess from the label for plans written before it existed.
    var resolvedKind: String {
        if let k = kind?.nilIfBlank { return k.lowercased() }
        let l = label.lowercased()
        if l.contains("warm") { return "warmup" }
        if l.contains("cool") { return "cooldown" }
        if l.contains("stride") { return "strides" }
        if l.contains("drill") { return "drills" }
        return (repeats ?? 1) > 1 ? "reps" : "main"
    }

    // Older plans put ranges in the effort text, so look there last.
    var paceRange: PaceRange? { PaceRange(alertPace) ?? PaceRange(targetPace) ?? PaceRange(targetEffort) }
    var heartRateRange: HeartRateRange? {
        HeartRateRange(alertHeartRate) ?? HeartRateRange(targetHeartRate) ?? HeartRateRange(targetEffort)
    }

    /// The step between repeats: `recoveryStep`, or one read from the older `recovery` text.
    var effectiveRecovery: WatchStep? {
        guard (repeats ?? 1) > 1 else { return nil }
        if var step = recoveryStep {
            if step.instructions == nil { step.instructions = recovery?.nilIfBlank }
            return step
        }
        guard let text = recovery?.nilIfBlank else { return nil }
        return WatchStep(durationMin: Self.minutes(in: text), instructions: text)
    }

    /// "90 s" → 1.5, "2 min" → 2.
    static func minutes(in text: String) -> Double? {
        let t = text.lowercased()
        if let m = t.firstMatch(of: #/(\d+(?:\.\d+)?)\s*(?:s|secs?|seconds?)\b/#), let v = Double(m.1) { return v / 60 }
        if let m = t.firstMatch(of: #/(\d+(?:\.\d+)?)\s*min/#), let v = Double(m.1) { return v }
        return nil
    }

    /// Targets in one line, for the AI prompt.
    var targetSummary: String {
        [targetPace, targetHeartRate, targetEffort].compactMap { $0?.nilIfBlank }.joined(separator: ", ")
    }

    var summary: String {
        var parts: [String] = []
        if let d = distanceKm { parts.append(d < 1 ? "\(Int((d * 1000).rounded())) m" : "\(Format.number(d)) km") }
        if let m = durationMin { parts.append(m < 1 ? "\(Int((m * 60).rounded())) s" : "\(Format.number(m)) min") }
        let base = parts.joined(separator: " / ")
        if let r = repeats, r > 1 { return base.isEmpty ? "\(r) ×" : "\(r) × \(base)" }
        return base
    }
}

/// A single Watch step, used for the recovery between repeats.
struct WatchStep: Codable, Hashable {
    var label: String?
    var durationMin: Double?
    var distanceKm: Double?
    var alertPace: String?
    var alertHeartRate: String?
    var instructions: String?

    var paceRange: PaceRange? { PaceRange(alertPace) }
    var heartRateRange: HeartRateRange? { HeartRateRange(alertHeartRate) }
    /// Recoveries are easy running, so heart rate comes first.
    var alert: WatchAlert? { heartRateRange.map(WatchAlert.heartRate) ?? paceRange.map(WatchAlert.pace) }

    var summary: String {
        if let d = distanceKm { return d < 1 ? "\(Int((d * 1000).rounded())) m" : "\(Format.number(d)) km" }
        if let m = durationMin { return m < 1 ? "\(Int((m * 60).rounded())) s" : "\(Format.number(m)) min" }
        return "until you press"
    }
}

/// Pace range in seconds per km, read from text like "5:40-5:50 /km".
struct PaceRange: Hashable {
    var fastSec: Int
    var slowSec: Int

    init?(_ text: String?) {
        guard let text, let m = text.firstMatch(of: #/(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})/#),
              let a = Int(m.1), let b = Int(m.2), let c = Int(m.3), let d = Int(m.4) else { return nil }
        let x = a * 60 + b, y = c * 60 + d
        guard x > 0, y > 0 else { return nil }
        fastSec = min(x, y)
        slowSec = max(x, y)
    }

    var text: String { "\(Format.pace(Double(fastSec)).dropLast(4))-\(Format.pace(Double(slowSec)))" }
}

/// Heart-rate range in bpm, read from text like "130-150 bpm".
struct HeartRateRange: Hashable {
    var low: Int
    var high: Int

    init?(_ text: String?) {
        guard let text, let m = text.firstMatch(of: #/(\d{2,3})\s*[-–]\s*(\d{2,3})/#),
              let a = Int(m.1), let b = Int(m.2), min(a, b) >= 40, max(a, b) <= 230 else { return nil }
        low = min(a, b)
        high = max(a, b)
    }

    var text: String { "\(low)-\(high) bpm" }
}

enum WatchAlert: Hashable {
    case pace(PaceRange)
    case heartRate(HeartRateRange)

    var text: String {
        switch self {
        case .pace(let p): "Pace \(p.text)"
        case .heartRate(let h): "Heart rate \(h.text)"
        }
    }
}

/// How a run maps onto an Apple Watch custom workout.
struct WatchLayout {
    var beforeStart: [Segment] = []   // drills done before pressing start
    var warmup: Segment?
    var blocks: [Segment] = []
    var cooldown: Segment?

    func isOnWatch(_ seg: Segment) -> Bool { !beforeStart.contains { $0.id == seg.id } }
}

extension PlannedRun {
    var watchLayout: WatchLayout {
        var layout = WatchLayout()
        var segs = segments ?? []
        while let first = segs.first, first.resolvedKind == "drills" { layout.beforeStart.append(segs.removeFirst()) }
        if let first = segs.first, first.resolvedKind == "warmup" { layout.warmup = segs.removeFirst() }
        if let last = segs.last, last.resolvedKind == "cooldown" { layout.cooldown = segs.removeLast() }
        layout.blocks = segs
        return layout
    }

    /// Every step the Watch will run, in order. Mirrors `WatchWorkout.workout(for:in:)`.
    var expectedWatchSteps: [ExpectedStep] {
        let layout = watchLayout
        var steps: [ExpectedStep] = []
        func target(_ seg: Segment) -> String? {
            watchAlert(for: seg)?.text ?? seg.targetSummary.nilIfBlank
        }
        func step(_ seg: Segment, _ purpose: String, label: String? = nil) -> ExpectedStep {
            ExpectedStep(label: label ?? seg.label, purpose: purpose, target: target(seg),
                         distanceKm: seg.distanceKm, durationMin: seg.durationMin)
        }

        if layout.blocks.isEmpty, layout.warmup == nil {
            steps.append(ExpectedStep(label: title, purpose: "work", target: targetSummary(includeEffort: true).nilIfBlank,
                                      distanceKm: targetDistanceKm, durationMin: targetDurationMin))
        } else if layout.blocks.isEmpty, let w = layout.warmup {
            steps.append(step(w, "work"))   // a workout needs at least one block
        } else {
            if let w = layout.warmup { steps.append(step(w, "warmup")) }
            for seg in layout.blocks {
                let reps = max(seg.repeats ?? 1, 1)
                let rec = seg.effectiveRecovery
                for i in 1...reps {
                    steps.append(step(seg, "work", label: reps > 1 ? "\(seg.label) \(i)/\(reps)" : seg.label))
                    if let rec {
                        steps.append(ExpectedStep(label: "\(rec.label ?? "Recovery") \(i)/\(reps)", purpose: "recovery",
                                                  target: rec.alert?.text, distanceKm: rec.distanceKm, durationMin: rec.durationMin))
                    }
                }
            }
        }
        if let c = layout.cooldown { steps.append(step(c, "cooldown")) }
        return steps
    }

    /// Steady runs get km splits instead of (or as well as) intervals.
    var wantsSplits: Bool {
        ["easy", "long", "recovery", "walk-run"].contains((type ?? "easy").lowercased())
            || expectedWatchSteps.filter { $0.purpose == "work" }.count <= 1
    }

    /// The one alert the Watch will use for this segment: pace for hard work, heart rate for easy running.
    func watchAlert(for seg: Segment) -> WatchAlert? {
        let pace = seg.paceRange.map(WatchAlert.pace)
        let hr = seg.heartRateRange.map(WatchAlert.heartRate)
        switch seg.watchAlert?.lowercased() {
        case "pace": return pace ?? hr
        case "heartrate", "heart rate", "hr": return hr ?? pace
        default: break
        }
        let hardRun = ["tempo", "intervals", "hills", "race"].contains((type ?? "").lowercased())
        let kind = seg.resolvedKind
        let prefersPace = kind == "reps" || kind == "strides" || (kind == "main" && hardRun)
        return prefersPace ? (pace ?? hr) : (hr ?? pace)
    }
}

struct GlossaryTerm: Codable, Hashable, Identifiable {
    var term: String
    var meaning: String
    var id: String { term }
}

// MARK: - Completion

struct Completion: Codable, Hashable {
    var date: Date
    var skipped: Bool = false
    var effort: Int?          // 1–10 RPE
    var notes: String?
    var workout: WorkoutSummary?
}

/// A snapshot of an Apple Health running workout, stored so the AI prompt works offline.
struct WorkoutSummary: Codable, Hashable, Identifiable {
    var id: UUID              // HKWorkout uuid
    var start: Date
    var durationSec: Double
    var distanceKm: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var activeKcal: Double?
    var elevationGainM: Double?
    var indoor: Bool?
    var intervals: [IntervalStat]?    // one per Watch step
    var splits: [IntervalStat]?       // per km, for steady running
    var intervalNote: String?         // where the intervals came from, or why they don't match the plan

    var paceSecPerKm: Double? {
        guard let km = distanceKm, km > 0.05 else { return nil }
        return durationSec / km
    }

    var hasBreakdown: Bool { intervals != nil || splits != nil }
}

/// Stats for one Watch step or one km split.
struct IntervalStat: Codable, Hashable {
    var label: String
    var purpose: String            // warmup, work, recovery, cooldown, split
    var startOffsetSec: Double
    var durationSec: Double
    var distanceKm: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var target: String?

    var paceSecPerKm: Double? {
        guard let km = distanceKm, km > 0.05 else { return nil }
        return durationSec / km
    }

    /// e.g. "2:17, 0.40 km, 5:42 /km, HR 161 avg/168 max"
    var statsLine: String {
        var parts = [Format.duration(durationSec)]
        if let km = distanceKm { parts.append(km < 1 ? "\(Int((km * 1000).rounded())) m" : Format.km(km)) }
        if let p = paceSecPerKm { parts.append(Format.pace(p)) }
        if let avg = avgHeartRate {
            parts.append("HR \(Int(avg)) avg" + (maxHeartRate.map { "/\(Int($0)) max" } ?? ""))
        }
        return parts.joined(separator: ", ")
    }
}

/// One step the Watch workout will run, in order, as built by `WatchWorkout`.
struct ExpectedStep: Hashable {
    var label: String
    var purpose: String            // warmup, work, recovery, cooldown
    var target: String?
    var distanceKm: Double?
    var durationMin: Double?
}

// MARK: - Helpers

enum Format {
    static func duration(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        let h = s / 3600, m = (s % 3600) / 60, ss = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%d:%02d", m, ss)
    }

    static func pace(_ secPerKm: Double) -> String {
        let s = Int(secPerKm.rounded())
        return String(format: "%d:%02d /km", s / 60, s % 60)
    }

    static func km(_ v: Double) -> String { String(format: "%.2f km", v) }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}
