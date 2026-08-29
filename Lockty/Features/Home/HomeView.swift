import SwiftUI

struct HomeView: View {
    @Bindable var router: AppRouter
    let featureFactory: FeatureFactory
    let destinationFactory: DestinationFactory

    /// Shared namespace so the bottom bar zooms into the live session sheet.
    @Namespace private var liveSessionZoom

    private var activeRoutine: ActiveRoutine? {
        featureFactory.routineEngine.activeRoutine()
    }

    var body: some View {
        // No TabView: Today is the whole screen, Routines and Pauses are opened from
        // cards inside it, and the bottom bar is reserved for the running session.
        NavigationStack(path: $router.todayPath) {
            featureFactory.makeTodayView(day: router.selectedDay)
                .locktyScreenBackground()
                .navigationDestination(for: AppRoute.self) { route in
                    destinationFactory.destination(for: route)
                }
        }
        .safeAreaInset(edge: .bottom) {
            if let activeRoutine {
                ActiveSessionBar(
                    routine: activeRoutine,
                    pauseCount: featureFactory.pausesViewModel.eventsSince(activeRoutine.startedAt).count
                ) {
                    router.presentSheet(.liveSession)
                }
                .matchedTransitionSource(id: SheetRoute.liveSession.id, in: liveSessionZoom)
                .padding(.bottom, LocktySpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: activeRoutine?.id)
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
