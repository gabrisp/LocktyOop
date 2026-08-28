import SwiftUI

struct RootView: View {
    let container: AppContainer

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
        .task {
            await container.startupCoordinator.startIfNeeded()
        }
    }
}
