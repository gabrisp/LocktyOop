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
        let store = AppGroupStore()
        let runtime = try? store.loadRuntimeState()
        let allActive = runtime?.activeRoutines ?? []

        // What is actually holding *this* app, asked in the right order.
        //
        // A limit first. With a routine running and an unrelated app over its daily
        // budget, the shield blamed the routine -- it was the only thing this screen ever
        // looked at -- so it said "Deep work is running" over an app Deep Work does not
        // block, and the real answer, that the app had used its two hours, was nowhere on
        // the screen. The limit is matched on the app's own token, which is the one thing
        // both sides genuinely hold.
        let token = application?.token
        let limitRule = token.flatMap { token -> Rule? in
            let lookup = RuleShieldLookup(appGroupStore: store)
            guard let rule = lookup.limitingRule(for: token) else { return nil }
            return rule.isShielding(given: store.loadRuleEnforcementState()) ? rule : nil
        }

        // The routines holding this app shut. With several running at once only the ones
        // blocking it have any say; the others are blocking something else entirely.
        //
        // Matched through every scope the routine blocks through, not just the apps picked
        // on it directly. A routine that names what it holds by app group has an empty
        // `blockedApplications`, so nothing here matched, and the screen fell through to
        // blaming whatever happened to be running -- with that routine's name, glyph and
        // colour over an app it does not hold, and its break policy deciding whether the
        // unlock button appeared. `ShieldActionExtension` already asks the question this
        // way; this screen was the half that still did not.
        let appID = token.map(AppIdentity.ID.init(token:))
        let selectionStore = ScreenTimeSelectionStore(appGroupStore: store)
        let blocking = appID.map { id in
            allActive.filter { routine in
                if routine.shieldPolicy.blockedApplications.contains(id) { return true }
                let selection = selectionStore.blockedSelection(scopes: routine.shieldPolicy.selectionScopes)
                return selection.applicationTokens.contains { AppIdentity.ID(token: $0) == id }
            }
        } ?? []
        let responsible = blocking.isEmpty && limitRule == nil ? allActive : blocking

        // Strict mode is the only thing that takes the unlock button away, and a limit
        // that has run out has nothing to give either: every responsible routine has to
        // allow it, because one strict routine is enough to keep the app shut and a button
        // that cannot deliver is a lie.
        // The one routine that answers for this app, and the same one the flow will ask.
        // Every routine having to agree meant one that allows no breaks took the button
        // away from a newer routine that does -- and the button is what the app decides
        // by, so the two screens disagreed about the same app.
        //
        // Strict answers first when there is one, being the strictest of them, but strict
        // is not itself a refusal. Strict mode is the promise that a routine cannot be
        // *ended* early; it says nothing about breaks, and a strict routine set up with
        // them is meant to have them. Taking the button away from one was the screen
        // enforcing a rule nobody wrote -- and refusing a friction the routine had been
        // given on purpose.
        let governing = responsible.routineAnsweringForApp
        // The same answer the button's action reads, so the word on the button and what
        // pressing it does cannot disagree: breaks left in this run and any cooldown, both
        // written down by the app because they come out of Core Data.
        let offersUnlock = limitRule == nil
            && !responsible.isEmpty
            && governing.map { routine in
                runtime?.breakAvailabilities[routine.routineID].map { $0.isAvailable() }
                    ?? (routine.breakPolicySnapshot.maximumBreaks > 0)
            } == true

        let preferences = store.loadShieldScreenPreferences()
        let packMessage = preferences.message(cost: todaysUsage(of: application))

        // The reasons, one per line, under an empty one.
        //
        // Both when both apply: a routine can be running *and* the app can have used its
        // day, and picking one to mention leaves the other as a surprise the next time.
        // The blank line above them is what keeps the title a title -- run together, the
        // whole thing reads as a paragraph nobody finishes.
        var reasons: [String] = []

        if let limitRule {
            reasons.append(Self.limitReason(limitRule, store: store))
        }

        switch responsible.count {
        case 0:
            if reasons.isEmpty { reasons.append("This app is locked.") }
        case 1:
            reasons.append("\(responsible[0].nameSnapshot) is running.")
        default:
            // Named rather than counted: knowing which routines are holding an app is what
            // tells you whether to wait one out or go and end one.
            reasons.append("\(responsible.map(\.nameSnapshot).joined(separator: " and ")) are running.")
        }

        if offersUnlock {
            reasons.append("Ask Lockty to unlock it, or close the app.")
        }

        // Its own face. An hourglass for a limit, the mode's own glyph for a mode, a shield
        // for a session -- a padlock on everything said only that something was locked,
        // which is the one thing already obvious from the screen being there.
        let symbol: String
        if preferences.isSilent {
            symbol = "moon.fill"
        } else if limitRule != nil {
            symbol = "hourglass"
        } else if let icon = governing?.iconSnapshot, !icon.isEmpty {
            symbol = icon
        } else if governing != nil {
            symbol = "shield.fill"
        } else {
            symbol = "lock.fill"
        }

        // The colour of whatever is holding it: the routine's own, or the plain amber a
        // limit is drawn in everywhere else. With several routines the first responsible
        // one wins -- the same one the sentence names first -- because a shield cannot be
        // two colours and a blend matches nothing anybody chose.
        let tint = limitRule != nil
            ? UIColor(red: 1.0, green: 0.77, blue: 0.34, alpha: 1)
            : governing.map { UIColor(routineColor: $0.colorSnapshot) }

        // Light or dark, as the phone is.
        //
        // The whole screen was written for black: a near-black ground, white type, and a
        // dark blur, forced whatever the device was set to. On a phone in light mode that
        // is a panel from another app. The ground is now the system's own, the type is
        // resolved through the trait collection, and the colour arrives as a cast over it
        // either way.
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let ground = isDark
            ? UIColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1)
            : UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        let primaryText: UIColor = isDark ? .white : UIColor(white: 0.06, alpha: 1)

        return ShieldConfiguration(
            backgroundBlurStyle: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight,
            // A cast of the colour over the ground rather than the colour itself: this is
            // read at arm's length over whatever app was opened, and a saturated ground
            // would make the words on it hard work.
            backgroundColor: tint?.blended(with: ground, amount: isDark ? 0.86 : 0.90) ?? ground,
            icon: UIImage(systemName: symbol),
            // The pack's line is the headline when there is one, with the reason under it.
            // The pack is what you chose to read; the reason is why the app will not open,
            // and dropping it would leave someone staring at a haiku with no idea what to
            // do about it.
            // Who stopped you, said plainly. "TikTok" on its own is the app announcing
            // itself; "TikTok is blocked by Lockty" is an answer, and it is the first
            // thing anybody wants from this screen.
            title: ShieldConfiguration.Label(
                text: packMessage ?? "\(resourceName) is blocked by Lockty",
                color: primaryText
            ),
            // The pack's line is the headline when there is one, so the plain sentence
            // moves down here in front of the reasons. The pack is what you chose to read;
            // the reasons are why the app will not open, and dropping them would leave
            // someone staring at a haiku with no idea what to do about it.
            subtitle: ShieldConfiguration.Label(
                text: packMessage == nil
                    ? "\n" + reasons.joined(separator: "\n")
                    : "\n\(resourceName) is blocked by Lockty.\n" + reasons.joined(separator: "\n"),
                color: primaryText.withAlphaComponent(isDark ? 0.68 : 0.62)
            ),
            primaryButtonLabel: offersUnlock
                ? ShieldConfiguration.Label(text: "Unlock with Lockty", color: .black)
                : ShieldConfiguration.Label(text: "Close", color: .black),
            // Every colour in the palette is light enough to carry black type, which is why
            // the label above is black either way.
            primaryButtonBackgroundColor: tint ?? (isDark ? .white : UIColor(white: 0.12, alpha: 1)),
            secondaryButtonLabel: offersUnlock
                ? ShieldConfiguration.Label(text: "Close", color: primaryText.withAlphaComponent(0.85))
                : nil
        )
    }

    /// What a limit says when it is the thing in the way.
    ///
    /// The figure, not the word: "you have used your 2 h today" is an answer, where "a
    /// limit is running" is the screen restating itself.
    private static func limitReason(_ rule: Rule, store: AppGroupStore) -> String {
        _ = store

        switch rule.kind {
        case .openCountLimit:
            let maximum = rule.openCountLimitConfiguration?.maximumOpens ?? 0
            return "You have hit the limit of \(maximum) opens."

        case .dailyUsageLimit:
            let minutes = rule.dailyUsageLimitConfiguration?.maximumMinutesPerDay ?? 0
            let length = minutes >= 60
                ? (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) m")
                : "\(minutes) m"
            return "You have hit the limit of \(length) here."

        case .sessionDurationLimit:
            let minutes = rule.sessionDurationLimitConfiguration?.maximumMinutesPerSession ?? 0
            return "You have hit the limit of \(minutes) m at a time."

        case .schedule:
            return rule.name
        }
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

private extension UIColor {
    convenience init(routineColor: RoutineColor) {
        let components = routineColor.components
        self.init(red: components.red, green: components.green, blue: components.blue, alpha: 1)
    }

    /// This colour mixed towards another. `amount` is how much of the *other* one.
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var otherRed: CGFloat = 0, otherGreen: CGFloat = 0, otherBlue: CGFloat = 0, otherAlpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
        else { return other }

        let mix = min(max(amount, 0), 1)
        return UIColor(
            red: red * (1 - mix) + otherRed * mix,
            green: green * (1 - mix) + otherGreen * mix,
            blue: blue * (1 - mix) + otherBlue * mix,
            alpha: alpha * (1 - mix) + otherAlpha * mix
        )
    }
}
