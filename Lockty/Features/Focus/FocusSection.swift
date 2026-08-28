import Foundation

enum FocusSection: String, CaseIterable, Identifiable, Hashable {
    case routines
    case pauses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routines:
            "Routines"
        case .pauses:
            "Pauses"
        }
    }
}
