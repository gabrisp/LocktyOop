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

        let preferences = AppGroupStore().loadShieldScreenPreferences()
        let packMessage = preferences.message(cost: todaysUsage(of: application))

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
            icon: UIImage(systemName: preferences.isSilent ? "moon.fill" : "lock.fill"),
            // The pack's line is the headline when there is one, with the routine's own
            // sentence under it. The pack is what you chose to read; the sentence is why
            // the app will not open, and dropping it would leave someone staring at a
            // haiku with no idea what to do about it.
            title: ShieldConfiguration.Label(
                text: packMessage ?? resourceName,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: packMessage == nil ? subtitle : "\(resourceName) · \(subtitle)",
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

    /// How long this app has been used today, from the cached report snapshot.
    ///
    /// Nil when there is no snapshot or no entry for the app: Screen Time delivers these
    /// late, and a shield claiming "0m here today" over an app you have been in all
    /// morning is worse than a shield that simply does not mention it.
    private func todaysUsage(of application: Application?) -> String? {
        guard
            let token = application?.token,
            let snapshot = try? AppGroupStore().loadScreenTimeReportSnapshot(for: DayKey(date: Date())),
            let entry = snapshot.applications.first(where: { $0.app.id == AppIdentity.ID(token: token) }),
            entry.totalActivityDuration >= 60
        else { return nil }

        let minutes = Int(entry.totalActivityDuration / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }
}
