import SwiftUI

struct RootView: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch container.session.phase {
            case .splash:
                // Unreachable: AppSession starts on .onboarding or .home. Kept so the
                // phase stays in the model, but it must never put a screen in the way.
//                SplashView()
                EmptyView()

            case .onboarding:
                OnboardingView(
                    authorizationState: container.screenTimeAuthorizationService.currentState,
                    onContinue: {
                        Task {
                            _ = await container.screenTimeAuthorizationService.requestAuthorization()
                            container.session.completeOnboarding()
                        }
                    }
                )

            case .home:
                HomeView(
                    router: container.router,
                    featureFactory: container.featureFactory,
                    destinationFactory: container.destinationFactory
                )
            }
        }
        .locktyScreenBackground()
        .preferredColorScheme(.dark)
        .task {
            await container.startupCoordinator.startIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await container.startupCoordinator.handleForeground() }
        }
        // lockty://unlock — the shield's primary button opens this directly, and the
        // notification it falls back to carries it too. Either way it lands on the same
        // pending request the coordinator reads out of the App Group.
        .onOpenURL { url in
            guard url.scheme == "lockty", url.host == "unlock" else { return }
            Task { await container.startupCoordinator.handleForeground() }
        }
    }
}
