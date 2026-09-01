import SwiftUI

struct RootView: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var onboardingAuthorizationState: ScreenTimeAuthorizationState = .notDetermined

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
                    authorizationState: onboardingAuthorizationState,
                    onContinue: {
                        Task {
                            let state = await container.screenTimeAuthorizationService.requestAuthorization()
                            await MainActor.run {
                                onboardingAuthorizationState = state
                                completeOnboardingIfAuthorized(state)
                            }
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
        // Attached once, at the root: the toast lives in its own window above everything,
        // so it survives sheets and covers the status bar. Attaching it per screen would
        // build that window several times over.
        .locktyToasts(container.toastCenter)
        .task {
            await container.startupCoordinator.startIfNeeded()
            await refreshOnboardingAuthorizationState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshOnboardingAuthorizationState()
                await container.startupCoordinator.handleForeground()
            }
        }
        // lockty://unlock — the shield's primary button opens this directly, and the
        // notification it falls back to carries it too. Either way it lands on the same
        // pending request the coordinator reads out of the App Group.
        .onOpenURL { url in
            guard url.scheme == "lockty", url.host == "unlock" else { return }
            Task { await container.startupCoordinator.handleForeground() }
        }
    }

    @MainActor
    private func completeOnboardingIfAuthorized(_ state: ScreenTimeAuthorizationState) {
        guard state == .authorized || state == .authorizedWithDataAccess else { return }
        container.session.completeOnboarding()
    }

    private func refreshOnboardingAuthorizationState() async {
        let state = await container.screenTimeAuthorizationService.refreshAuthorizationState()
        await MainActor.run {
            onboardingAuthorizationState = state
            completeOnboardingIfAuthorized(state)
        }
    }
}
