import Foundation
import Observation

struct SystemAccessItemState: Equatable {
    var title: String
    var detail: String
    var actionTitle: String?
    var isLoading = false
}

@MainActor
@Observable
final class SystemAccessViewModel {
    private let screenTime: ScreenTimeAuthorizationServicing
    private let notifications: NotificationServicing
    private let location: LocationTriggerServicing
    private let alarms: AlarmServicing

    private(set) var screenTimeState = SystemAccessItemState(title: "Screen Time", detail: "Checking", actionTitle: nil)
    private(set) var notificationState = SystemAccessItemState(title: "Notifications", detail: "Checking", actionTitle: nil)
    private(set) var locationState = SystemAccessItemState(title: "Location", detail: "Checking", actionTitle: nil)
    private(set) var alarmState = SystemAccessItemState(title: "Alarms", detail: "Checking", actionTitle: nil)

    init(screenTime: ScreenTimeAuthorizationServicing, notifications: NotificationServicing, location: LocationTriggerServicing, alarms: AlarmServicing) {
        self.screenTime = screenTime
        self.notifications = notifications
        self.location = location
        self.alarms = alarms
    }

    func refresh() async {
        let screen = await screenTime.refreshAuthorizationState()
        let notification = await notifications.refreshAuthorization()
        let location = await location.refreshAuthorization()
        let alarm = await alarms.authorizationState()
        screenTimeState = Self.screenItem(screen)
        notificationState = Self.notificationItem(notification)
        locationState = Self.locationItem(location)
        alarmState = SystemAccessItemState(title: "Alarms", detail: alarm.rawValue.capitalized, actionTitle: alarm == .notDetermined ? "Enable" : nil)
    }

    func requestScreenTime() async { screenTimeState.isLoading = true; _ = await screenTime.requestAuthorization(); await refresh() }
    func requestNotifications() async { notificationState.isLoading = true; _ = await notifications.requestAuthorization(); await refresh() }
    func requestLocation() async { locationState.isLoading = true; _ = await location.requestAuthorization(); await refresh() }
    func requestAlarms() async { alarmState.isLoading = true; _ = await alarms.requestAuthorization(); await refresh() }

    func requestAllAvailable() async {
        _ = await screenTime.requestAuthorization()
        _ = await notifications.requestAuthorization()
        _ = await location.requestAuthorization()
        _ = await alarms.requestAuthorization()
        await refresh()
    }

    private static func screenItem(_ state: ScreenTimeAuthorizationState) -> SystemAccessItemState {
        let detail: String
        switch state {
        case .authorized:
            detail = "Blocking allowed. Usage data still limited."
        case .authorizedWithDataAccess:
            detail = state.title
        default:
            detail = state.title
        }

        return SystemAccessItemState(
            title: "Screen Time",
            detail: detail,
            actionTitle: [.notDetermined, .denied].contains(state) ? "Request" : nil
        )
    }

    private static func notificationItem(_ state: NotificationAuthorizationState) -> SystemAccessItemState {
        SystemAccessItemState(title: "Notifications", detail: state.rawValue.capitalized, actionTitle: state == .notDetermined ? "Enable" : nil)
    }

    private static func locationItem(_ state: LocationAuthorizationState) -> SystemAccessItemState {
        SystemAccessItemState(title: "Location", detail: state.rawValue.capitalized, actionTitle: state == .notDetermined ? "Enable" : nil)
    }
}
