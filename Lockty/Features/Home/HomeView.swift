import SwiftUI

struct HomeView: View {
    @ObservedObject var router: AppRouter
    let featureFactory: FeatureFactory
    let destinationFactory: DestinationFactory

    /// Shared namespace so the bottom bar zooms into the live session sheet.
    @Namespace private var liveSessionZoom

    private var activeRoutine: ActiveRoutine? {
        featureFactory.routineEngine.activeRoutine()
    }

    var body: some View {
        // Two tabs, the plain system TabView: Today, and Routines/Pauses -- which is one
        // tab holding both behind a segmented control, not two. Each keeps its own
        // NavigationStack path so a push in one doesn't surface in the other.
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.todayPath) {
                featureFactory.makeTodayView(day: router.selectedDay)
                    .locktyScreenBackground()
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationFactory.destination(for: route)
                    }
            }
            .tabItem {
                Label(AppTab.today.title, systemImage: AppTab.today.systemImage)
            }
            .tag(AppTab.today)

            NavigationStack(path: $router.focusPath) {
                featureFactory.makeFocusView()
                    .locktyScreenBackground()
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationFactory.destination(for: route)
                    }
            }
            .tabItem {
                Label(AppTab.focus.title, systemImage: AppTab.focus.systemImage)
            }
            .tag(AppTab.focus)
        }
        // The selected tab is the app's own primary, not the AccentColor asset the bar
        // was falling back to. Nothing else in Lockty is tinted by that accent, so the
        // bar was the one place a colour from outside the palette showed up.
        .tint(LocktyColors.primaryText)
//        .safeAreaInset(edge: .bottom) {
//            Group {
//                if let activeRoutine {
//                    ActiveSessionBar(
//                        routine: activeRoutine,
//                        pauseCount: featureFactory.pausesViewModel.eventsSince(activeRoutine.startedAt).count
//                    ) {
//                        router.presentSheet(.liveSession)
//                    }
//                    .transition(.move(edge: .bottom).combined(with: .opacity))
//                }
//            }
//            // The zoom source is on this container, not on the bar itself. The bar
//            // redraws every second from its own TimelineView clock, and a source that
//            // gets re-created while the transition is running is dropped -- which is why
//            // dismissing sometimes just snapped back with no animation at all.
//            .matchedTransitionSource(id: SheetRoute.liveSession.id, in: liveSessionZoom)
//            .padding(.bottom, LocktySpacing.sm)
//            // Scoped to the bar. On the whole TabView this implicit animation was picked
//            // up by the presentation itself and fought the zoom.
//            .animation(.snappy(duration: 0.28, extraBounce: 0.05), value: activeRoutine?.id)
//        }
        .sheet(item: $router.sheet) { route in
            // Only the live session zooms, and only from the bottom bar that opened it —
            // every other sheet has no matching source and must present normally.
            if route == .liveSession {
                destinationFactory.sheet(for: route)
                    .navigationTransition(.zoom(sourceID: SheetRoute.liveSession.id, in: liveSessionZoom))
            } else {
                destinationFactory.sheet(for: route)
            }
        }
        .fullScreenCover(item: $router.fullScreen) { route in
            destinationFactory.fullScreen(for: route)
        }
    }
}
