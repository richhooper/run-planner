import Foundation
import Observation

@Observable
final class PlanStore {
    var data: AppData {
        didSet { save() }
    }

    static let fileURL = URL.documentsDirectory.appending(path: "runplanner.json")

    init() {
        if let raw = try? Data(contentsOf: Self.fileURL) {
            if let decoded = try? JSONCoding.decoder.decode(AppData.self, from: raw) {
                data = decoded
                return
            }
            // Never silently overwrite a file we couldn't read – keep a copy.
            let stamp = Int(Date().timeIntervalSince1970)
            try? raw.write(to: URL.documentsDirectory.appending(path: "runplanner-unreadable-\(stamp).json"))
        }
        data = AppData()
    }

    private func save() {
        do {
            try JSONCoding.encoder.encode(data).write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Save failed: \(error)")
        }
    }

    // MARK: Queries

    func run(_ id: UUID) -> PlannedRun? {
        data.currentPlan?.runs.first { $0.id == id }
    }

    var backupJSON: String {
        (try? JSONCoding.encoder.encode(data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Mutations

    func setCompletion(_ completion: Completion?, for id: UUID) {
        guard var plan = data.currentPlan, let i = plan.runs.firstIndex(where: { $0.id == id }) else { return }
        plan.runs[i].completion = completion
        data.currentPlan = plan
    }

    enum InstallMode {
        /// Old block is finished: keep it, with its links, in history.
        case archive
        /// New plan is a revision: move completions across by week and run number.
        case relink
        /// Drop the old block and its links, so those workouts can be attached again.
        case removeLinks
    }

    /// Replaces the Apple Watch data on a completed run, e.g. after adding interval stats.
    func updateWorkout(_ workout: WorkoutSummary, for id: UUID) {
        guard var plan = data.currentPlan, let i = plan.runs.firstIndex(where: { $0.id == id }),
              plan.runs[i].completion?.workout?.id == workout.id else { return }
        plan.runs[i].completion?.workout = workout
        data.currentPlan = plan
    }

    /// Makes `plan` the current plan.
    func install(_ plan: TrainingPlan, mode: InstallMode = .archive) {
        var d = data
        var plan = plan
        if let current = d.currentPlan, current.resolvedCount > 0 {
            switch mode {
            case .archive:
                d.history.insert(current, at: 0)
            case .relink:
                for (i, run) in plan.runs.enumerated() {
                    plan.runs[i].completion = current.matchingRun(for: run, in: plan)?.completion
                }
            case .removeLinks:
                break
            }
        }
        d.currentPlan = plan
        data = d
    }
}

extension TrainingPlan {
    /// 1-based position of `run` among the runs in its week.
    func numberInWeek(of run: PlannedRun) -> Int {
        (runsInWeek(run.week ?? 0).firstIndex { $0.id == run.id } ?? 0) + 1
    }

    /// The run in this plan with the same week and run number as `run` in `other`.
    func matchingRun(for run: PlannedRun, in other: TrainingPlan) -> PlannedRun? {
        let week = runsInWeek(run.week ?? 0)
        let n = other.numberInWeek(of: run)
        return week.indices.contains(n - 1) ? week[n - 1] : nil
    }

    /// How many of this plan's completed or skipped runs have a match in `newPlan`.
    func relinkCount(into newPlan: TrainingPlan) -> Int {
        newPlan.runs.filter { matchingRun(for: $0, in: newPlan)?.completion != nil }.count
    }
}

// MARK: - Importing AI output

enum PlanImportError: LocalizedError {
    case noJSON, noRuns, invalid(String)

    var errorDescription: String? {
        switch self {
        case .noJSON: "Couldn't find a JSON plan in that text. Copy the whole reply, including the { … } block."
        case .noRuns: "The plan has no runs in it."
        case .invalid(let why): why
        }
    }
}

enum PlanImporter {
    static func parse(_ text: String) throws -> TrainingPlan {
        let cleaned = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
        let json = extractJSON(cleaned)
        guard let json else { throw PlanImportError.noJSON }

        var plan: TrainingPlan
        do {
            plan = try JSONCoding.decoder.decode(TrainingPlan.self, from: Data(json.utf8))
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw PlanImportError.invalid("Missing \"\(key.stringValue)\" at \(path(ctx)).")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw PlanImportError.invalid("Wrong type at \(path(ctx)): \(ctx.debugDescription)")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw PlanImportError.invalid("Empty value at \(path(ctx)).")
        } catch DecodingError.dataCorrupted {
            throw PlanImportError.invalid("That isn't valid JSON. The reply may have been cut off, so try copying it again.")
        }

        guard !plan.runs.isEmpty else { throw PlanImportError.noRuns }
        // Fresh identity for everything we import.
        plan.id = UUID()
        plan.importedAt = .now
        for i in plan.runs.indices {
            plan.runs[i].id = UUID()
            plan.runs[i].completion = nil
        }
        return plan
    }

    /// Prefers a ```json fenced block, otherwise the outermost { … }.
    private static func extractJSON(_ text: String) -> String? {
        if let fence = text.range(of: "```json") ?? text.range(of: "```"),
           let close = text.range(of: "```", range: fence.upperBound..<text.endIndex) {
            let inner = String(text[fence.upperBound..<close.lowerBound])
            if inner.contains("{") { return inner }
        }
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e else { return nil }
        return String(text[s...e])
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map { $0.intValue.map { "#\($0 + 1)" } ?? $0.stringValue }
        return p.isEmpty ? "the top level" : p.joined(separator: " › ")
    }
}
