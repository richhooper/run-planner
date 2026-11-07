import Foundation
import Observation
import WorkoutKit

/// Keeps exactly one workout from this app on the Apple Watch: the next unfinished run.
@MainActor @Observable
final class WatchSync {
    private(set) var status: String?

    func sync(_ data: AppData) async {
        guard WorkoutScheduler.isSupported else {
            status = "Sending workouts to Apple Watch isn't supported on this iPhone."
            return
        }
        let scheduler = WorkoutScheduler.shared

        var desired: WorkoutPlan?
        var title: String?
        if data.sendToWatch, let plan = data.currentPlan, let run = plan.nextRun {
            desired = WatchWorkout.plan(for: run, in: plan)
            title = WatchWorkout.title(for: run, in: plan)
        }

        var auth = await scheduler.authorizationState
        if desired != nil {
            if auth == .notDetermined { auth = await scheduler.requestAuthorization() }
            guard auth == .authorized else {
                status = "Allow Run Planner to schedule workouts: iPhone Settings › Apps › Run Planner."
                return
            }
        } else if auth != .authorized {
            status = nil
            return   // never asked, so there's nothing of ours to clean up
        }

        // Remove everything of ours except the next run, if it's already scheduled for today.
        let today = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        var alreadyThere = false
        for scheduled in await scheduler.scheduledWorkouts {
            if let desired, scheduled.plan == desired, Self.sameDay(scheduled.date, today) {
                alreadyThere = true
            } else {
                await scheduler.remove(scheduled.plan, at: scheduled.date)
            }
        }
        if let desired, !alreadyThere {
            await scheduler.schedule(desired, at: today)
        }

        if let title {
            status = "On your Watch: \(title)"
        } else {
            status = data.sendToWatch ? "No runs left to send." : nil
        }
    }

    private static func sameDay(_ a: DateComponents, _ b: DateComponents) -> Bool {
        a.year == b.year && a.month == b.month && a.day == b.day
    }
}
