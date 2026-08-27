import Foundation
import CoreGraphics
import Observation

@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var selectedTab: AppTab = .today
    var sheet: SheetRoute?
    var fullScreen: FullScreenRoute?
    var selectedDay: Date
    var daySliderOffset: CGFloat
    var todayChromeCollapseProgress: CGFloat = 0
    let dayNavigationDays: [Date]

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
