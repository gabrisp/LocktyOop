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
        }
    }
}
