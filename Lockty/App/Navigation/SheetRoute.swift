import Foundation

enum SheetRoute: Hashable, Identifiable {
    case appClassification(AppIdentity.ID)
    case routineBreak(UUID)
    case accentPicker
    case appPicker(ScreenTimeSelectionScope)
    case systemAccess
    case routineIconPicker(UUID)
    case routineColorPicker(UUID)
    case routineTriggers(UUID)
    case routineAppPicker(UUID)
    case pauseAppPicker(UUID)

    var id: String {
        switch self {
        case .appClassification(let id): "app-classification-\(id.rawValue)"
        case .routineBreak(let id): "routine-break-\(id.uuidString)"
        case .accentPicker: "accent-picker"
        case .appPicker(let scope): "app-picker-\(scope.id)"
        case .systemAccess: "system-access"
        case .routineIconPicker(let draftID): "routine-icon-picker-\(draftID.uuidString)"
        case .routineColorPicker(let draftID): "routine-color-picker-\(draftID.uuidString)"
        case .routineTriggers(let draftID): "routine-triggers-\(draftID.uuidString)"
        case .routineAppPicker(let draftID): "routine-app-picker-\(draftID.uuidString)"
        case .pauseAppPicker(let draftID): "pause-app-picker-\(draftID.uuidString)"
        }
    }
}
