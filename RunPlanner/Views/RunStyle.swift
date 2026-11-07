import SwiftUI

extension PlannedRun {
    private var kind: String { (type ?? "easy").lowercased() }

    var symbol: String {
        switch kind {
        case "long": "road.lanes"
        case "tempo": "hare.fill"
        case "intervals": "bolt.fill"
        case "hills": "mountain.2.fill"
        case "recovery": "leaf.fill"
        case "strides": "wind"
        case "race": "flag.checkered"
        case "walk-run": "figure.walk"
        default: "figure.run"
        }
    }

    var color: Color {
        switch kind {
        case "long": .blue
        case "tempo": .orange
        case "intervals": .red
        case "hills": .brown
        case "recovery": .teal
        case "strides": .indigo
        case "race": .purple
        case "walk-run": .mint
        default: .green
        }
    }
}

extension Segment {
    /// Warm-ups, cool-downs and recoveries are muted; the work itself uses the run's colour.
    func color(runColor: Color) -> Color {
        let k = (kind ?? label).lowercased()
        if k.contains("warm") || k.contains("cool") { return .gray }
        if k.contains("recover") || k.contains("walk") { return .teal }
        if k.contains("stride") { return .indigo }
        if k.contains("drill") { return .mint }
        return runColor
    }
}

enum Effort {
    static func label(_ v: Int) -> String {
        switch v {
        case ...3: "Easy"
        case 4...6: "Moderate"
        case 7...8: "Hard"
        default: "All out"
        }
    }
}
