import Foundation

enum AppRoute: Hashable {
    case today(Date)
    case routineDetail(UUID)
    case routineEditor(RoutineEditorRoute)
    case pauseDetail(UUID)
    case pauseEditor(PauseEditorRoute)
    case settings
    case productivityDetail(Date)
    case controlDetail(Date)
    case detoxDetail(Date)
    case screenTimeDetail(Date)
    case routineDaySummary(Date)
    case pauseDaySummary(Date)
    case distractionsDetail(Date)
    case intentionalTimeDetail(Date)
    case digitalBalanceDetail(Date)
    case applicationDetails(AppIdentity.ID, day: Date?)
}
