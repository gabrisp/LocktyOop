import Foundation
import CoreGraphics
import Observation

@Observable
final class AppRouter {
    // Each tab keeps its own independent push history, matching the custom
    // per-tab NavigationStack setup in HomeView (a single shared path across
    // tabs doesn't work with that — pushes from one tab would show up
    // when switching to another).
    var todayPath: [AppRoute] = []
    var focusPath: [AppRoute] = []
    var lifetimePath: [AppRoute] = []
    var selectedTab: AppTab = .today
    var sheet: SheetRoute?
    var fullScreen: FullScreenRoute?
    var selectedDay: Date
    var daySliderOffset: CGFloat
    var todayChromeCollapseProgress: CGFloat = 0
    /// Drives IGStyleTabBar's scroll-hide behavior: 0 = expanded/visible, 1 = minimized/hidden.
    var tabBarProgress: CGFloat = 0
    let dayNavigationDays: [Date]

    var path: [AppRoute] {
        get {
            switch selectedTab {
            case .today: todayPath
            case .focus: focusPath
            case .lifetime: lifetimePath
            }
        }
        set {
            switch selectedTab {
            case .today: todayPath = newValue
            case .focus: focusPath = newValue
            case .lifetime: lifetimePath = newValue
            }
        }
    }

    init(today: Date = Date(), calendar: Calendar = .current) {
        let normalizedToday = calendar.startOfDay(for: today)
        let days = Self.makeDayNavigationDays(endingAt: normalizedToday, calendar: calendar)

        selectedDay = normalizedToday
        dayNavigationDays = days
        daySliderOffset = 0
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func presentSheet(_ route: SheetRoute) {
        sheet = route
    }

    func presentFullScreen(_ route: FullScreenRoute) {
        fullScreen = route
    }

    func dismissSheet() {
        sheet = nil
    }

    func dismissFullScreen() {
        fullScreen = nil
    }

    private static func makeDayNavigationDays(endingAt day: Date, calendar: Calendar) -> [Date] {
        (-30...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: day)
        }
    }
}
