import SwiftUI

struct RootView: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch container.session.phase {
            case .splash:
                SplashView()

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
    }
}
