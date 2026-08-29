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
        let offersUnlock = runtime?.pendingPause == nil
            && activeRoutine?.pausePolicySnapshot.offersPause == true

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1),
            icon: UIImage(systemName: "lock.shield"),
            title: ShieldConfiguration.Label(
                text: resourceName,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: activeRoutine.map { "Bloqueado por \($0.nameSnapshot)" } ?? "Bloqueado por Lockty",
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: offersUnlock
                ? ShieldConfiguration.Label(text: "Desbloquear", color: .black)
                : ShieldConfiguration.Label(text: "Cerrar", color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: offersUnlock
                ? ShieldConfiguration.Label(text: "Cerrar", color: UIColor.white.withAlphaComponent(0.85))
                : nil
        )
    }
}
