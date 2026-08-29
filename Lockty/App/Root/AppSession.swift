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
        let completed = defaults.bool(forKey: Keys.onboardingCompleted)
        hasCompletedOnboarding = completed
        // Never .splash. Whether onboarding is needed is already known here -- it is one
        // UserDefaults read -- so waiting on startup to decide only bought a shield
        // screen in front of the app for no reason. The real screen is the first thing
        // drawn, and it fills its own values in as they arrive.
        phase = completed ? .home : .onboarding
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
