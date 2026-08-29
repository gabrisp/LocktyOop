import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(
            resourceName: application.localizedDisplayName ?? "this app",
            application: application
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(
            resourceName: application.localizedDisplayName ?? category.localizedDisplayName ?? "this app",
            application: application
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        // Pauses target a single application, so a shielded website never has one.
        makeConfiguration(resourceName: webDomain.domain ?? "this website", application: nil)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(
            resourceName: webDomain.domain ?? category.localizedDisplayName ?? "this website",
            application: nil
        )
    }

    /// The same two buttons on every shielded app: primary asks Lockty to unlock,
    /// secondary closes. Neither depends on a per-app rule any more -- the pause belongs
    /// to the running routine, so it covers everything that routine blocks.
    private func makeConfiguration(resourceName: String, application: Application?) -> ShieldConfiguration {
        let runtime = try? AppGroupStore().loadRuntimeState()
        let activeRoutine = runtime?.activeRoutine
        // Strict mode is the only thing that takes the unlock button away. It used to
        // hang on the routine's stored pause policy, so a routine saved without one
        // showed a shield whose only button closed the app -- and the standard
        // wait-then-confirm flow, which the action extension always falls back to, was
        // never reachable.
        let offersUnlock = activeRoutine.map { routine in
            routine.modeSnapshot != .strict || routine.allowsPauseDuringStrictMode
        } ?? false

        let subtitle = activeRoutine.map { routine in
            offersUnlock
                ? "\(routine.nameSnapshot) is running. Ask Lockty to unlock it, or close the app."
                : "\(routine.nameSnapshot) is running."
        } ?? "This app is locked."

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1),
            icon: UIImage(systemName: "lock.fill"),
            title: ShieldConfiguration.Label(
                text: "\(resourceName) was blocked by Lockty",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.68)
            ),
            primaryButtonLabel: offersUnlock
                ? ShieldConfiguration.Label(text: "Unlock with Lockty", color: .black)
                : ShieldConfiguration.Label(text: "Close", color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: offersUnlock
                ? ShieldConfiguration.Label(text: "Close", color: UIColor.white.withAlphaComponent(0.85))
                : nil
        )
    }
}
