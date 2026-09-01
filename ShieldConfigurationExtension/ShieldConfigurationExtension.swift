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
        let allActive = runtime?.activeRoutines ?? []

        // The routines actually holding *this* app shut. With several running at once
        // only the ones blocking it have any say over its shield; the others are
        // blocking something else entirely.
        let appID = application?.token.map(AppIdentity.ID.init(token:))
        let blocking = appID.map { id in
            allActive.filter { $0.shieldPolicy.blockedApplications.contains(id) }
        } ?? []
        let responsible = blocking.isEmpty ? allActive : blocking

        // Strict mode is the only thing that takes the unlock button away. It used to
        // hang on the routine's stored pause policy, so a routine saved without one
        // showed a shield whose only button closed the app -- and the standard
        // wait-then-confirm flow, which the action extension always falls back to, was
        // never reachable.
        //
        // Every responsible routine has to allow it: one strict routine is enough to
        // keep the app shut, and offering a button that cannot deliver would be a lie.
        let offersUnlock = !responsible.isEmpty && responsible.allSatisfy { routine in
            routine.modeSnapshot != .strict || routine.allowsPauseDuringStrictMode
        }

        let subtitle: String
        switch responsible.count {
        case 0:
            subtitle = "This app is locked."
        case 1:
            let name = responsible[0].nameSnapshot
            subtitle = offersUnlock
                ? "\(name) is running. Ask Lockty to unlock it, or close the app."
                : "\(name) is running."
        default:
            // Named rather than counted: knowing which routines are holding an app is
            // what tells you whether to wait one out or go and end one.
            let names = responsible.map(\.nameSnapshot).joined(separator: " and ")
            subtitle = offersUnlock
                ? "\(names) are running. Ask Lockty to unlock it, or close the app."
                : "\(names) are running."
        }

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
