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
