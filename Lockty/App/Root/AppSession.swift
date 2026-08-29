import Foundation
import Combine

final class AppSession: ObservableObject {
    private enum Keys {
        static let onboardingCompleted = "lockty.onboarding.completed"
    }

    @Published private(set) var phase: AppPhase = .splash
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var startupError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
    }

    func finishStartup(requiresOnboarding: Bool) {
        phase = requiresOnboarding ? .onboarding : .home
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.onboardingCompleted)
        phase = .home
    }

    func recordStartupError(_ message: String) {
        startupError = message
    }
}
