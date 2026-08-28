import Foundation

enum AppRoute: Hashable {
    case today(Date)
    case routineDetail(UUID)
    case pauseDetail(UUID)
    case settings
    case applicationDetails(AppIdentity.ID, day: Date?)
}
