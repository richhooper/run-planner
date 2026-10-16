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
