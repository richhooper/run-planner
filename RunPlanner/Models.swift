import Foundation

// MARK: - App data (everything the app stores, in one JSON file)

struct AppData: Codable {
    var goal: String = ""
    var aboutMe: String = ""
    var runsPerWeek: Int = 3
    var currentPlan: TrainingPlan?
    var history: [TrainingPlan] = []   // finished blocks, newest first

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        aboutMe = try c.decodeIfPresent(String.self, forKey: .aboutMe) ?? ""
        runsPerWeek = try c.decodeIfPresent(Int.self, forKey: .runsPerWeek) ?? 3
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
    var runs: [PlannedRun]
    var importedAt: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Training block"
        coachNotes = try c.decodeIfPresent(String.self, forKey: .coachNotes)
        runs = try c.decode([PlannedRun].self, forKey: .runs)
        importedAt = (try? c.decodeIfPresent(Date.self, forKey: .importedAt)) ?? .now
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
    var details: String?
    var segments: [Segment]?
    var completion: Completion?

    enum CodingKeys: String, CodingKey {
        case id, week, title, type, targetDistanceKm, targetDurationMin, targetPace, targetEffort
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
}

struct Segment: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var durationMin: Double?
    var distanceKm: Double?
    var repeats: Int?
    var intensity: String?

    enum CodingKeys: String, CodingKey { case label, durationMin, distanceKm, repeats, intensity }

    var summary: String {
        var parts: [String] = []
        if let d = distanceKm { parts.append(d < 1 ? "\(Int((d * 1000).rounded())) m" : "\(Format.number(d)) km") }
        if let m = durationMin { parts.append(m < 1 ? "\(Int((m * 60).rounded())) s" : "\(Format.number(m)) min") }
        let base = parts.joined(separator: " / ")
        if let r = repeats, r > 1 { return base.isEmpty ? "\(r) ×" : "\(r) × \(base)" }
        return base
    }
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

    var paceSecPerKm: Double? {
        guard let km = distanceKm, km > 0.05 else { return nil }
        return durationSec / km
    }
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
