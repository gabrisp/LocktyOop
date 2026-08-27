import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(resourceName: application.localizedDisplayName ?? "this app")
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(resourceName: application.localizedDisplayName ?? category.localizedDisplayName ?? "this app")
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(resourceName: webDomain.domain ?? "this website")
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(resourceName: webDomain.domain ?? category.localizedDisplayName ?? "this website")
    }

    private func makeConfiguration(resourceName: String) -> ShieldConfiguration {
        let runtime = try? AppGroupStore().loadRuntimeState()
        let allowsPause = runtime?.pendingPause == nil
        let activeRoutineName = runtime?.activeRoutine?.nameSnapshot

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1),
            icon: UIImage(systemName: "lock.shield"),
            title: ShieldConfiguration.Label(
                text: resourceName,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: activeRoutineName.map { "Blocked by \($0)" } ?? "Locked by Lockty",
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Locked",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue,
            secondaryButtonLabel: allowsPause
                ? ShieldConfiguration.Label(text: "Open Mindfully", color: UIColor.white.withAlphaComponent(0.85))
                : nil
        )
    }
}
