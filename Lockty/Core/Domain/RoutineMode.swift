import Foundation

nonisolated enum RoutineMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case normal
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .strict: "Strict"
        }
    }
}
