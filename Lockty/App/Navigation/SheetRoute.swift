import Foundation

enum SheetRoute: Hashable, Identifiable {
    case appClassification(AppIdentity.ID)
    case routineBreak(UUID)
    case appPicker(ScreenTimeSelectionScope)
    case systemAccess
    case routineEditor(RoutineEditorRoute)
    case pauseEditor(PauseEditorRoute)
    case productivityDetail(Date)
    case controlDetail(Date)
    case detoxDetail(Date)
    case screenTimeDetail(Date)
    case routineDaySummary(Date)
    case pauseDaySummary(Date)
    case distractionsDetail(Date)
    case intentionalTimeDetail(Date)
    case digitalBalanceDetail(Date)

    var id: String {
        switch self {
        case .appClassification(let id): "app-classification-\(id.rawValue)"
        case .routineBreak(let id): "routine-break-\(id.uuidString)"
        case .appPicker(let scope): "app-picker-\(scope.id)"
        case .systemAccess: "system-access"
        case .routineEditor(let route): "routine-editor-\(route.draftID.uuidString)"
        case .pauseEditor(let route): "pause-editor-\(route.draftID.uuidString)"
        case .productivityDetail(let day): "productivity-detail-\(day.timeIntervalSince1970)"
        case .controlDetail(let day): "control-detail-\(day.timeIntervalSince1970)"
        case .detoxDetail(let day): "detox-detail-\(day.timeIntervalSince1970)"
        case .screenTimeDetail(let day): "screen-time-detail-\(day.timeIntervalSince1970)"
        case .routineDaySummary(let day): "routine-day-summary-\(day.timeIntervalSince1970)"
        case .pauseDaySummary(let day): "pause-day-summary-\(day.timeIntervalSince1970)"
        case .distractionsDetail(let day): "distractions-detail-\(day.timeIntervalSince1970)"
        case .intentionalTimeDetail(let day): "intentional-time-detail-\(day.timeIntervalSince1970)"
        case .digitalBalanceDetail(let day): "digital-balance-detail-\(day.timeIntervalSince1970)"
        }
    }
}
