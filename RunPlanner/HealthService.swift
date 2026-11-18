import Foundation
import HealthKit

enum HealthError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Apple Health isn't available on this device." }
}

/// Read-only access to running workouts recorded by Apple Watch / Fitness.
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
    ]

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Running workouts from the last `days` days, newest first.
    func recentRuns(days: Int) async throws -> [WorkoutSummary] {
        try await requestAccess()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: start, end: nil),
        ])
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        return try await query.result(for: store).map(WorkoutSummary.init(workout:))
    }

    /// Adds per-step intervals and km splits to `summary`, matched against the planned run.
    func addBreakdown(to summary: WorkoutSummary, for run: PlannedRun) async throws -> WorkoutSummary {
        try await requestAccess()
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: summary.id))],
            sortDescriptors: [], limit: 1)
        guard let workout = try await query.result(for: store).first else { return summary }

        let distance = try await samples(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), for: workout)
        let heartRate = try await samples(.heartRate, unit: .count().unitDivided(by: .minute()), for: workout)
        let start = workout.startDate
        let expected = run.expectedWatchSteps

        // Where the Watch's step boundaries are, best source first.
        var windows: [StepWindow] = []
        var source = ""
        let activities = workout.workoutActivities
        let segments = (workout.workoutEvents ?? []).filter { $0.type == .segment && $0.dateInterval.duration > 0 }
        if activities.count > 1 {
            windows = activities.map {
                StepWindow(interval: DateInterval(start: $0.startDate, end: $0.endDate ?? workout.endDate),
                           activeDuration: $0.duration)
            }
            source = "From the Watch's recorded steps"
        } else if segments.count > 1 {
            windows = segments.map { StepWindow(interval: $0.dateInterval) }
            source = "From the Watch's recorded segments"
        }

        var result = summary
        if !windows.isEmpty {
            let r = IntervalMath.intervals(windows: windows, expected: expected, source: source, workoutStart: start,
                                           distance: distance, heartRate: heartRate)
            result.intervals = r.stats
            result.intervalNote = r.note
        } else if expected.count > 1 {
            // No recorded steps: follow the plan's distances and times through the recording.
            let est = IntervalMath.estimateWindows(steps: expected, start: start, end: workout.endDate, distance: distance)
            windows = est
            result.intervals = est.enumerated().map { i, w in
                let placed = est.count == expected.count || i < est.count - 1
                let e = placed ? expected[i] : ExpectedStep(label: "Rest of run", purpose: "step")
                return IntervalMath.stat(label: e.label, purpose: e.purpose, target: e.target, window: w,
                                         workoutStart: start, distance: distance, heartRate: heartRate)
            }
            result.intervalNote = "Estimated from the plan's distances and times (the Watch didn't record step times), so boundaries are approximate."
        }

        if run.wantsSplits {
            // Split the main running step if there is one, so a warm-up or strides don't blur the km times.
            let main = zip(windows, result.intervals ?? [])
                .filter { $0.1.purpose == "work" }
                .max { $0.0.interval.duration < $1.0.interval.duration }?.0.interval
            let window = main ?? DateInterval(start: start, end: workout.endDate)
            result.splits = IntervalMath.kmSplits(window: window, workoutStart: start, distance: distance, heartRate: heartRate)
        }
        return result
    }

    /// Samples the Watch recorded for this workout, oldest first.
    private func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, for workout: HKWorkout) async throws -> [TimedValue] {
        let type = HKQuantityType(id)
        let fromWorkout = HKQuery.predicateForObjects(from: workout)
        let inTime = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let sort = [SortDescriptor(\HKQuantitySample.startDate)]

        var found = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: fromWorkout)], sortDescriptors: sort
        ).result(for: store)
        if found.isEmpty {
            // Some sources don't link samples to the workout; fall back to its time range.
            found = try await HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: inTime)], sortDescriptors: sort
            ).result(for: store)
        }
        return found.map { TimedValue(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
    }
}

extension WorkoutSummary {
    init(workout w: HKWorkout) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartRate = w.statistics(for: HKQuantityType(.heartRate))
        self.init(
            id: w.uuid,
            start: w.startDate,
            durationSec: w.duration,
            distanceKm: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)),
            avgHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
            maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm),
            activeKcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()),
            elevationGainM: (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
                .doubleValue(for: .meter()),
            indoor: (w.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue
        )
    }
}
