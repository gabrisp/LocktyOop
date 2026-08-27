import Foundation

enum SheetRoute: Hashable, Identifiable {
    case appClassification(AppIdentity.ID)
    case routineBreak(UUID)
    case accentPicker
    case appPicker(ScreenTimeSelectionScope)
    case systemAccess

    var id: String {
        switch self {
        case .appClassification(let id): "app-classification-\(id.rawValue)"
        case .routineBreak(let id): "routine-break-\(id.uuidString)"
        case .accentPicker: "accent-picker"
        case .appPicker(let scope): "app-picker-\(scope.id)"
        case .systemAccess: "system-access"
        }
    }
}
