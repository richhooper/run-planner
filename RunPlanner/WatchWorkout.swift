import Foundation
import HealthKit
import WorkoutKit

/// Turns a planned run into an Apple Watch custom workout.
enum WatchWorkout {
    static func plan(for run: PlannedRun, in plan: TrainingPlan) -> WorkoutPlan {
        WorkoutPlan(.custom(workout(for: run, in: plan)), id: run.id)
    }

    static func workout(for run: PlannedRun, in plan: TrainingPlan) -> CustomWorkout {
        let layout = run.watchLayout
        var blocks = layout.blocks.map { block(for: $0, in: run) }
        var warmup = layout.warmup.map { step(for: $0, in: run) }

        if blocks.isEmpty {
            if let w = warmup {
                // A workout needs at least one block.
                blocks = [IntervalBlock(steps: [IntervalStep(.work, step: w)])]
                warmup = nil
            } else {
                blocks = [wholeRunBlock(run)]
            }
        }

        return CustomWorkout(activity: .running, location: .outdoor, displayName: title(for: run, in: plan),
                             warmup: warmup, blocks: blocks,
                             cooldown: layout.cooldown.map { step(for: $0, in: run) })
    }

    /// e.g. "B1 W2·2 Tempo 2 x 8 min", so workouts are easy to tell apart on the Watch.
    static func title(for run: PlannedRun, in plan: TrainingPlan) -> String {
        var prefix = ""
        if let m = plan.name.firstMatch(of: #/(?i)block\s*(\d+)/#) { prefix += "B\(m.1) " }
        if let w = run.week { prefix += "W\(w)·\(plan.numberInWeek(of: run)) " }
        return prefix + run.title
    }

    // MARK: Pieces

    private static func block(for seg: Segment, in run: PlannedRun) -> IntervalBlock {
        var steps = [IntervalStep(.work, step: step(for: seg, in: run))]
        if let rec = seg.effectiveRecovery {
            steps.append(IntervalStep(.recovery, step: makeStep(
                goal: goal(km: rec.distanceKm, min: rec.durationMin), alert: rec.alert, name: rec.label ?? "Recovery")))
        }
        return IntervalBlock(steps: steps, iterations: max(seg.repeats ?? 1, 1))
    }

    private static func step(for seg: Segment, in run: PlannedRun) -> WorkoutStep {
        makeStep(goal: goal(km: seg.distanceKm, min: seg.durationMin), alert: run.watchAlert(for: seg), name: seg.label)
    }

    /// A run with no segments: one step for the whole run.
    private static func wholeRunBlock(_ run: PlannedRun) -> IntervalBlock {
        let alert = HeartRateRange(run.targetEffort).map(WatchAlert.heartRate) ?? PaceRange(run.targetPace).map(WatchAlert.pace)
        let s = makeStep(goal: goal(km: run.targetDistanceKm, min: run.targetDurationMin), alert: alert, name: run.title)
        return IntervalBlock(steps: [IntervalStep(.work, step: s)])
    }

    private static func makeStep(goal: WorkoutGoal, alert: WatchAlert?, name: String) -> WorkoutStep {
        let a = alert.map(workoutAlert)
        if #available(iOS 18, *) {
            return WorkoutStep(goal: goal, alert: a, displayName: name)
        }
        return WorkoutStep(goal: goal, alert: a)
    }

    private static func goal(km: Double?, min: Double?) -> WorkoutGoal {
        if let km, km > 0 { return .distance(km * 1000, .meters) }
        if let min, min > 0 { return .time((min * 60).rounded(), .seconds) }
        return .open
    }

    private static func workoutAlert(_ alert: WatchAlert) -> any WorkoutAlert {
        switch alert {
        case .pace(let p):
            // Pace is time per km; the Watch wants a speed range in m/s.
            return SpeedRangeAlert.speed((1000 / Double(p.slowSec))...(1000 / Double(p.fastSec)), unit: .metersPerSecond)
        case .heartRate(let h):
            return HeartRateRangeAlert.heartRate(Double(h.low)...Double(h.high))
        }
    }
}
