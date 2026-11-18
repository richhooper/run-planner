import Foundation

/// A sample spread over a time range: distance in km, or heart rate in bpm.
struct TimedValue {
    var start: Date
    var end: Date
    var value: Double
}

/// A stretch of the workout, with the time actually spent moving if the Watch knows it.
struct StepWindow {
    var interval: DateInterval
    var activeDuration: Double?
}

/// Splits a recorded workout into per-step and per-km stats. No HealthKit here, so it can be tested anywhere.
enum IntervalMath {
    // MARK: Stats for a window

    /// Distance covered inside `w`, counting the overlapping part of each sample.
    static func distanceKm(_ samples: [TimedValue], in w: DateInterval) -> Double? {
        var total = 0.0, any = false
        for s in samples {
            let lo = max(s.start, w.start), hi = min(s.end, w.end)
            let length = s.end.timeIntervalSince(s.start)
            if length <= 0 {
                if s.start >= w.start && s.start < w.end { total += s.value; any = true }
            } else if hi > lo {
                total += s.value * hi.timeIntervalSince(lo) / length
                any = true
            }
        }
        return any ? total : nil
    }

    static func heartRate(_ samples: [TimedValue], in w: DateInterval) -> (avg: Double, max: Double)? {
        let inside = samples.filter { $0.start >= w.start && $0.start < w.end }.map(\.value)
        guard let top = inside.max() else { return nil }
        return (inside.reduce(0, +) / Double(inside.count), top)
    }

    static func stat(label: String, purpose: String, target: String?, window: StepWindow, workoutStart: Date,
                     distance: [TimedValue], heartRate hr: [TimedValue]) -> IntervalStat {
        let h = heartRate(hr, in: window.interval)
        return IntervalStat(label: label, purpose: purpose,
                            startOffsetSec: window.interval.start.timeIntervalSince(workoutStart),
                            durationSec: window.activeDuration ?? window.interval.duration,
                            distanceKm: distanceKm(distance, in: window.interval),
                            avgHeartRate: h?.avg, maxHeartRate: h?.max, target: target)
    }

    // MARK: Matching recorded steps to the plan

    /// Labels recorded windows with the planned steps when the counts match; otherwise numbers them and explains.
    static func intervals(windows: [StepWindow], expected: [ExpectedStep], source: String, workoutStart: Date,
                          distance: [TimedValue], heartRate: [TimedValue]) -> (stats: [IntervalStat], note: String) {
        if windows.count == expected.count {
            let stats = zip(windows, expected).map { w, e in
                stat(label: e.label, purpose: e.purpose, target: e.target, window: w, workoutStart: workoutStart,
                     distance: distance, heartRate: heartRate)
            }
            return (stats, source)
        }
        let stats = windows.enumerated().map { i, w in
            stat(label: "Step \(i + 1)", purpose: "step", target: nil, window: w, workoutStart: workoutStart,
                 distance: distance, heartRate: heartRate)
        }
        let why = windows.count < expected.count ? "a step was probably skipped" : "steps were added or split"
        return (stats, "\(source). The Watch recorded \(windows.count) steps but the plan had \(expected.count): \(why), so steps are numbered rather than named.")
    }

    // MARK: Estimating steps from distance and time

    /// When the running total of distance after `t0` reaches `km`.
    static func time(whenDistance km: Double, after t0: Date, in samples: [TimedValue]) -> Date? {
        var covered = 0.0
        for s in samples where s.end > t0 {
            let start = max(s.start, t0)
            let length = s.end.timeIntervalSince(s.start)
            let part = length > 0 ? s.value * s.end.timeIntervalSince(start) / length : s.value
            if covered + part >= km {
                guard part > 0 else { return start }
                return start.addingTimeInterval(s.end.timeIntervalSince(start) * (km - covered) / part)
            }
            covered += part
        }
        return nil
    }

    /// Rebuilds step boundaries by following the plan's distances and times through the recording.
    /// Stops at the first step it can't place (an open step, or the workout ran out); the rest becomes one window.
    static func estimateWindows(steps: [ExpectedStep], start: Date, end: Date, distance: [TimedValue]) -> [StepWindow] {
        var windows: [StepWindow] = []
        var t = start
        for (i, step) in steps.enumerated() {
            let isLast = i == steps.count - 1
            var next: Date?
            if isLast {
                next = end
            } else if let km = step.distanceKm, km > 0 {
                next = time(whenDistance: km, after: t, in: distance)
            } else if let min = step.durationMin, min > 0 {
                next = t.addingTimeInterval(min * 60)
            }
            guard let stop = next, stop > t, stop <= end else { break }
            windows.append(StepWindow(interval: DateInterval(start: t, end: stop)))
            t = stop
        }
        if t < end, windows.count < steps.count {
            windows.append(StepWindow(interval: DateInterval(start: t, end: end)))
        }
        return windows
    }

    // MARK: Km splits

    static func kmSplits(window: DateInterval, workoutStart: Date, distance: [TimedValue], heartRate: [TimedValue]) -> [IntervalStat] {
        var splits: [IntervalStat] = []
        var t = window.start
        var km = 1
        while let next = time(whenDistance: 1, after: t, in: distance), next <= window.end {
            splits.append(stat(label: "km \(km)", purpose: "split", target: nil,
                               window: StepWindow(interval: DateInterval(start: t, end: next)),
                               workoutStart: workoutStart, distance: distance, heartRate: heartRate))
            t = next
            km += 1
        }
        let rest = DateInterval(start: t, end: max(t, window.end))
        if let d = distanceKm(distance, in: rest), d >= 0.1 {
            splits.append(stat(label: "last \(Int((d * 1000).rounded())) m", purpose: "split", target: nil,
                               window: StepWindow(interval: rest), workoutStart: workoutStart,
                               distance: distance, heartRate: heartRate))
        }
        return splits
    }
}
