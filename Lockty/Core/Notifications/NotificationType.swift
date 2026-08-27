import Foundation

enum NotificationType: String, Codable, CaseIterable, Hashable {
    case routineStarted
    case routineEnding
    case breakEnding
    case pauseRequested
    case routineReminder
    case alarmAction
    case authorizationRecovery
    case relockFailed
}
