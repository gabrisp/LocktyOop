import SwiftUI

struct HomeView: View {
    @Bindable var router: AppRouter
    let featureFactory: FeatureFactory
    let destinationFactory: DestinationFactory

    var body: some View {
        NavigationStack(path: $router.path) {
            TabView(selection: $router.selectedTab) {
                Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                    featureFactory.makeTodayView(day: router.selectedDay)
                }

                Tab(AppTab.focus.title, systemImage: AppTab.focus.systemImage, value: AppTab.focus) {
                    featureFactory.makeFocusView()
                }

                Tab(AppTab.lifetime.title, systemImage: AppTab.lifetime.systemImage, value: AppTab.lifetime) {
                    featureFactory.makeLifetimeView()
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destinationFactory.destination(for: route)
            }
            .sheet(item: $router.sheet) { route in
                destinationFactory.sheet(for: route)
            }
            .fullScreenCover(item: $router.fullScreen) { route in
                destinationFactory.fullScreen(for: route)
            }
            .locktyScreenBackground()
            .safeSafeAreaBar(edge: .top, spacing: 0) {
                switch router.selectedTab {
                case .today:
                    // Calendar-hide animation paused: always shown at full height.
//                    let sliderProgress = MetricsHeaderGeometry.rangedProgress(
//                        router.todayChromeCollapseProgress,
//                        from: 0.14,
//                        to: 0.74
//                    )

                    DateSliderView(
                        dates: router.dayNavigationDays,
                        selectedDate: $router.selectedDay,
                        scrollOffset: $router.daySliderOffset,
                        onSelectionChanged: featureFactory.haptics.selectionChanged
                    )
//                    .opacity(1 - sliderProgress)
//                    .frame(height: DayPageSliderMetrics.barHeight * (1 - sliderProgress))
//                    .clipped()
//                    .allowsHitTesting(sliderProgress < 0.05)

                case .focus:
                    EmptyView()

                case .lifetime:
                    EmptyView()
                }
            }
        }
    }
}
