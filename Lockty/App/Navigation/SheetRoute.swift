import Foundation
import ManagedSettings

/// An app that a running allowance has already released, and when that runs out.
///
/// A snapshot rather than a live lookup: the expiry is fixed the moment the allowance is
/// granted, so the countdown has everything it needs to tick on its own.
struct AllowanceTimerRoute: Hashable {
    let appID: AppIdentity.ID
    var token: ApplicationToken?
    var expiresAt: Date
}

enum SheetRoute: Hashable, Identifiable {
    case allowanceTimer(AllowanceTimerRoute)
    case dayPicker
    case focusCreationChoice(FocusCreationChoiceRoute)
    case appClassification(AppIdentity.ID)
    case breakStatus(BreakUnavailableState)
    case routineBreak(UUID)
    case appPicker(ScreenTimeSelectionScope)
    case systemAccess
    case applicationDetails(AppIdentity.ID, day: Date?)
    case liveSession
    case ruleEditor(RuleEditorRoute)
    case routineEditor(RoutineEditorRoute)
    case pauseEditor(PauseEditorRoute)
    case pauseFlowEditor(PauseFlowEditorRoute)
    case frictionEditor(FrictionEditorRoute)
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
        case .allowanceTimer(let route): "allowance-timer-\(route.appID.rawValue)"
        case .dayPicker: "day-picker"
        case .focusCreationChoice(let route): "focus-creation-choice-\(route.draftID.uuidString)"
        case .appClassification(let id): "app-classification-\(id.rawValue)"
        case .breakStatus(let state): "break-status-\(state.id.uuidString)"
        case .routineBreak(let id): "routine-break-\(id.uuidString)"
        case .appPicker(let scope): "app-picker-\(scope.id)"
        case .systemAccess: "system-access"
        case .applicationDetails(let id, let day): "application-details-\(id.rawValue)-\(day?.timeIntervalSince1970 ?? 0)"
        case .liveSession: "live-session"
        case .ruleEditor(let route): "rule-editor-\(route.draftID.uuidString)"
        case .routineEditor(let route): "routine-editor-\(route.draftID.uuidString)"
        case .pauseEditor(let route): "pause-editor-\(route.draftID.uuidString)"
        case .pauseFlowEditor(let route): "pause-flow-editor-\(route.draftID.uuidString)"
        case .frictionEditor(let route): "friction-editor-\(route.draftID.uuidString)"
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
