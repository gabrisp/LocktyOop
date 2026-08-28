import SwiftUI
import UIKit

struct HomeView: View {
    @Bindable var router: AppRouter
    let featureFactory: FeatureFactory
    let destinationFactory: DestinationFactory

    private let visibleTabs = AppTab.visiblePrimaryTabs

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                NavigationStack(path: $router.todayPath) {
                    featureFactory.makeTodayView(day: router.selectedDay)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationFactory.destination(for: route)
                        }
                }
                .toolbar(.hidden, for: .tabBar)
                .toolbarVisibility(.hidden, for: .tabBar)
            }

            Tab(AppTab.focus.title, systemImage: AppTab.focus.systemImage, value: AppTab.focus) {
                NavigationStack(path: $router.focusPath) {
                    featureFactory.makeFocusView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationFactory.destination(for: route)
                        }
                }
                .toolbar(.hidden, for: .tabBar)
                .toolbarVisibility(.hidden, for: .tabBar)
            }

//            Tab(AppTab.lifetime.title, systemImage: AppTab.lifetime.systemImage, value: AppTab.lifetime) {
//                NavigationStack(path: $router.lifetimePath) {
//                    featureFactory.makeLifetimeView()
//                        .navigationDestination(for: AppRoute.self) { route in
//                            destinationFactory.destination(for: route)
//                        }
//                }
//                .toolbar(.hidden, for: .tabBar)
//                .toolbarVisibility(.hidden, for: .tabBar)
//            }
        }
        .hideNativeTabBar()
        .onAppear {
            if router.selectedTab == .lifetime {
                router.selectedTab = .today
            }
        }
        .safeAreaInset(edge: .bottom) {
            IGStyleTabBar(selection: $router.selectedTab, values: visibleTabs) { tab, isSelected in
                UIImage(
                    systemName: tab.systemImage,
                    withConfiguration: UIImage.SymbolConfiguration(weight: isSelected ? .semibold : .regular)
                ) ?? UIImage()
            } onInteraction: {
                featureFactory.haptics.selectionChanged()
            }
            .frame(height: 50)
            .fixedSize()
            .safeGlass(radius: 25, interactive: true)
            .padding(.bottom, LocktySpacing.sm)
            .opacity(1 - router.tabBarProgress)
            .offset(y: router.tabBarProgress * 80)
        }
        .sheet(item: $router.sheet) { route in
            destinationFactory.sheet(for: route)
        }
        .fullScreenCover(item: $router.fullScreen) { route in
            destinationFactory.fullScreen(for: route)
        }
    }
}
