import Foundation

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case today
    case focus
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .lifetime: "Lifetime"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "chart.bar.xaxis"
        case .focus: "scope"
        case .lifetime: "chart.line.uptrend.xyaxis"
        }
    }
}
