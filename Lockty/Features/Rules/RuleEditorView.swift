import Combine
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
final class RuleEditorViewModel: ObservableObject {
    let editingID: UUID
    let draftID: UUID

    @Published var name = ""
    @Published var kind: RuleKind?
    @Published var isEnabled = true
    @Published var maximumOpens = 10
    @Published var openCountWindowHours = 24
    @Published var maximumDailyMinutes = 30
    @Published var dailyResetPeriod: RuleResetPeriod = .daily
    @Published var maximumSessionMinutes = 5
    @Published var maximumBreaks = 0
    /// Adult content, purchases, installing apps. The same three a routine offers: a
    /// rule is a block like any other, and a limit that shuts an app while leaving the
    /// App Store open is the same half-measure there as anywhere else.
    @Published var contentRestrictions: ContentRestrictions = .none
    @Published var maximumBreakMinutes = 5
    @Published var minimumBreakIntervalMinutes = 60
    @Published var breakResetPeriod: RuleResetPeriod = .daily
    @Published var requiredFrictionID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var appGroups: [LocktySelectableAppGroup] = []
    @Published var selectedAppGroupIDs: Set<UUID> = []
    @Published private(set) var selectionPreview = FamilyActivitySelection()
    @Published private(set) var selectedApplicationCount = 0
    @Published private(set) var frictions: [Friction] = []

    private let repository: RuleRepository
    /// So a hold takes effect at the moment it is taken.
    ///
    /// Holding a rule wrote the hold and stopped there. The shield is applied from the
    /// stored rules and nothing recomputed it, so the app stayed shut until something
    /// else happened to touch the policy -- a rule "paused" that went on blocking.
    private let pauseEngine: PauseEngine
    /// Its own handle on the shared container. The store is a path and a coder -- it
    /// holds nothing -- so one made here is the same store as any other.
    private let appGroupStore = AppGroupStore()
    private let selectionStore: ScreenTimeSelectionStore
    private let frictionRepository: FrictionRepository
    private let appGroupRepository: UserAppGroupRepository
    let toastCenter: LocktyToastCenter
    private let initialRuleID: UUID?
    private var hasLoaded = false
    private var createdAt: Date
    private var baseline: Snapshot?

    private struct Snapshot: Equatable {
        var name: String
        var kind: RuleKind?
        var isEnabled: Bool
        var maximumOpens: Int
        var openCountWindowHours: Int
        var maximumDailyMinutes: Int
        var dailyResetPeriod: RuleResetPeriod
        var maximumSessionMinutes: Int
        var maximumBreaks: Int
        var maximumBreakMinutes: Int
        var minimumBreakIntervalMinutes: Int
        var breakResetPeriod: RuleResetPeriod
        var requiredFrictionID: UUID?
        var selectedApplicationCount: Int
        var selectedAppGroupIDs: Set<UUID>
    }

    init(
        ruleID: UUID?,
        draftID: UUID,
        repository: RuleRepository,
        selectionStore: ScreenTimeSelectionStore,
        frictionRepository: FrictionRepository,
        appGroupRepository: UserAppGroupRepository,
        toastCenter: LocktyToastCenter,
        pauseEngine: PauseEngine
    ) {
        self.pauseEngine = pauseEngine
        self.initialRuleID = ruleID
        self.editingID = ruleID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        self.frictionRepository = frictionRepository
        self.appGroupRepository = appGroupRepository
        self.toastCenter = toastCenter
        createdAt = Date()
    }

    var isCreating: Bool { initialRuleID == nil }
    var breaksAllowed: Bool { maximumBreaks > 0 }

    var selectedFriction: Friction? {
        requiredFrictionID.flatMap { id in
            frictions.first { $0.id == id }
        }
    }

    var hasChanges: Bool {
        guard let baseline else { return false }
        return snapshot != baseline
    }

    var draftSelectionScope: ScreenTimeSelectionScope {
        .rule(draftID)
    }

    private var persistedSelectionScope: ScreenTimeSelectionScope {
        .rule(editingID)
    }

    private var snapshot: Snapshot {
        Snapshot(
            name: name,
            kind: kind,
            isEnabled: isEnabled,
            maximumOpens: maximumOpens,
            openCountWindowHours: openCountWindowHours,
            maximumDailyMinutes: maximumDailyMinutes,
            dailyResetPeriod: dailyResetPeriod,
            maximumSessionMinutes: maximumSessionMinutes,
            maximumBreaks: maximumBreaks,
            maximumBreakMinutes: maximumBreakMinutes,
            minimumBreakIntervalMinutes: minimumBreakIntervalMinutes,
            breakResetPeriod: breakResetPeriod,
            requiredFrictionID: requiredFrictionID,
            selectedApplicationCount: selectedApplicationCount,
            selectedAppGroupIDs: selectedAppGroupIDs
        )
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await loadFrictions()
        await loadAppGroups()

        guard let initialRuleID else {
            try? selectionStore.remove(scope: draftSelectionScope)
            refreshSelectionState()
            captureBaseline()
            return
        }

        guard let rule = try? await repository.rule(id: initialRuleID) else {
            refreshSelectionState()
            captureBaseline()
            return
        }

        createdAt = rule.createdAt
        name = rule.name
        kind = rule.kind
        isEnabled = rule.isEnabled
        maximumOpens = Self.clampedOpenCount(rule.openCountLimitConfiguration?.maximumOpens ?? 10)
        openCountWindowHours = rule.openCountLimitConfiguration?.windowHours ?? 24
        maximumDailyMinutes = rule.dailyUsageLimitConfiguration?.maximumMinutesPerDay ?? 30
        dailyResetPeriod = rule.dailyUsageLimitConfiguration?.resetPeriod ?? .daily
        maximumSessionMinutes = rule.sessionDurationLimitConfiguration?.maximumMinutesPerSession ?? 5
        maximumBreaks = rule.breakPolicy.maximumBreaks
        contentRestrictions = rule.contentRestrictions
        maximumBreakMinutes = max(rule.breakPolicy.durationMinutes ?? 5, 1)
        minimumBreakIntervalMinutes = max(rule.breakPolicy.cooldownMinutes, 1)
        breakResetPeriod = rule.breakPolicy.resetPeriod
        requiredFrictionID = rule.breakPolicy.requiredFrictionID
        selectedAppGroupIDs = rule.appGroupIDs.intersection(Set(appGroups.map(\.id)))
        if let selection = try? selectionStore.load(scope: persistedSelectionScope) {
            try? selectionStore.save(selection, scope: draftSelectionScope)
        } else {
            try? selectionStore.remove(scope: draftSelectionScope)
        }
        refreshSelectionState()
        captureBaseline()
        refreshPauseState()
    }

