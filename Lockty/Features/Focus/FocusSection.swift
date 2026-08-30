import Foundation

enum FocusSection: String, CaseIterable, Identifiable, Hashable {
    case routines
    case frictions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routines:
            "Routines"
        case .frictions:
            "Frictions"
        }
    }
}
