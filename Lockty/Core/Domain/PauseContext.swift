import Foundation
import ManagedSettings

nonisolated struct PauseContext: Codable, Hashable, Identifiable {
    let id: UUID
    var pauseRuleID: UUID
    var appID: AppIdentity.ID
    /// The app's own token, so anything showing this request can draw its real icon.
    /// An AppIdentity rebuilt from appID alone has no token and falls back to a
    /// placeholder square.
    var applicationToken: ApplicationToken?
    /// Every app this release covers. Normally just `appID`, but the unlock flow's
    /// "all apps" choice releases the whole set the routine is holding shut, and an
    /// allowance that can only name one app cannot express that.
    var releasedApplications: Set<AppIdentity.ID>
    var displayName: String
    var allowanceDuration: TimeInterval
    var steps: [PauseStep]
    var requestedAt: Date
    var activeRoutineID: UUID?
    /// The limit rule this unlock is being granted against, when one is what put the app
    /// behind the shield. Carried so whoever grants the allowance can charge it to the
    /// right counter -- an open count is only spent once the unlock is actually given,
    /// not when the shield's button is pressed and the flow then abandoned.
    var limitRuleID: UUID?
    var source: PauseSource

    init(
        id: UUID = UUID(),
        pauseRuleID: UUID,
        appID: AppIdentity.ID,
        applicationToken: ApplicationToken? = nil,
        releasedApplications: Set<AppIdentity.ID> = [],
        displayName: String,
        allowanceDuration: TimeInterval,
        steps: [PauseStep],
        requestedAt: Date = Date(),
        activeRoutineID: UUID? = nil,
        limitRuleID: UUID? = nil,
        source: PauseSource
    ) {
        self.id = id
        self.pauseRuleID = pauseRuleID
        self.appID = appID
        self.applicationToken = applicationToken
        // Defaults to the single app it names, so every existing caller keeps its
        // meaning without saying anything new.
        self.releasedApplications = releasedApplications.isEmpty ? [appID] : releasedApplications
        self.displayName = displayName
        self.allowanceDuration = allowanceDuration
        self.steps = steps
        self.requestedAt = requestedAt
        self.activeRoutineID = activeRoutineID
        self.limitRuleID = limitRuleID
        self.source = source
    }
}

nonisolated enum PauseSource: String, Codable, Hashable {
    case shieldAction
    case notification
    case deepLink
    /// Started inside Lockty, from the unlock flow.
    case app
    case development
}

nonisolated struct PendingPauseContext: Codable, Hashable, Identifiable {
    let id: UUID
    var context: PauseContext
    var expiresAt: Date
    var idempotencyKey: String

    init(
        id: UUID = UUID(),
        context: PauseContext,
        expiresAt: Date,
        idempotencyKey: String
    ) {
        self.id = id
        self.context = context
        self.expiresAt = expiresAt
        self.idempotencyKey = idempotencyKey
    }

    var isValid: Bool {
        Date() < expiresAt
    }
}

nonisolated struct ActivePauseAllowance: Codable, Hashable, Identifiable {
    let id: UUID
    var context: PauseContext
    var startedAt: Date
    var expiresAt: Date

    init(id: UUID = UUID(), context: PauseContext, startedAt: Date, expiresAt: Date) {
        self.id = id
        self.context = context
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Everything this allowance is currently releasing.
    var releasedApplications: Set<AppIdentity.ID> {
        context.releasedApplications.isEmpty ? [context.appID] : context.releasedApplications
    }
}
