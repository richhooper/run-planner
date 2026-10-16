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

    /// Makes `plan` the current plan, archiving the old one if any of it was done.
    func install(_ plan: TrainingPlan) {
        var d = data
        if let current = d.currentPlan, current.resolvedCount > 0 {
            d.history.insert(current, at: 0)
        }
        d.currentPlan = plan
        data = d
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
