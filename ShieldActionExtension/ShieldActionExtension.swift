import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    private let appGroupStore = AppGroupStore()
    private let selectionStore = ScreenTimeSelectionStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, applicationToken: application, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    private func handle(
        action: ShieldAction,
        applicationToken: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)

        case .secondaryButtonPressed:
            guard let snapshot = resolvePauseRule(for: applicationToken) else {
                completionHandler(.close)
                return
            }
            writePendingPause(snapshot: snapshot)
            completionHandler(.defer)

        default:
            completionHandler(.close)
        }
    }

    private func resolvePauseRule(for token: ApplicationToken) -> PauseRuleSnapshot? {
        guard let ruleID = selectionStore.pauseRuleID(matching: token) else {
            return nil
        }

        return appGroupStore.loadPauseRuleSnapshots().first(where: { $0.id == ruleID && $0.isEnabled })
    }

    private func writePendingPause(snapshot: PauseRuleSnapshot) {
        let context = PauseContext(
            pauseRuleID: snapshot.id,
            appID: snapshot.application.id,
            displayName: snapshot.application.displayName,
            allowanceDuration: snapshot.allowanceDuration,
            steps: snapshot.steps,
            source: .shieldAction
        )
        let pendingContext = PendingPauseContext(
            context: context,
            expiresAt: Date().addingTimeInterval(10 * 60),
            idempotencyKey: context.id.uuidString
        )
        let event = PendingSystemEvent(
            source: .shieldAction,
            payload: .pauseRequested(context),
            expiresAt: pendingContext.expiresAt,
            idempotencyKey: pendingContext.idempotencyKey
        )

        try? AppGroupStore().updateRuntimeState { state in
            state.pendingPause = pendingContext
            state.pendingEvents.append(event)
        }
    }
}