    func loadFrictions() async {
        let loaded = await frictionRepository.frictions()
        withAnimation(.smooth(duration: 0.24)) {
            frictions = loaded.filter(\.isEnabled)
        }
    }

    func captureBaseline() {
        baseline = snapshot
    }

    func refreshSelectionState() {
        do {
            let selection = try selectionStore.load(scope: draftSelectionScope)
            selectionPreview = selection
            selectedApplicationCount = selection.applicationTokens.count + selection.categoryTokens.count
        } catch {
            selectionPreview = FamilyActivitySelection()
            selectedApplicationCount = 0
            errorMessage = error.localizedDescription
        }
    }

    func replaceSelection(_ selection: FamilyActivitySelection) {
        var normalized = selection
        normalized.webDomainTokens = []
        selectionPreview = normalized
        selectedApplicationCount = normalized.applicationTokens.count + normalized.categoryTokens.count
        do {
            try selectionStore.save(normalized, scope: draftSelectionScope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setKind(_ nextKind: RuleKind) {
        kind = nextKind
        if nextKind != .schedule, requiredFrictionID == nil {
            requiredFrictionID = frictions.first?.id
        }
    }

    func setBreaksAllowed(_ isAllowed: Bool) {
        guard isAllowed else {
            maximumBreaks = 0
            requiredFrictionID = nil
            return
        }

        if maximumBreaks <= 0 {
            maximumBreaks = 2
        }
        if requiredFrictionID == nil {
            requiredFrictionID = frictions.first?.id
        }
    }

    func save() async -> Bool {
        guard let kind else {
            errorMessage = "Choose a rule type."
            return false
        }
        guard kind != .schedule else {
            errorMessage = "Schedule rules use the routine editor."
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Rule name is required."
            return false
        }

        let selection = selectionPreview
        // Apps, and only apps. A limit counts minutes and pickups, and those are reported
        // per app: a category or a group is a set that can grow behind the rule's back,
        // so "30 minutes a day" would quietly start counting something it was never
        // pointed at. The picker no longer offers either; this is the guard that means an
        // older rule cannot save one through the back door.
        guard !selection.applicationTokens.isEmpty else {
            errorMessage = "Select at least one app."
            return false
        }

        // A rule that names an app nothing may block is a rule that contradicts itself:
        // it would save, and then the shield would exempt the very app it was built
        // around. Refused here rather than silently doing nothing at runtime.
        let alwaysAllowed = (try? selectionStore.load(scope: .alwaysAllowed))?.applicationTokens ?? []
        let conflicting = selection.applicationTokens.intersection(alwaysAllowed)
        if !conflicting.isEmpty {
            toastCenter.show(
                .blockedAppIsAlwaysAllowed(
                    names: conflicting.map { AppIdentity(token: $0).displayName }
                )
            )
            return false
        }

        if breaksAllowed && requiredFrictionID == nil {
            errorMessage = "Choose a friction for this break."
            return false
        }

        let rule = Rule(
            id: editingID,
            name: trimmedName,
            isEnabled: isEnabled,
            kind: kind,
            appGroupIDs: [],
            blockedApplications: Set(selection.applicationTokens.map(AppIdentity.ID.init(token:))),
            contentRestrictions: contentRestrictions,
            openCountLimitConfiguration: kind == .openCountLimit
                ? OpenCountLimitRuleConfiguration(
                    maximumOpens: Self.clampedOpenCount(maximumOpens),
                    windowHours: openCountWindowHours
                )
                : nil,
            dailyUsageLimitConfiguration: kind == .dailyUsageLimit
                ? DailyUsageLimitRuleConfiguration(
                    maximumMinutesPerDay: maximumDailyMinutes,
                    resetPeriod: dailyResetPeriod
                )
                : nil,
            sessionDurationLimitConfiguration: kind == .sessionDurationLimit
                ? SessionDurationLimitRuleConfiguration(
                    maximumMinutesPerSession: maximumSessionMinutes
                )
                : nil,
            breakPolicy: RuleBreakPolicy(
                isAllowed: breaksAllowed,
                durationMinutes: breaksAllowed ? maximumBreakMinutes : nil,
                maximumBreaks: breaksAllowed ? maximumBreaks : 0,
                resetPeriod: breakResetPeriod,
                cooldownMinutes: breaksAllowed ? minimumBreakIntervalMinutes : 0,
                allowedTriggers: breaksAllowed ? [.manual] : [],
                requiredFrictionID: breaksAllowed ? requiredFrictionID : nil,
                frictionPolicy: selectedFriction?.flow.policy ?? .off
            ),
            createdAt: createdAt,
            updatedAt: Date()
        )

        do {
            try selectionStore.save(selection, scope: persistedSelectionScope)
            try? selectionStore.remove(scope: draftSelectionScope)
            try await repository.save(rule)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Whether this limit has already stopped something today.
    ///
    /// While it has, the rule is sealed: it cannot be edited, deleted or held. That is the
    /// whole of what a limit is -- a decision made in advance about a moment you knew you
    /// would argue with. A limit you can delete the second it fires is a limit that only
    /// applies when you already agree with it, and every escape hatch here is the same
    /// hatch: edit it to a bigger number, hold it until tomorrow, or remove it outright.
    ///
    /// It seals for the day, not forever. Tomorrow the record is a fresh one and the rule
    /// is yours again.
    @Published private(set) var isSpentToday = false

    /// When the hold on this rule ends, or nil when it is not on hold.
    @Published private(set) var pausedUntil: Date?

    func refreshPauseState() {
        pausedUntil = appGroupStore.loadRulePauseState().pauseEnd(for: editingID)
        refreshSpentState()
    }

    func refreshSpentState() {
        guard !isCreating, let kind, kind != .schedule else {
            isSpentToday = false
            return
        }

        let stored = appGroupStore.loadStoredRules().first { $0.id == editingID }
        let enforcement = appGroupStore.loadRuleEnforcementState()
        let isBlocking = stored?.isShielding(given: enforcement) ?? false

        // Sealed only when there is genuinely no way through it.
        //
        // A limit that has fired but still offers unlocks is not a wall -- the way past it
        // is the friction it asks for, which is the whole point of having one. Sealing it
        // there would take away the editing *and* leave the unlock, which is the worst of
        // both: an escape hatch that works and a rule you cannot touch.
        //
        // With no unlocks allowed, or none left, or a strict rule that refuses them, the
        // limit *is* the wall -- and then editing, deleting or holding it are simply three
        // more doors out of a room that was locked on purpose.
        let allowsUnlock = (stored?.breakPolicy.maximumBreaks ?? 0) > 0
        isSpentToday = isBlocking && !allowsUnlock
    }

    /// What the screen says when it refuses.
    var spentReason: String {
        "This limit has already stopped you today. It can be changed again tomorrow."
    }

    func pause(for duration: RulePauseDuration) {
        try? appGroupStore.updateRulePauseState { state in
            state.pause(editingID, until: Date().addingTimeInterval(duration.duration))
        }
        refreshPauseState()
        applyShields()
    }

    func resume() {
        try? appGroupStore.updateRulePauseState { state in
            state.resume(editingID)
        }
        refreshPauseState()
        applyShields()
    }

    /// Recomputes what is shielded from what is stored now. `loadShieldRules()` already
    /// drops anything on hold, so this is the whole of a hold taking effect -- and of it
    /// ending.
    private func applyShields() {
        Task { await pauseEngine.refreshShields() }
    }

    /// Removes the rule for good.
    ///
    /// Returns whether it went, so the caller only closes the editor on a deletion that
    /// actually happened -- a failure here used to be a screen that dismissed as if all
    /// was well and a rule still sitting in the list behind it.
    func delete() async -> Bool {
        guard !isCreating else { return true }
        do {
            try await repository.delete(id: editingID)
            defer { applyShields() }
            // The selection the rule was blocking goes with it. Left behind it is a
            // record nothing points at, and the next rule to reuse the id -- ids are
            // reused when a routine bridges to a rule -- would inherit its apps.
            try? selectionStore.remove(scope: .rule(editingID))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func clampedOpenCount(_ value: Int) -> Int {
        min(max(value, 1), 10)
    }

    /// Names the rule after the kind just chosen.
    ///
    /// Only on a new rule with an untouched name: the kind can be picked more than once
    /// on the way through, and re-generating over a name the user had typed would throw
    /// their words away. Called after the choice rather than at load, because at load
    /// there is no kind yet to name it after.
    func generateNameIfNeeded() async {
        guard isCreating, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kind
        else { return }

        let existing = (try? await repository.rules())?.map(\.name) ?? []
        name = LocktyGeneratedName.rule(kind: kind, existing: existing)
        captureBaseline()
    }

    func discardDraft() {
        try? selectionStore.remove(scope: draftSelectionScope)
    }

    private func loadAppGroups() async {
        let loadedGroups = await appGroupRepository.appGroups()
        let suggestedGroups = ReusableAppGroupDefinition.selectableAsRestriction.map { definition in
            let selection = (try? selectionStore.load(scope: definition.selectionScope)) ?? FamilyActivitySelection()
            return LocktySelectableAppGroup(
                id: definition.id,
                name: definition.name,
                itemCount: selection.applicationTokens.count + selection.categoryTokens.count,
                tokens: selection.applicationTokens.stablePrefix(selection.applicationTokens.count)
            )
        }
        let suggestedGroupIDs = Set(suggestedGroups.map(\.id))
        let userGroups = loadedGroups.filter { !suggestedGroupIDs.contains($0.id) }.map { group in
            let selection = (try? selectionStore.load(scope: .appGroup(group.id))) ?? FamilyActivitySelection()
            return LocktySelectableAppGroup(
                id: group.id,
                name: group.name,
                itemCount: selection.applicationTokens.count + selection.categoryTokens.count,
                tokens: selection.applicationTokens.stablePrefix(selection.applicationTokens.count)
            )
        }
        let selectableGroups = suggestedGroups + userGroups
        let availableIDs = Set(selectableGroups.map(\.id))
        withAnimation(.smooth(duration: 0.24)) {
            appGroups = selectableGroups
            selectedAppGroupIDs = selectedAppGroupIDs.intersection(availableIDs)
        }
    }
}

private enum RuleEditorLocalSheet: String, Identifiable {
    case apps
    case breakSettings
    case delete
    /// Putting the rule on hold for a while.
    case hold

    var id: String { rawValue }
}

struct RuleEditorView: View {
    @StateObject private var viewModel: RuleEditorViewModel
    let makeScheduleRuleEditor: (@escaping () -> Void) -> AnyView
    let isEmbeddedInParentSheet: Bool
    let onReturnToParent: (() -> Void)?
    let onCloseEditor: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: RuleEditorLocalSheet?
    /// Where the hold wheel sits. A day: long enough to be a real break from a rule,
    /// short enough that nobody has to remember they did it.
    @State private var holdDuration: RulePauseDuration = .oneDay
    @State private var isNaming = false
    /// A new rule goes straight to its form -- there is nothing to preview yet.
    @State private var isEditing: Bool
    /// Whether the kind screen is showing the second question -- which sort of limit.
    @State private var isChoosingLimitKind = false
    @State private var isShowingKindChoice: Bool
    /// What a discard confirmation, if one is up, is about to throw away.
    @State private var pendingDiscard: LocktyDiscardIntent?
    @FocusState private var isNameFieldFocused: Bool
    @State private var isGoingBack = false

    init(
        viewModel: RuleEditorViewModel,
        makeScheduleRuleEditor: @escaping (@escaping () -> Void) -> AnyView,
        isEmbeddedInParentSheet: Bool = false,
        onReturnToParent: (() -> Void)? = nil,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.makeScheduleRuleEditor = makeScheduleRuleEditor
        self.isEmbeddedInParentSheet = isEmbeddedInParentSheet
        self.onReturnToParent = onReturnToParent
        self.onCloseEditor = onCloseEditor
        _isShowingKindChoice = State(initialValue: viewModel.isCreating)
        _isEditing = State(initialValue: viewModel.isCreating)
    }

    private var sheetAnimation: Animation { .snappy(duration: 0.4, extraBounce: 0.02) }
    private var cardRadius: CGFloat { 22 }

    private var chromeID: String {
        "\(contentID)-\(viewModel.name)-\(viewModel.kind?.rawValue ?? "none")"
    }

    private var contentID: String {
        if isShowingKindChoice { return isChoosingLimitKind ? "kind-choice-limit" : "kind-choice" }
        // A spent limit draws a different screen -- no pencil, no trash, a sentence where
        // the hold button was -- so the chrome has to be re-taken for it.
        //
        // This line read `"\(contentID)-spent"`: the property calling itself, forever,
        // until the stack ran out. Opening a limit that had already fired was the only way
        // to reach it, which is exactly the sheet that was crashing.
        if viewModel.isSpentToday { return "reading-spent" }
        if viewModel.kind == .schedule { return "schedule" }
        if let activeSheet { return activeSheet.id }
        if isNaming { return "naming" }
        return isEditing ? "editor" : "reading"
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity),
            removal: .move(edge: isGoingBack ? .trailing : .leading)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity)
        )
    }

    var body: some View {
        Group {
            if isEmbeddedInParentSheet {
                rootContent
            } else {
                LocktyDynamicSheet(animation: sheetAnimation) {
                    rootContent
                }
            }
        }
        .locktyInteractiveDismiss(
            blocked: isDiscardable && viewModel.hasChanges && !isShowingKindChoice && activeSheet == nil,
            onAttempt: requestClose
        )
        .confirmationDialog(
            "Discard changes?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDiscard
        ) { intent in
            Button("Discard", role: .destructive) {
                pendingDiscard = nil
                switch intent {
                case .leave: returnToParentOrDismiss()
                case .back: returnToKindChoice()
                }
            }
            Button("Keep editing", role: .cancel) { pendingDiscard = nil }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: isNaming, initial: false) { _, newValue in
            guard newValue else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                isNameFieldFocused = true
            }
        }
        .alert(
            "Could not save rule",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            if isShowingKindChoice {
                // Two questions, one chrome.
                //
                // They were two branches with a chrome modifier each, and that is what
                // broke the back button: the chrome is registered by whichever screen
                // last appeared and cleared by whichever last disappeared, so on the way
                // back the leaving screen's clear landed after the arriving screen's
                // register and the bar was left holding the close button. Pressing back
                // closed the sheet, exactly as it looked.
                //
                // One chrome that changes with the step, and the contents move underneath
                // it -- which is also what makes the movement read as going a step deeper.
                ZStack {
                    if isChoosingLimitKind {
                        limitKindChoiceContent
                            .transition(screenTransition)
                    } else {
                        kindChoiceContent
                            .transition(screenTransition)
                    }
                }
                .geometryGroup()
                .locktyDynamicSheetChrome(id: chromeID) {
                    chromeTitleText(isChoosingLimitKind ? "Create Limit" : "Create Rule")
                } leading: {
                    kindChoiceLeading
                } trailing: {
                    Color.clear.frame(width: 44, height: 44)
                }
                .transition(screenTransition)
            } else if viewModel.kind == .schedule {
                // Where its back button goes depends on how you got here. Creating one,
                // there is a step behind it -- the kind you picked -- and a chevron is
                // right. Opening one that already exists, there is nothing behind it but
                // the way out, and the chevron was taking people from a mode they were
                // reading into the screen for making a new one.
                makeScheduleRuleEditor { scheduleReturnAction() }
                    .geometryGroup()
                    .transition(screenTransition)
            } else if isEditing || activeSheet != nil {
                // `activeSheet` too, and this is the whole bug it fixes: the read-only
                // screen drew the preview and nothing else, so a child sheet opened from
                // it -- delete, the hold -- set the state and then never appeared. The
                // form's scaffold is what honours `activeSheet`.
                editorScaffold
                    .geometryGroup()
                    .transition(screenTransition)
            } else {
                readOnlyScaffold
                    .geometryGroup()
                    .transition(screenTransition)
            }
        }
        .geometryGroup()
    }

    /// The summary, wearing the same bar the form does.
    private var readOnlyScaffold: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            RulePreviewContent(
                onEdit: { enterEditingFlow() },
                viewModel: viewModel,
                applicationTokens: previewTokens
            )

            // Pausing is not editing: you are not changing what the rule is, you are
            // saying not this week. So it lives on the screen you read the rule on,
            // exactly as a routine's does.
            if !viewModel.isCreating {
                if viewModel.isSpentToday {
                    // Not a disabled button: a control greyed out invites you to work out
                    // how to enable it. The sentence is the answer, and there is nothing
                    // to press.
                    Text(viewModel.spentReason)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LocktySpacing.screenInset)
                        .transition(.blurReplace)
                } else {
                    holdButton
                        .padding(.horizontal, LocktySpacing.screenInset)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .locktyDynamicSheetChrome(id: chromeID) {
            chromeCenter
        } leading: {
            chromeLeading
        } trailing: {
            chromeTrailing
        }
    }

    private var previewTokens: [ApplicationToken] {
        let tokens = viewModel.selectionPreview.applicationTokens
        return tokens.stablePrefix(tokens.count)
    }

    private var editorScaffold: some View {
        sheetContent
            .locktyDynamicSheetChrome(id: chromeID) {
                chromeCenter
            } leading: {
                chromeLeading
            } trailing: {
                chromeTrailing
            }
    }

    @ViewBuilder
    private var chromeCenter: some View {
        switch activeSheet {
        case .apps:
            chromeTitleText("Selected")
        case .breakSettings:
            chromeTitleText("Break")
        case .delete:
            chromeTitleText("Delete")
        case .hold:
            chromeTitleText("Pause")
        case nil:
            // The generated name, not "New Rule": the rule already has a name by the
            // time this is on screen, and showing a placeholder over a filled field
            // would be the header disagreeing with the form under it.
            if isNaming {
                chromeTitleText("Name")
            } else if !isEditing {
                // Nothing while reading. The summary under this bar carries the icon and
                // the name at full size, so a smaller copy directly above them is the
                // same thing said twice.
                EmptyView()
            } else {
                chromeTitleText(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rule" : viewModel.name)
            }
        }
    }

    @ViewBuilder
    private var chromeLeading: some View {
        if activeSheet != nil {
            LocktyDynamicSheetBarButton(action: closeChildSheet) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else if isNaming {
            LocktyDynamicSheetBarButton(action: exitNaming) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else if isEditing && !viewModel.isCreating {
            LocktyDynamicSheetBarButton(action: returnToReading) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else if viewModel.isCreating {
            // Reached by picking a kind on "Create Rule", so there is a step behind this
            // one. A chevron says that; an X claimed the only way out was to abandon the
            // whole thing, when going back one screen is right there.
            LocktyDynamicSheetBarButton(action: requestReturnToKindChoice) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else {
            // Opened straight onto an existing rule: nothing behind it but the way out.
            LocktyDynamicSheetBarButton(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }

    @ViewBuilder
    private var chromeTrailing: some View {
        // Nothing at all on the one that commits by being held. A tick beside "Delete
        // this rule?" is a second way to say yes sitting where the way to say no should
        // be.
        if activeSheet == .delete || activeSheet == .hold {
            Color.clear
                .frame(width: 44, height: 44)
        } else if activeSheet != nil {
            LocktyDynamicSheetBarButton(action: closeChildSheet) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .medium))
            }
        } else if isNaming {
            LocktyDynamicSheetBarButton(action: exitNaming) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
            // The trash only while editing. Reading a rule is not the moment to be one
            // tap from destroying it, and the pencil is right there -- so it sits beside
            // the pencil on the screen where you are already changing things.
            HStack(spacing: LocktySpacing.sm) {
                // Neither while the limit is spent. A rule you can delete the moment it
                // stops you is a rule that only applies while you agree with it.
                if isEditing, !viewModel.isCreating, !viewModel.isSpentToday {
                    LocktyDynamicSheetBarButton(action: { openChildSheet(.delete) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LocktyColors.error)
                    }
                }

                if !viewModel.isSpentToday {
                    LocktyDynamicSheetBarButton(action: enterEditingFlow) {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .medium))
                    }
                } else {
                    // Its place kept, so the bar does not shuffle when the rule seals.
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        ZStack {
            switch activeSheet {
            case .apps:
                selectionScreen
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            case .breakSettings:
                breakSettingsScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case .delete:
                deleteScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case .hold:
                holdScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case nil:
                if isNaming {
                    namingContent
                        .geometryGroup()
                        .transition(screenTransition)
                } else {
                    editorContent
                        .geometryGroup()
                        .transition(screenTransition)
                }
            }
        }
        .geometryGroup()
    }

    /// The two things a rule can be.
    ///
    /// A schedule or a limit, and nothing else. The four kinds were four tiles here, but
    /// three of them were the same answer at different granularities -- and one of them,
    /// the cap on a single sitting, is not something you write down at all: it is decided
    /// on the spot from the plus in the tab bar, which is what that button is for.
    ///
    /// "Limit" is a door rather than an answer: which sort of limit is the next question,
    /// asked on its own screen.
    private var kindChoiceContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LocktySpacing.md),
                    GridItem(.flexible(), spacing: LocktySpacing.md)
                ],
                spacing: LocktySpacing.md
            ) {
                kindTile(kind: .schedule, subtitle: "Scheduled blocking")

                limitTile
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, LocktySpacing.lg)
        }
    }

    /// Which sort of limit: by how many times something is opened, or by how long it is
    /// used. Both are "so much a day"; what differs is what is being counted.
    private var limitKindChoiceContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LocktySpacing.md),
                    GridItem(.flexible(), spacing: LocktySpacing.md)
                ],
                spacing: LocktySpacing.md
            ) {
                kindTile(kind: .openCountLimit, subtitle: "So many opens a day")
                kindTile(kind: .dailyUsageLimit, subtitle: "So much time a day")
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, LocktySpacing.lg)
        }
    }

    /// The door to the second question, drawn as the kinds are.
    private var limitTile: some View {
        Button {
            isGoingBack = false
            withAnimation(sheetAnimation) { isChoosingLimitKind = true }
        } label: {
            CardView(radius: LocktyRadius.large, interactive: true, height: 188) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: 0)

                    Text("Limit")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Text("By opens or by time")
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }

    /// Close on the first question, back on the second.
    @ViewBuilder
    private var kindChoiceLeading: some View {
        if isChoosingLimitKind {
            LocktyDynamicSheetBarButton(action: returnToKindChoiceRoot) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
            }
        } else {
            LocktyDynamicSheetBarButton(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }

    /// Where the schedule editor's back button goes.
    ///
    /// Extracted rather than written inline: a ternary of two closures inside a view
    /// builder is more than the type checker will sit through.
    private func scheduleReturnAction() {
        if viewModel.isCreating {
            returnToKindChoice()
        } else {
            requestClose()
        }
    }

    /// Back one step, from the limits to the two kinds.
    private func returnToKindChoiceRoot() {
        isGoingBack = true
        withAnimation(sheetAnimation) { isChoosingLimitKind = false }
    }

    // The cap on one sitting, as a rule you write down. Kept, not used: it is decided on
    // the spot from the plus in the tab bar now.
    //
    //  kindTile(kind: .sessionDurationLimit, subtitle: "Session time limit")

    private func kindTile(kind: RuleKind, subtitle: String) -> some View {
        Button {
            viewModel.setKind(kind)
            // Named after the kind the moment it is chosen. There is nothing to name a
            // rule after before this point, which is why it does not happen at load.
            Task { await viewModel.generateNameIfNeeded() }
            if kind == .schedule {
                openSchedule()
            } else {
                isGoingBack = false
                withAnimation(sheetAnimation) {
                    isShowingKindChoice = false
                    isNaming = false
                }
            }
        } label: {
            CardView(radius: LocktyRadius.large, interactive: true, height: 188) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: symbolName(for: kind))
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: 0)

                    Text(displayName(for: kind))
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(subtitle)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }

    private var namingContent: some View {
        VStack(spacing: LocktySpacing.lg) {
            TextField("Name", text: $viewModel.name)
                .focused($isNameFieldFocused)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.lg)
                .padding(.vertical, LocktySpacing.md)
                .background(Capsule(style: .continuous).fill(LocktyColors.elevatedBackground))

            Text(viewModel.kind.map(displayName(for:)) ?? "")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.vertical, LocktySpacing.lg)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(conditionSectionTitle, systemImage: conditionSectionIcon)

            conditionCard

            sectionHeading("Blocked Apps", systemImage: "lock.shield")

            appsRow

            LocktyHoldButton(title: viewModel.isCreating ? "Hold to confirm" : "Hold to save") {
                Task {
                    if await viewModel.save() {
                        dismissEditor()
                    }
                }
            }
            .padding(.top, LocktySpacing.sm)

            // Only on a rule that exists. A rule being created has nothing to delete, and
            // the way out of it is the same X every other new thing has.
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Puts the rule on hold, or lets it go again.
    ///
    /// Every kind, not only schedules. A limit is as worth suspending as a routine --
    /// a day off does not mean deleting the count of opens you want back on Monday.
    private var holdButton: some View {
        Button {
            if viewModel.pausedUntil != nil {
                viewModel.resume()
            } else {
                openChildSheet(.hold)
            }
        } label: {
            HStack(spacing: LocktySpacing.sm) {
                Image(systemName: viewModel.pausedUntil == nil ? "pause.circle" : "play.circle")
                    .font(.system(size: 15, weight: .medium))

                Text(holdButtonTitle)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
            }
            .foregroundStyle(LocktyColors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
        .tappable()
    }

    private var holdButtonTitle: String {
        guard let until = viewModel.pausedUntil else { return "Pause rule" }
        return "Paused until \(LocktyDateFormatting.shortDayAndTime(until)) · Resume"
    }

    private var holdScreen: some View {
        VStack(spacing: LocktySpacing.xl) {
            VStack(spacing: LocktySpacing.sm) {
                Text("Pause for how long?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)

                Text("The rule stops counting and stops blocking while it is paused. It comes back on its own at the end of the hold -- there is nothing to switch back on.")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("", selection: $holdDuration) {
                ForEach(RulePauseDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 180)
            .clipped()

            Text("Until \(LocktyDateFormatting.shortDayAndTime(Date().addingTimeInterval(holdDuration.duration)))")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            LocktyHoldButton(title: "Hold to pause", systemImage: "pause.fill") {
                viewModel.pause(for: holdDuration)
                closeChildSheet()
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.xl)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity)
    }

    private var deleteScreen: some View {
        LocktyDestructiveConfirmation(
            title: "Delete this rule?",
            message: deleteMessage,
            onConfirm: {
                Task {
                    if await viewModel.delete() {
                        dismissEditor()
                    }
                }
            },
            onCancel: closeChildSheet
        )
    }

    /// What deleting actually costs, said plainly and differently per kind: a schedule
    /// stops running, a limit stops counting.
    private var deleteMessage: String {
        let name = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = name.isEmpty ? "This rule" : "\u{201C}\(name)\u{201D}"

        switch viewModel.kind {
        case .schedule:
            return "\(subject) will stop running, and the apps it blocks will be free at its hours. This cannot be undone."
        case .openCountLimit, .dailyUsageLimit, .sessionDurationLimit:
            return "\(subject) will stop counting, and the apps it holds will be free immediately. This cannot be undone."
        case .none:
            return "\(subject) will be removed. This cannot be undone."
        }
    }

    @ViewBuilder
    private var conditionCard: some View {
        VStack(spacing: 0) {
            switch viewModel.kind {
            case .openCountLimit:
                openCountStepperRow(
                    title: "App Opens",
                    subtitle: "Per day",
                    value: Binding(
                        get: { viewModel.maximumOpens },
                        set: { viewModel.maximumOpens = RuleEditorViewModel.clampedOpenCount($0) }
                    )
                )
            case .dailyUsageLimit:
                menuRow(
                    title: "Usage Time",
                    valueText: "\(viewModel.maximumDailyMinutes) min",
                    subtitle: "Daily",
                    options: Array(stride(from: 5, through: 360, by: 5)),
                    format: { "\($0) min" },
                    selection: Binding(
                        get: { viewModel.maximumDailyMinutes },
                        set: { viewModel.maximumDailyMinutes = $0 }
                    )
                )
            case .sessionDurationLimit:
                menuRow(
                    title: "Session Time",
                    valueText: "\(viewModel.maximumSessionMinutes) min",
                    options: Array(1...120),
                    format: { "\($0) min" },
                    selection: Binding(
                        get: { viewModel.maximumSessionMinutes },
                        set: { viewModel.maximumSessionMinutes = $0 }
                    )
                )
            case .schedule, .none:
                EmptyView()
            }
        }
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var appsRow: some View {
        Button {
            openChildSheet(.apps)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected apps")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(selectionCountText)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .locktyCardBackground(cornerRadius: cardRadius)
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
    }

    private var breakSettingsScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Break policy", systemImage: "figure.walk")

            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow breaks")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(viewModel.breaksAllowed ? "This rule can open a temporary exception after a friction." : "This rule cannot be bypassed.")
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer(minLength: 0)

                LocktySwitch(
                    isOn: Binding(
                        get: { viewModel.breaksAllowed },
                        set: { viewModel.setBreaksAllowed($0) }
                    )
                )
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .locktyCardBackground(cornerRadius: cardRadius)

            if viewModel.breaksAllowed {
                VStack(spacing: 0) {
                    menuRow(
                        title: "Max breaks",
                        valueText: BreakPolicy.label(forMaximumBreaks: viewModel.maximumBreaks),
                        // Unlimited first, since it is the loosest of them and the list
                        // tightens downwards.
                        options: [BreakPolicy.unlimitedBreaks] + Array(1...10),
                        format: BreakPolicy.label(forMaximumBreaks:),
                        selection: Binding(
                            get: { viewModel.maximumBreaks },
                            set: { viewModel.maximumBreaks = $0 }
                        )
                    )

                    dividerInset

                    menuRow(
                        title: "Break duration",
                        valueText: "\(viewModel.maximumBreakMinutes) min",
                        options: Array(1...15),
                        format: { "\($0) min" },
                        selection: Binding(
                            get: { viewModel.maximumBreakMinutes },
                            set: { viewModel.maximumBreakMinutes = $0 }
                        )
                    )

                    dividerInset

                    menuRow(
                        title: "Cooldown",
                        valueText: "\(viewModel.minimumBreakIntervalMinutes) min",
                        options: Array(stride(from: 5, through: 240, by: 5)),
                        format: { "\($0) min" },
                        selection: Binding(
                            get: { viewModel.minimumBreakIntervalMinutes },
                            set: { viewModel.minimumBreakIntervalMinutes = $0 }
                        )
                    )

                    dividerInset

                    resetPeriodRow(selection: $viewModel.breakResetPeriod)
                }
                .locktyCardBackground(cornerRadius: cardRadius)

                sectionHeading("Friction", systemImage: "sparkles.rectangle.stack")

                frictionSelectionCard
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var frictionSelectionCard: some View {
        VStack(spacing: 0) {
            if viewModel.frictions.isEmpty {
                HStack {
                    Text("Create a friction first")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LocktySpacing.md)
                .padding(.vertical, LocktySpacing.md)
            } else {
                ForEach(Array(viewModel.frictions.enumerated()), id: \.element.id) { index, friction in
                    Button {
                        withAnimation(.smooth(duration: 0.24)) {
                            viewModel.requiredFrictionID = friction.id
                        }
                    } label: {
                        HStack(spacing: LocktySpacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friction.name)
                                    .font(.system(.subheadline, design: .default, weight: .regular))
                                    .foregroundStyle(LocktyColors.primaryText)

                                Text("\(friction.steps.count == 1 ? "1 step" : "\(friction.steps.count) steps") · \(friction.summary)")
                                    .font(.system(.footnote, design: .default, weight: .regular))
                                    .foregroundStyle(LocktyColors.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: viewModel.requiredFrictionID == friction.id ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(viewModel.requiredFrictionID == friction.id ? LocktyColors.productive : LocktyColors.secondaryText)
                        }
                        .padding(.horizontal, LocktySpacing.md)
                        .padding(.vertical, LocktySpacing.md)
                    }
                    .buttonStyle(.plain)

                    if index < viewModel.frictions.count - 1 {
                        dividerInset
                    }
                }
            }
        }
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var selectionScreen: some View {
        VStack {
                LocktyActivitySelectionView(
                    title: "Selected",
                    // Apps only, so the button says apps only. It offered "app or
                    // category" over a screen that refuses categories.
                    addLabel: "Add app",
                    selection: Binding(
                        get: { viewModel.selectionPreview },
                        set: { newValue in
                            withAnimation(.smooth(duration: 0.28)) {
                                viewModel.replaceSelection(newValue)
                            }
                        }
                    ),
                    selectedAppGroupIDs: Binding(
                        get: { viewModel.selectedAppGroupIDs },
                        set: { viewModel.selectedAppGroupIDs = $0 }
                    ),
                    blockedDomains: .constant([]),
                    contentRestrictions: Binding(
                        get: { viewModel.contentRestrictions },
                        set: { viewModel.contentRestrictions = $0 }
                    ),
                    rules: .rule,
                    suggestions: [],
                    appGroups: viewModel.appGroups,
                    toastCenter: viewModel.toastCenter,
                    onClose: {},
                    onDone: {}
                )
        }
    }

    private var dividerInset: some View {
        Divider()
            .overlay(LocktyColors.ink(0.10))
            .padding(.leading, 16)
    }

    private var conditionSummary: String {
        switch viewModel.kind {
        case .openCountLimit:
            return "\(viewModel.maximumOpens) opens in \(viewModel.openCountWindowHours)h"
        case .dailyUsageLimit:
            return "\(viewModel.maximumDailyMinutes) minutes per day"
        case .sessionDurationLimit:
            return "\(viewModel.maximumSessionMinutes) minutes per session"
        case .schedule:
            return "Schedule based rule"
        case .none:
            return "Choose a rule type"
        }
    }

    private var conditionSectionTitle: String {
        switch viewModel.kind {
        case .openCountLimit:
            return "Open Count"
        case .dailyUsageLimit:
            return "Daily Usage"
        case .sessionDurationLimit:
            return "Session Duration"
        case .schedule:
            return "Schedule"
        case .none:
            return "Rule"
        }
    }

    private var conditionSectionIcon: String {
        switch viewModel.kind {
        case .openCountLimit:
            return "lock"
        case .dailyUsageLimit:
            return "hourglass"
        case .sessionDurationLimit:
            return "timer"
        case .schedule:
            return "calendar"
        case .none:
            return "line.3.horizontal.decrease.circle"
        }
    }

    private var selectionCountText: String {
        RestrictionSummary.appsCategoriesAndGroups(
            apps: viewModel.selectionPreview.applicationTokens.count,
            categories: viewModel.selectionPreview.categoryTokens.count,
            groups: viewModel.selectedAppGroupIDs.count
        ) ?? "Choose"
    }

    private func displayName(for kind: RuleKind) -> String {
        switch kind {
        case .schedule:
            return "Schedule"
        case .openCountLimit:
            return "Open Count"
        case .dailyUsageLimit:
            return "Daily Usage"
        case .sessionDurationLimit:
            return "Session Duration"
        }
    }

    private func openCountStepperRow(
        title: String,
        subtitle: String,
        value: Binding<Int>
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(subtitle)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    value.wrappedValue -= 1
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LocktyColors.primaryText))
                    .contentShape(Circle())
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .tappable()
            .disabled(value.wrappedValue <= 1)
            .opacity(value.wrappedValue <= 1 ? 0.35 : 1)

            Text("\(value.wrappedValue)")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.24), value: value.wrappedValue)
                .frame(minWidth: 32)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    value.wrappedValue += 1
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LocktyColors.primaryText))
                    .contentShape(Circle())
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .tappable()
            .disabled(value.wrappedValue >= 10)
            .opacity(value.wrappedValue >= 10 ? 0.35 : 1)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
    }

    private func symbolName(for kind: RuleKind) -> String {
        switch kind {
        case .schedule:
            return "calendar"
        case .openCountLimit:
            return "number.circle"
        case .dailyUsageLimit:
            return "hourglass"
        case .sessionDurationLimit:
            return "timer"
        }
    }

    private func menuRow(
        title: String,
        valueText: String,
        subtitle: String? = nil,
        options: [Int],
        format: @escaping (Int) -> String,
        selection: Binding<Int>
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(.smooth(duration: 0.22)) {
                            selection.wrappedValue = option
                        }
                    } label: {
                        if selection.wrappedValue == option {
                            Label(format(option), systemImage: "checkmark")
                        } else {
                            Text(format(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: LocktySpacing.xs) {
                    Text(valueText)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LocktyColors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
    }

    private func resetPeriodRow(selection: Binding<RuleResetPeriod>) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text("Reset")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            HStack(spacing: LocktySpacing.sm) {
                resetChip(title: "Daily", period: .daily, selection: selection)
                resetChip(title: "24h", period: .rolling24Hours, selection: selection)
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
    }

    private func resetChip(
        title: String,
        period: RuleResetPeriod,
        selection: Binding<RuleResetPeriod>
    ) -> some View {
        let isSelected = selection.wrappedValue == period
        return Button {
            withAnimation(.smooth(duration: 0.22)) {
                selection.wrappedValue = period
            }
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(isSelected ? .black : LocktyColors.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? LocktyColors.primaryText : LocktyColors.ink(0.06))
                }
        }
        .buttonStyle(.plain)
    }

    private func summaryCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Text(subtitle)
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private func sectionHeading(_ title: String, systemImage: String) -> some View {
        HStack(spacing: LocktySpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            Text(title)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
        }
    }

    private func chromeTitleText(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
    }

    private func openChildSheet(_ sheet: RuleEditorLocalSheet) {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            activeSheet = sheet
        }
    }

    private func closeChildSheet() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            activeSheet = nil
        }
        viewModel.refreshSelectionState()
    }

    private func openSchedule() {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            isShowingKindChoice = false
            isNaming = false
        }
    }

    /// Back to the kind choice, asking first when there is something to lose.
    ///
    /// Going back a step still throws away what was typed on this one, so it gets the
    /// same confirmation leaving the sheet does -- the answer just lands on the previous
    /// screen instead of outside.
    private func requestReturnToKindChoice() {
        guard viewModel.hasChanges else {
            returnToKindChoice()
            return
        }
        pendingDiscard = .back
    }

    private func returnToKindChoice() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            isShowingKindChoice = true
            isChoosingLimitKind = false
            viewModel.kind = nil
        }
    }

    /// From the summary the pencil opens the form; from the form, the name.
    private func enterEditingFlow() {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            if isEditing {
                isNaming = true
            } else {
                isEditing = true
            }
        }
    }

    private func returnToReading() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            isEditing = false
            isNaming = false
        }
    }

    private func enterNaming() {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            isNaming = true
        }
    }

    private func exitNaming() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            isNaming = false
        }
        isNameFieldFocused = false
    }

    private func dismissEditor() {
        viewModel.discardDraft()
        onCloseEditor()
        dismiss()
    }

    private func returnToParentOrDismiss() {
        viewModel.discardDraft()
        onCloseEditor()
        if let onReturnToParent {
            onReturnToParent()
        } else {
            dismiss()
        }
    }

    /// Whether there is an edit in progress that could be thrown away. The summary is
    /// not one: nothing on it changes the rule.
    private var isDiscardable: Bool {
        isEditing || viewModel.isCreating || isNaming
    }

    private func requestClose() {
        // Never from the summary: reading a rule changes nothing, so there is nothing to
        // discard.
        guard isEditing || viewModel.isCreating || isNaming else {
            returnToParentOrDismiss()
            return
        }

        guard viewModel.hasChanges else {
            returnToParentOrDismiss()
            return
        }
        pendingDiscard = .leave
    }
}
