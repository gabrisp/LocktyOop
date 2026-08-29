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

    /// True only when an enabled Pause rule exists for this specific app — the
    /// secondary button offers the Pause flow, so it must not appear otherwise.
    private func pauseRule(for application: Application?) -> PauseRuleSnapshot? {
        guard let application else { return nil }

        let snapshots = AppGroupStore().loadPauseRuleSnapshots().filter(\.isEnabled)
        guard !snapshots.isEmpty else { return nil }

        if let token = application.token,
           let match = snapshots.first(where: { $0.application.applicationToken == token }) {
            return match
        }

        if let bundleIdentifier = application.bundleIdentifier,
           let match = snapshots.first(where: {
               $0.application.bundleIdentifier == bundleIdentifier
                   || $0.application.id.rawValue == bundleIdentifier
           }) {
            return match
        }

        return nil
    }

    private func makeConfiguration(resourceName: String, application: Application?) -> ShieldConfiguration {
        let runtime = try? AppGroupStore().loadRuntimeState()
        let rule = pauseRule(for: application)
        let allowsPause = runtime?.pendingPause == nil && rule != nil
        let activeRoutineName = runtime?.activeRoutine?.nameSnapshot
        // Prefer the user's own label: the system only gives us an opaque token, so
        // localizedDisplayName is frequently unavailable here.
        let title = rule?.displayName ?? resourceName

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1),
            icon: UIImage(systemName: "lock.shield"),
            title: ShieldConfiguration.Label(
                text: title,
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
