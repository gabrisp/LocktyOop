import Foundation
import Combine
import CoreGraphics

final class AppRouter: ObservableObject {
    // Each tab keeps its own independent push history, matching the custom
    // per-tab NavigationStack setup in HomeView (a single shared path across
    // tabs doesn't work with that — pushes from one tab would show up
    // when switching to another).
    @Published var todayPath: [AppRoute] = []
    @Published var focusPath: [AppRoute] = []
    @Published var lifetimePath: [AppRoute] = []
    @Published var selectedTab: AppTab = .today
    @Published var sheet: SheetRoute?
    @Published var fullScreen: FullScreenRoute?
    /// An unlock the shield asked for while Lockty was closed. Today surfaces it as a
    /// card; answering the card is what opens the flow.
    @Published var pendingUnlock: PauseContext?
    @Published var selectedDay: Date
    @Published var daySliderOffset: CGFloat
    @Published var todayChromeCollapseProgress: CGFloat = 0
    /// Drives IGStyleTabBar's scroll-hide behavior: 0 = expanded/visible, 1 = minimized/hidden.
    @Published var tabBarProgress: CGFloat = 0
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

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
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
