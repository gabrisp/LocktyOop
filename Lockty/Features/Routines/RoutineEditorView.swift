import FamilyControls
import Combine
import ManagedSettings
import OSLog
import SwiftUI

private let routineEditorLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "routines")

struct EditableRoutineTask: Identifiable, Hashable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String = "") {
        self.id = id
        self.title = title
    }
}

@MainActor
final class RoutineEditorViewModel: ObservableObject {
    let editingID: UUID
    let draftID: UUID

    @Published var name = ""
    /// A new routine already has an icon: leaving it empty meant every screen that
    /// shows one had to invent a fallback, and the icon read as missing rather than as
    /// the one it starts with.
    @Published var icon = RoutineEditorViewModel.defaultIcon
    @Published var color: RoutineColor = .mint
    @Published var mode: RoutineMode = .normal
    @Published var allowsPauseDuringStrictMode = true
    @Published var tasks: [EditableRoutineTask] = [EditableRoutineTask()]
    @Published var triggers: [RoutineTrigger] = [.manual]
    @Published var maximumBreaks = 0
    @Published var maximumBreakMinutes = 10
    @Published var minimumBreakIntervalMinutes = 30
    @Published var startAlarmEnabled = false
    /// The saved pause flow this routine uses. Nil means the default wait-then-confirm.
    @Published var pauseFlowID: UUID?
    @Published private(set) var pauseFlows: [PauseFlow] = []
    @Published var blockedDomains: [String] = []
    /// Adult content, purchases, installing apps. Edited on the selection screen with
    /// everything else this routine shuts.
    @Published var contentRestrictions: ContentRestrictions = .none
    @Published var pendingDomain = ""
    @Published var errorMessage: String?
    @Published private(set) var selectedApplicationCount = 0
    @Published private(set) var selectionPreview = FamilyActivitySelection()
    @Published private(set) var suggestedApplications: [AppIdentity] = []
    @Published private(set) var appGroups: [LocktySelectableAppGroup] = []
    @Published var selectedAppGroupIDs: Set<UUID> = []

    private let repository: RoutineRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let routineEngine: RoutineEngine
    private let usageDataService: UsageDataServicing
    private let pauseFlowRepository: PauseFlowRepository
    private let appGroupRepository: UserAppGroupRepository
    let toastCenter: LocktyToastCenter
    /// What the routine looked like when the editor opened. Everything that decides
    /// whether there is anything to discard is compared against this rather than tracked
    /// by a flag, so undoing an edit by hand counts as no change again.
    private var baseline: Snapshot?

    private struct Snapshot: Equatable {
        var name: String
        var icon: String
        var color: RoutineColor
        var mode: RoutineMode
        var triggers: [RoutineTrigger]
        var tasks: [EditableRoutineTask]
        var blockedDomains: [String]
        var contentRestrictions: ContentRestrictions
        var startAlarmEnabled: Bool
        var pauseFlowID: UUID?
        var allowsPauseDuringStrictMode: Bool
        var selectedApplicationCount: Int
        var selectedAppGroupIDs: Set<UUID>
    }

    private var snapshot: Snapshot {
        Snapshot(
            name: name,
            icon: icon,
            color: color,
            mode: mode,
            triggers: triggers,
            tasks: tasks,
            blockedDomains: blockedDomains,
            contentRestrictions: contentRestrictions,
            startAlarmEnabled: startAlarmEnabled,
            pauseFlowID: pauseFlowID,
            allowsPauseDuringStrictMode: allowsPauseDuringStrictMode,
            selectedApplicationCount: selectedApplicationCount,
            selectedAppGroupIDs: selectedAppGroupIDs
        )
    }

    var hasChanges: Bool {
        guard let baseline else { return false }
        return snapshot != baseline
    }

    func captureBaseline() {
        baseline = snapshot
    }
    private let strictModePolicy = StrictModePolicy()
    private let initialRoutineID: UUID?
    private var hasLoaded = false
    private var createdAt: Date

    init(
        routineID: UUID?,
        draftID: UUID,
        repository: RoutineRepository,
        selectionStore: ScreenTimeSelectionStore,
        routineEngine: RoutineEngine,
        usageDataService: UsageDataServicing,
        pauseFlowRepository: PauseFlowRepository,
        appGroupRepository: UserAppGroupRepository,
        toastCenter: LocktyToastCenter
    ) {
        initialRoutineID = routineID
        editingID = routineID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        self.routineEngine = routineEngine
        self.usageDataService = usageDataService
        self.pauseFlowRepository = pauseFlowRepository
        self.appGroupRepository = appGroupRepository
        self.toastCenter = toastCenter
        createdAt = Date()
    }

    static let defaultIcon = "repeat"

    var isCreating: Bool { initialRoutineID == nil }

    func activeRoutine() -> ActiveRoutine? {
        routineEngine.activeRoutine()
    }

    /// Ends the routine this editor is showing, when it is the one running.
    @discardableResult
    func stopRoutine() async -> Bool {
        // This editor is one routine's, so it ends that one. Ending everything would
        // take down routines the user never opened, which is not what a stop button
        // inside a single routine can possibly mean.
        await routineEngine.stop(routineID: editingID)
        if case .failed(let message) = routineEngine.state {
            errorMessage = message
            return false
        }
        errorMessage = nil
        return true
    }

    /// Manual start from the routine's own sheet (hold-to-start).
    func startRoutine() async {
        guard let initialRoutineID,
              let routines = try? await repository.routines(),
              let routine = routines.first(where: { $0.id == initialRoutineID })
        else { return }

        errorMessage = await routineEngine.start(routine).errorMessage
    }

    /// The routine's own name, which a new one already has by the time anything is
    /// shown. "New Routine" was a placeholder standing in front of a filled field.
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return initialRoutineID == nil ? "New routine" : "Routine"
    }

    var selectionScope: ScreenTimeSelectionScope {
        draftSelectionScope
    }

    private var persistedSelectionScope: ScreenTimeSelectionScope {
        .routine(editingID)
    }

    private var draftSelectionScope: ScreenTimeSelectionScope {
        .routine(draftID)
    }

    var selectedWebsiteCount: Int {
        blockedDomains.count
    }

    var appRestrictionSummary: String {
        RestrictionSummary.appsCategoriesAndGroups(
            apps: selectionPreview.applicationTokens.count,
            categories: selectionPreview.categoryTokens.count,
            groups: selectedAppGroupIDs.count
        ) ?? "Choose apps"
    }

    var webRestrictionSummary: String {
        selectedWebsiteCount == 0 ? "No websites yet" : "\(selectedWebsiteCount) selected"
    }

    var trimmedTasksCount: Int {
        sanitizedTasks().count
    }

    var breaksAllowed: Bool {
        maximumBreaks > 0
    }

    /// A routine can't be edited while it is the one running -- in any mode, not only
    /// Strict. Its restrictions are already applied, so a mid-run edit would leave the
    /// live shield and the stored routine describing different things.
    var editingBlockDecision: StrictModeDecision {
        guard let initialRoutineID, let active = routineEngine.activeRoutine(),
              active.routineID == initialRoutineID
        else {
            return .allowed
        }

        let strictDecision = strictModePolicy.decision(for: .editRoutine, activeRoutine: active)
        guard strictDecision.isAllowed else { return strictDecision }
        return .denied("\(active.nameSnapshot) is running. It can't be edited until it ends.")
    }

    var isEditingBlocked: Bool {
        !editingBlockDecision.isAllowed
    }

    /// Displayed and edited directly in the editor, always -- with no weekdays
    /// selected this has no practical effect (manual start only), so there is
    /// no separate enable/disable toggle.
    var scheduleTrigger: RoutineSchedule {
        for trigger in triggers {
            if case .schedule(let schedule) = trigger { return schedule }
        }
        return RoutineSchedule(hour: 9, minute: 0, weekdays: [])
    }

    func updateSchedule(_ transform: (inout RoutineSchedule) -> Void) {
        var schedule = scheduleTrigger
        transform(&schedule)
        var newTriggers = triggers.filter { if case .schedule = $0 { false } else { true } }
        newTriggers.append(.schedule(schedule))
        triggers = newTriggers
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        print("Routine editor load started routineID=\(initialRoutineID?.uuidString ?? "new") draftID=\(draftID.uuidString)")
        await loadSuggestedApplications()
        await loadPauseFlows()
        await loadAppGroups()
        guard let initialRoutineID else {
            try? selectionStore.remove(scope: draftSelectionScope)
            refreshSelectionState()
            // Named before the baseline is taken, so the generated name counts as the
            // starting point rather than as an unsaved edit -- otherwise closing a
            // routine you never touched would ask whether to discard changes.
            let existing = (try? await repository.routines())?.map(\.name) ?? []
            name = LocktyGeneratedName.routine(
                startHour: scheduleTrigger.hour,
                existing: existing
            )
            captureBaseline()
            return
        }
        guard let routines = try? await repository.routines(), let routine = routines.first(where: { $0.id == initialRoutineID }) else {
            return
        }

        createdAt = routine.createdAt
        name = routine.name
        icon = routine.icon ?? RoutineEditorViewModel.defaultIcon
        color = routine.color
        mode = routine.mode
        triggers = routine.triggers.isEmpty ? [.manual] : routine.triggers
        allowsPauseDuringStrictMode = routine.allowsPauseDuringStrictMode
        tasks = routine.tasks
            .sorted { $0.order < $1.order }
            .map { EditableRoutineTask(id: $0.id, title: $0.title) }
        if tasks.isEmpty {
            tasks = [EditableRoutineTask()]
        }
        selectedAppGroupIDs = routine.appGroupIDs.intersection(Set(appGroups.map(\.id)))
        maximumBreaks = routine.breakPolicy.maximumBreaks
        maximumBreakMinutes = max(Int(routine.breakPolicy.maximumDuration / 60), 1)
        minimumBreakIntervalMinutes = max(Int(routine.breakPolicy.minimumInterval / 60), 1)
        startAlarmEnabled = routine.startAlarmEnabled
        pauseFlowID = routine.pauseFlowID
        blockedDomains = routine.blockedDomains.sorted()
        contentRestrictions = routine.contentRestrictions
        if let selection = try? selectionStore.load(scope: persistedSelectionScope) {
            try? selectionStore.save(selection, scope: draftSelectionScope)
        } else {
            try? selectionStore.remove(scope: draftSelectionScope)
        }
        refreshSelectionState()
        captureBaseline()
        print("Routine editor loaded routineID=\(initialRoutineID.uuidString) selectionApps=\(selectionPreview.applicationTokens.count) domains=\(blockedDomains.count)")
    }

    func loadPauseFlows() async {
        let loaded = await pauseFlowRepository.flows()
        withAnimation(.smooth(duration: 0.24)) {
            pauseFlows = loaded
        }
    }

    /// A blank pause, written from inside this routine's own sheet.
    func makePauseFlowEditor() -> PauseFlowEditorViewModel {
        PauseFlowEditorViewModel(flowID: nil, repository: pauseFlowRepository)
    }

    /// The flow this routine will use.
    /// When this routine next starts, from its own schedule. Nil when it has no schedule
    /// or is already running.
    var nextScheduledStart: Date? {
        let schedule = scheduleTrigger
        guard !schedule.weekdays.isEmpty else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let weekdayValue = calendar.component(.weekday, from: day)
            guard let weekday = Weekday(rawValue: weekdayValue), schedule.weekdays.contains(weekday) else {
                continue
            }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = schedule.hour
            components.minute = schedule.minute
            components.second = 0

            guard let candidate = calendar.date(from: components), candidate > now else { continue }
            return candidate
        }

        return nil
    }

    var selectedPauseFlow: PauseFlow? {
        pauseFlowID.flatMap { id in pauseFlows.first { $0.id == id } }
    }

    private func loadSuggestedApplications() async {
        do {
            let usage = try await usageDataService.mostUsedApplications(for: Date())
            // Suggestions are the most-used unproductive apps -- those are the ones worth
            // restricting. Everything else only stands in when nothing is classified
            // that way yet, so the section is never empty for no reason.
            let usable = usage.filter { $0.duration > 0 && $0.app.applicationToken != nil }
            let unproductive = usable.filter { $0.classification == .unproductive }
            let ranked = (unproductive.isEmpty ? usable : unproductive)
                .sorted { $0.duration > $1.duration }

            var seen = Set<AppIdentity.ID>()
            let suggestions = ranked.compactMap { item -> AppIdentity? in
                guard seen.insert(item.app.id).inserted else { return nil }
                return item.app
            }

            withAnimation(.smooth(duration: 0.28)) {
                suggestedApplications = Array(suggestions.prefix(8))
            }
            print("Routine editor loaded suggested applications count=\(suggestedApplications.count)")
        } catch {
            print("Routine editor failed loading suggested applications: \(error.localizedDescription)")
        }
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
                itemCount: selection.applicationTokens.count,
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

    func refreshSelectionState() {
        do {
            let selection = try selectionStore.load(scope: draftSelectionScope)
            selectionPreview = selection
            selectedApplicationCount = selection.applicationTokens.count + selection.categoryTokens.count
            print("Routine editor refreshed selection scope=\(selectionScope.id) apps=\(selection.applicationTokens.count)")
        } catch {
            selectionPreview = FamilyActivitySelection()
            selectedApplicationCount = 0
            errorMessage = error.localizedDescription
            print("Routine editor failed refreshing selection scope=\(selectionScope.id): \(error.localizedDescription)")
        }
    }

    func replaceSelection(_ selection: FamilyActivitySelection) {
        // Domains are handled separately via RoutineDomainsSheet/blockedDomains,
        // so webDomainTokens from the picker are dropped. Category selections
        // are kept -- restricting a whole category is a real, supported
        // restriction, resolved into the shield at runtime via the full
        // FamilyActivitySelection (not just applicationTokens).
        var normalized = selection
        normalized.webDomainTokens = []
        selectionPreview = normalized
        selectedApplicationCount = normalized.applicationTokens.count + normalized.categoryTokens.count
        do {
            try selectionStore.save(normalized, scope: draftSelectionScope)
            print("Routine editor replaced selection scope=\(selectionScope.id) apps=\(normalized.applicationTokens.count) categories=\(normalized.categoryTokens.count)")
        } catch {
            errorMessage = error.localizedDescription
            print("Routine editor failed replacing selection scope=\(selectionScope.id): \(error.localizedDescription)")
        }
    }

    func addTask() {
        tasks.append(EditableRoutineTask())
    }

    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        if tasks.isEmpty {
            tasks = [EditableRoutineTask()]
        }
    }

    func addDomain() {
        let normalized = normalizeDomain(pendingDomain)
        guard let normalized else {
            errorMessage = "Enter a valid domain like google.com."
            return
        }

        guard !blockedDomains.contains(normalized) else {
            pendingDomain = ""
            return
        }

        blockedDomains.append(normalized)
        blockedDomains.sort()
        pendingDomain = ""
    }

    func removeDomain(_ domain: String) {
        blockedDomains.removeAll { $0 == domain }
    }

    func save() async -> Bool {
        guard editingBlockDecision.isAllowed else {
            errorMessage = editingBlockDecision.reason
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Routine name is required."
            return false
        }

        let selection = selectionPreview
        guard
            !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selectedAppGroupIDs.isEmpty
                || !blockedDomains.isEmpty
                || !contentRestrictions.isEmpty
        else {
            errorMessage = "Select at least one app, category, app group, website, or restriction."
            print("Routine editor refused save because no app/domain restrictions were configured")
            return false
        }
        let tasks = sanitizedTasks()
        let breakPolicy = makeBreakPolicy()
        let routine = Routine(
            id: editingID,
            name: trimmedName,
            icon: icon.isEmpty ? nil : icon,
            color: color,
            mode: mode,
            triggers: triggers,
            appGroupIDs: selectedAppGroupIDs,
            blockedApplications: Set(selection.applicationTokens.map(AppIdentity.ID.init(token:))),
            blockedDomains: Set(blockedDomains),
            contentRestrictions: contentRestrictions,
            tasks: tasks,
            startAlarmEnabled: startAlarmEnabled,
            breakPolicy: breakPolicy,
            pauseFlowID: pauseFlowID,
            // Resolved at save time: the flow can be edited or deleted afterwards and
            // the routine keeps enforcing what it was given.
            pausePolicy: selectedPauseFlow?.policy ?? .off,
            allowsPauseDuringStrictMode: allowsPauseDuringStrictMode,
            createdAt: createdAt,
            updatedAt: Date()
        )

        do {
            try selectionStore.save(selection, scope: persistedSelectionScope)
            try? selectionStore.remove(scope: draftSelectionScope)
            try await repository.save(routine)
            routineEditorLogger.notice("Routine editor saved id=\(routine.id.uuidString, privacy: .public) name=\(routine.name, privacy: .public) tasks=\(tasks.count) apps=\(selection.applicationTokens.count) groups=\(self.selectedAppGroupIDs.count) domains=\(self.blockedDomains.count)")
            print("Routine editor saved id=\(routine.id.uuidString) name=\(routine.name) tasks=\(tasks.count) apps=\(selection.applicationTokens.count) groups=\(selectedAppGroupIDs.count) domains=\(blockedDomains.count)")
            return true
        } catch {
            routineEditorLogger.error("Routine editor failed saving id=\(routine.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            print("Routine editor failed saving id=\(routine.id.uuidString): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func sanitizedTasks() -> [RoutineTask] {
        tasks.enumerated().compactMap { index, task in
            let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return RoutineTask(
                id: task.id,
                title: trimmed,
                order: index,
                isOptional: false
            )
        }
    }

    private func makeBreakPolicy() -> BreakPolicy {
        guard maximumBreaks > 0 else {
            return .none
        }

        return BreakPolicy(
            maximumBreaks: maximumBreaks,
            maximumDuration: TimeInterval(maximumBreakMinutes * 60),
            minimumInterval: TimeInterval(minimumBreakIntervalMinutes * 60),
            allowedTriggers: [.manual]
        )
    }

    func setBreaksAllowed(_ isAllowed: Bool) {
        guard isAllowed else {
            maximumBreaks = 0
            return
        }

        if maximumBreaks <= 0 {
            maximumBreaks = 2
        }
        if maximumBreakMinutes <= 0 {
            maximumBreakMinutes = 5
        }
        if minimumBreakIntervalMinutes <= 0 {
            minimumBreakIntervalMinutes = 60
        }
    }

    private func normalizeDomain(_ rawValue: String) -> String? {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("."), !trimmed.contains(" ") else { return nil }
        return trimmed
    }

    func discardDraft() {
        try? selectionStore.remove(scope: draftSelectionScope)
    }
}

struct RoutineAppPickerSheet: View {
    @ObservedObject var viewModel: RoutineEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyActivitySelectionView(
            title: "Selected",
            addLabel: "Add app or category",
            selection: Binding(
                get: { viewModel.selectionPreview },
                set: { newValue in
                    withAnimation(.smooth(duration: 0.28)) {
                        viewModel.replaceSelection(newValue)
                    }
                }
            ),
            blockedDomains: Binding(
                get: { viewModel.blockedDomains },
                set: { viewModel.blockedDomains = $0 }
            ),
            contentRestrictions: Binding(
                get: { viewModel.contentRestrictions },
                set: { viewModel.contentRestrictions = $0 }
            ),
            rules: .routine,
            suggestions: viewModel.suggestedApplications,
            toastCenter: viewModel.toastCenter,
            onClose: { dismiss() },
            onDone: { dismiss() }
        )
        .presentationDetents([.large])
    }
}

private enum RoutineEditorLocalSheet: String, Identifiable {
    case apps
    case domains
    case checklist
    case breakSettings
    case color
    /// Writing a new pause without leaving the routine that will use it.
    case pauseFlow

    var id: String { rawValue }
}

private enum RoutineEditorCompactScreen: Hashable {
    case reading
    case editing
    case naming
}

/// What a discard confirmation is about to throw away.
///
/// One dialog, told what it is asking about, rather than two dialogs on the same view.
/// SwiftUI attaches each `confirmationDialog` to the view itself, and two of them fight
/// over the same presentation slot -- raising one while the other is attached crashes.
enum LocktyDiscardIntent: Identifiable {
    /// Leave the sheet entirely.
    case leave
    /// Step back to the screen behind this one.
    case back

    var id: String {
        switch self {
        case .leave: "leave"
        case .back: "back"
        }
    }
}

struct RoutineEditorView: View {
    @StateObject private var viewModel: RoutineEditorViewModel
    let router: AppRouter
    let isEmbeddedInParentSheet: Bool
    let onReturnToParent: (() -> Void)?
    let onCloseEditor: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: RoutineEditorLocalSheet?
    /// The same view serves reading and editing; the pencil flips this rather than
    /// pushing a different screen.
    @State private var isEditing: Bool
    /// Which section's (i) popover is showing, keyed by its info text.
    @State private var infoSectionText: String?
    /// The pencil swaps the sheet's content for the naming screen rather than pushing
    /// one: same sheet, same height animation, one thing on it at a time.
    @State private var isNaming = false
    @State private var isShowingIconPicker = false
    @State private var isShowingColorPicker = false
    /// Built when the pause screen is pushed and dropped when it is popped, so each new
    /// pause starts blank rather than carrying the last one's half-written steps.
    @State private var pauseFlowEditor: PauseFlowEditorViewModel?
    /// What a discard confirmation, if one is up, is about to throw away.
    @State private var pendingDiscard: LocktyDiscardIntent?
    @FocusState private var isNameFieldFocused: Bool
    @State private var isGoingBack = false

    init(
        viewModel: RoutineEditorViewModel,
        router: AppRouter,
        startsEditing: Bool = true,
        isEmbeddedInParentSheet: Bool = false,
        onReturnToParent: (() -> Void)? = nil,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isEditing = State(initialValue: startsEditing && !viewModel.isEditingBlocked)
        self.router = router
        self.isEmbeddedInParentSheet = isEmbeddedInParentSheet
        self.onReturnToParent = onReturnToParent
        self.onCloseEditor = onCloseEditor
    }

    private var isCreating: Bool { viewModel.isCreating }

    private var isRoutineActive: Bool {
        viewModel.activeRoutine()?.routineID == viewModel.editingID
    }

    private var activeRoutineStartedAt: Date? {
        isRoutineActive ? viewModel.activeRoutine()?.startedAt : nil
    }

    private func startRoutine() async {
        await viewModel.startRoutine()
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

    /// Leaving is free until something has been edited, and then it asks. Applies to the
    /// X and to the naming screen's back chevron alike -- both are ways out of the same
    /// unsaved state.
    private func requestClose() {
        guard viewModel.hasChanges else {
            returnToParentOrDismiss()
            return
        }
        pendingDiscard = .leave
    }

    /// What the bar is showing, which is not the same as which screen is showing.
    ///
    /// The bar is captured as a snapshot and only re-taken when this changes, so
    /// anything its buttons read has to be in here -- the check was disabled while the
    /// name was empty and kept that state after the name was typed, because nothing told
    /// the bar to look again. It is separate from the content's id so keystrokes rebuild
    /// the bar without re-running the screen transition.
    private var chromeID: String {
        let hasName = !viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return "\(contentID)-\(hasName)-\(viewModel.icon)"
    }

    private var contentID: String {
        if let activeSheet {
            return activeSheet.id
        }
        switch currentCompactScreen {
        case .reading: return "reading"
        case .editing: return "editor"
        case .naming: return "naming"
        }
    }

    private var currentCompactScreen: RoutineEditorCompactScreen {
        if isNaming { return .naming }
        return (isCreating || isEditing) ? .editing : .reading
    }

    private func timeValue(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    var body: some View {
        Group {
            if isEmbeddedInParentSheet {
                editorScaffold
            } else {
                LocktyDynamicSheet(animation: sheetAnimation) {
                    editorScaffold
                }
            }
        }
        .locktyInteractiveDismiss(
            blocked: viewModel.hasChanges && activeSheet == nil,
            // Swiping down means the same thing the X does, so it gets the same answer
            // rather than a sheet that silently refuses to move.
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
                case .back: returnToReading()
                }
            }
            Button("Keep editing", role: .cancel) { pendingDiscard = nil }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: isNaming, initial: false) { _, newValue in
            guard newValue else { return }
            // After the transition has put the field on screen. Focusing on the same
            // runloop turn asks a text field that does not exist yet to take the
            // keyboard, and nothing happens.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(340))
                isNameFieldFocused = true
            }
        }
        .alert(
            "Could not save routine",
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

    private var editorScaffold: some View {
        sheetContent
            .locktyDynamicSheetChrome(id: chromeID) {
                centerChrome
            } leading: {
                leadingChrome
            } trailing: {
                trailingChrome
            }
    }

    private var sheetAnimation: Animation { .snappy(duration: 0.4, extraBounce: 0.02) }

    /// Which way the screens travel. Going deeper the new screen comes in from the right
    /// and the old one leaves to the left; coming back, both reverse. Without this every
    /// change ran the same way and going back looked like going forward again.
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

    /// The screens, swapped in place. There is no navigation stack: one ZStack holds
    /// whichever screen is current and each branch is its own geometryGroup, so the
    /// sheet resizing and the content changing move together instead of the transition
    /// being measured mid-flight.
    private var sheetContent: some View {
        ZStack {
            switch activeSheet {
            case .apps:
                // A screen of its own: it asked for the whole sheet, so it has to fill
                // it rather than sit at the top of it at its own ideal height.
                selectionScreen
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            case .domains:
                domainsScreen
                    .frame(maxHeight: .infinity)
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            case .checklist:
                checklistScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case .breakSettings:
                breakSettingsScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case .color:
                colorScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case .pauseFlow:
                // Measured like the routine's own screens: a pause is a name and a few
                // steps, and the sheet is as tall as they come out.
                pauseFlowScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case nil:
                switch currentCompactScreen {
                case .naming:
                    namingContent
                        .geometryGroup()
                        .transition(screenTransition)
                case .editing:
                    editorContent
                        .geometryGroup()
                        .transition(screenTransition)
                case .reading:
                    readOnlyContent
                        .geometryGroup()
                        .transition(screenTransition)
                }
            }
        }
        .geometryGroup()
    }

    /// The middle of the bar. On the routine itself that is its icon beside its name,
    /// which is why the bar takes a view rather than a string.
    @ViewBuilder
    private var centerChrome: some View {
        switch activeSheet {
        case .apps:
            chromeTitleText("Selected")
        case .domains:
            chromeTitleText("Websites")
        case .checklist:
            chromeTitleText("Checklist")
        case .breakSettings:
            chromeTitleText("Break")
        case .color:
            chromeTitleText("Color")
        case .pauseFlow:
            chromeTitleText(pauseFlowEditor?.title ?? "New friction")
        case nil:
            if isNaming {
                chromeTitleText("Name")
            } else if currentCompactScreen == .reading {
                // Nothing. The preview under this bar shows the icon and the name at
                // full size, so a smaller copy of both sitting directly above them was
                // the same thing said twice.
                EmptyView()
            } else {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: viewModel.icon)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    chromeTitleText(routineChromeName)
                }
            }
        }
    }

    private var routineChromeName: String {
        let trimmed = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return viewModel.title
    }

    private func chromeTitleText(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
    }

    @ViewBuilder
    private var leadingChrome: some View {
        if activeSheet != nil {
            LocktyDynamicSheetBarButton(action: closePicker) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else if isNaming {
            LocktyDynamicSheetBarButton(action: exitNaming) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else if onReturnToParent != nil {
            // This is the schedule step of "Create Rule", so there is a screen behind it.
            // requestClose already lands on that screen once the discard is confirmed --
            // only the glyph was wrong, and it read as "throw all of this away".
            LocktyDynamicSheetBarButton(action: requestClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else if isEditing && !isCreating {
            // Editing an existing routine is a step *into* its preview, so the way out is
            // back to it. An X here offered to leave the sheet entirely, which is not
            // what going back from a form means.
            LocktyDynamicSheetBarButton(action: requestReturnToReading) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else {
            LocktyDynamicSheetBarButton(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }

    /// Back to the preview, asking first when there is something to lose.
    private func requestReturnToReading() {
        guard viewModel.hasChanges else {
            returnToReading()
            return
        }
        pendingDiscard = .back
    }

    private func returnToReading() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            isEditing = false
            isNaming = false
        }
    }

    @ViewBuilder
    private var trailingChrome: some View {
        if activeSheet == .pauseFlow {
            // No check here: the pause is committed by holding the button on it.
            Color.clear
                .frame(width: 44, height: 44)
        } else if activeSheet != nil {
            if isCreating || isEditing {
                LocktyDynamicSheetBarButton(action: closePicker) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .medium))
                }
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }
        } else if isNaming {
            LocktyDynamicSheetBarButton(action: exitNaming) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else if !viewModel.isEditingBlocked {
            // Also while creating. It used to be shown only when reading an existing
            // routine, so a new one had no way to reach the screen that names it.
            LocktyDynamicSheetBarButton(action: enterEditingFlow) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
            }
        } else {
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    /// Naming the routine: its name and its icon, and nothing else. Reached from the
    /// pencil, and the only way back is answering it.
    private var namingContent: some View {
        VStack(spacing: LocktySpacing.lg) {
            HStack(spacing: LocktySpacing.sm) {
                TextField("Name", text: $viewModel.name)
                    .focused($isNameFieldFocused)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                    .padding(.horizontal, LocktySpacing.lg)
                    .padding(.vertical, LocktySpacing.md)
                    .background(Capsule(style: .continuous).fill(LocktyColors.elevatedBackground))

                // The icon lives beside the name, not inside the field: it is the other
                // half of what identifies the routine, and it opens its own popover.
                Button {
                    isShowingIconPicker = true
                } label: {
                    Image(systemName: viewModel.icon)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(LocktyColors.routine(viewModel.color).opacity(0.24)))
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                // The circle is 52pt but the glyph inside it is 18, so without a content
                // shape the taps that count are only the ones landing on the glyph.
                .tappable()
                .locktyMenu(isPresented: $isShowingIconPicker) {
                    RoutineIconPickerSheet(selectedIcon: $viewModel.icon)
                }

                // The colour is picked the same way the icon is, and at the same size:
                // a row of swatches laid out under the field made the colour look like a
                // setting of its own rather than the other half of the routine's badge.
                Button {
                    isShowingColorPicker = true
                } label: {
                    Circle()
                        .fill(LocktyColors.routine(viewModel.color))
                        .frame(width: 24, height: 24)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(LocktyColors.routine(viewModel.color).opacity(0.24)))
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                .tappable()
                .locktyMenu(isPresented: $isShowingColorPicker) {
                    RoutineColorPickerPopover(selectedColor: $viewModel.color)
                }
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.vertical, LocktySpacing.lg)
    }

    /// Section heading: a glyph and a label, both in full colour. The eyebrow form is
    /// for sections inside a card; these are the sheet's own divisions.
    @ViewBuilder
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

    private func closePicker() {
        if activeSheet == .pauseFlow {
            closePauseFlowEditor()
            return
        }
        isGoingBack = true
        withAnimation(sheetAnimation) {
            activeSheet = nil
        }
        viewModel.refreshSelectionState()
    }

    private func openChildSheet(_ sheet: RoutineEditorLocalSheet) {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            activeSheet = sheet
        }
    }

    private func enterEditingFlow() {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            // The pencil means different things on the two screens, because there are
            // two different things to edit. From the preview it opens the form: the
            // routine is already named, and its name is the heading the pencil sits
            // beside. From the form there is nothing left to open but the name.
            if isEditing || isCreating {
                isNaming = true
            } else {
                isEditing = true
            }
        }
    }

    private func exitNaming() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            isNaming = false
        }
        isNameFieldFocused = false
    }

    private var cardRadius: CGFloat { 22 }

    /// The two times in one card, joined down the left by the dotted run between them.
    private var scheduleCard: some View {
        VStack(spacing: 0) {
            timeRow(
                label: "De",
                hour: viewModel.scheduleTrigger.hour,
                minute: viewModel.scheduleTrigger.minute,
                isStart: true
            ) { hour, minute in
                viewModel.updateSchedule {
                    $0.hour = hour
                    $0.minute = minute
                }
            }

            Divider()
                .overlay(LocktyColors.ink(0.10))
                .padding(.leading, 44)

            timeRow(
                label: "A",
                hour: viewModel.scheduleTrigger.endHour,
                minute: viewModel.scheduleTrigger.endMinute,
                isStart: false
            ) { hour, minute in
                viewModel.updateSchedule {
                    $0.endHour = hour
                    $0.endMinute = minute
                }
            }
        }
        .locktyCardBackground(cornerRadius: cardRadius)
        .overlay(alignment: .topLeading) {
            // The run between the two marks, drawn once across both rows rather than
            // half in each, so it lines up whatever the rows end up measuring.
            Rectangle()
                .fill(LocktyColors.ink(0.35))
                .frame(width: 1)
                .padding(.leading, 21)
                .padding(.top, 26)
                .padding(.bottom, 26)
        }
    }

    private var readOnlyScheduleCard: some View {
        VStack(spacing: 0) {
            readOnlyTimeRow(
                label: "De",
                value: timeValue(
                    hour: viewModel.scheduleTrigger.hour,
                    minute: viewModel.scheduleTrigger.minute
                ),
                isStart: true
            )

            Divider()
                .overlay(LocktyColors.ink(0.10))
                .padding(.leading, 44)

            readOnlyTimeRow(
                label: "A",
                value: timeValue(
                    hour: viewModel.scheduleTrigger.endHour,
                    minute: viewModel.scheduleTrigger.endMinute
                ),
                isStart: false
            )
        }
        .locktyCardBackground(cornerRadius: cardRadius)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(LocktyColors.ink(0.35))
                .frame(width: 1)
                .padding(.leading, 21)
                .padding(.top, 26)
                .padding(.bottom, 26)
        }
    }

    private func timeRow(
        label: String,
        hour: Int,
        minute: Int,
        isStart: Bool,
        onChange: @escaping (Int, Int) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(isStart ? LocktyColors.ink(0.75) : .clear)
                .overlay {
                    if !isStart {
                        Circle().stroke(LocktyColors.ink(0.55), lineWidth: 1.5)
                    }
                }
                .frame(width: 9, height: 9)
                .frame(width: 44, alignment: .center)

            Text(label)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            ScheduleTimeField(label: label, hour: hour, minute: minute, onChange: onChange)
        }
        .padding(.trailing, LocktySpacing.md)
        .frame(height: 52)
    }

    private func readOnlyTimeRow(
        label: String,
        value: String,
        isStart: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(isStart ? LocktyColors.ink(0.75) : .clear)
                .overlay {
                    if !isStart {
                        Circle().stroke(LocktyColors.ink(0.55), lineWidth: 1.5)
                    }
                }
                .frame(width: 9, height: 9)
                .frame(width: 44, alignment: .center)

            Text(label)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.trailing, LocktySpacing.md)
        .frame(height: 52)
    }

    /// The weekday circles, with the name of whatever preset they add up to.
    private var daysCard: some View {
        let selected = viewModel.scheduleTrigger.weekdays

        return VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack {
                Text("On these days:")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: 0)

                Text(RoutineEditorView.presetName(for: selected))
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            HStack(spacing: 10) {
                ForEach(Weekday.orderedWeek, id: \.self) { weekday in
                    let isOn = selected.contains(weekday)

                    Button {
                        withAnimation(.smooth(duration: 0.22)) {
                            viewModel.updateSchedule {
                                if isOn { $0.weekdays.remove(weekday) } else { $0.weekdays.insert(weekday) }
                            }
                        }
                    } label: {
                        Text(weekday.shortLabel)
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(isOn ? .black : LocktyColors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                if isOn {
                                    Circle().fill(.white)
                                } else {
                                    Circle().stroke(LocktyColors.ink(0.18), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.locktyInteractive(shape: Circle()))
                }
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    /// The name for a set of days when it happens to be one, and the count when it isn't.
    /// Shared with the preview screen, which names the same set of days.
    static func previewPresetName(for weekdays: Set<Weekday>) -> String {
        presetName(for: weekdays)
    }

    private static func presetName(for weekdays: Set<Weekday>) -> String {
        let weekend: Set<Weekday> = [.saturday, .sunday]
        let workweek: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

        switch weekdays {
        case []: return "Never"
        case weekend: return "Fines de semana"
        case workweek: return "Entre semana"
        case Set(Weekday.orderedWeek): return "Every day"
        default: return weekdays.count == 1 ? "1 day" : "\(weekdays.count) days"
        }
    }

    private var appsRow: some View {
        Button {
            openChildSheet(.apps)
        } label: {
            HStack {
                Text("Apps seleccionadas")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: 0)

                Text(
                    RestrictionSummary.appsCategoriesAndGroups(
                        apps: viewModel.selectionPreview.applicationTokens.count,
                        categories: viewModel.selectionPreview.categoryTokens.count,
                        groups: viewModel.selectedAppGroupIDs.count
                    ) ?? "None"
                )
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: 52)
            .locktyCardBackground(cornerRadius: cardRadius)
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }

    @ViewBuilder
    private var selectionScreen: some View {
        VStack {
            if isCreating || isEditing {
                LocktyActivitySelectionView(
                    title: "Selected",
                    addLabel: "Add app or category",
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
                    blockedDomains: Binding(
                        get: { viewModel.blockedDomains },
                        set: { viewModel.blockedDomains = $0 }
                    ),
                    contentRestrictions: Binding(
                        get: { viewModel.contentRestrictions },
                        set: { viewModel.contentRestrictions = $0 }
                    ),
                    rules: .routine,
                    suggestions: viewModel.suggestedApplications,
                    appGroups: viewModel.appGroups,
                    toastCenter: viewModel.toastCenter,
                    onClose: {},
                    onDone: {}
                )
            } else {
                LocktyReadOnlyActivitySelectionView(
                    title: "Selected",
                    selection: viewModel.selectionPreview
                )
            }
        }
    }

    private var domainsScreen: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                HStack(spacing: LocktySpacing.sm) {
                    TextField("google.com", text: $viewModel.pendingDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .locktyGlassInputStyle()

                    Button("Add") {
                        withAnimation(.smooth(duration: 0.24)) {
                            viewModel.addDomain()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 52)
                    .safeGlass(radius: LocktyRadius.medium, interactive: true, tint: LocktyColors.primaryText)
                }

                if !viewModel.blockedDomains.isEmpty {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        DomainChipFlow(domains: viewModel.blockedDomains) { domain in
                            withAnimation(.smooth(duration: 0.24)) {
                                viewModel.removeDomain(domain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.md)
        }
    }

    private var breakRow: some View {
        Button {
            openChildSheet(.breakSettings)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Break")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(breakSummary)
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
            .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
    }

    private var checklistSummary: String {
        let count = viewModel.trimmedTasksCount
        return count == 0 ? "Empty" : (count == 1 ? "1 step" : "\(count) steps")
    }

    private var checklistRow: some View {
        Button {
            openChildSheet(.checklist)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checklist")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(checklistSummary)
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
            .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
    }

    private var colorRow: some View {
        Button {
            openChildSheet(.color)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Color")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(viewModel.color.rawValue.capitalized)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(LocktyColors.routine(viewModel.color))
                    .frame(width: 18, height: 18)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .locktyCardBackground(cornerRadius: cardRadius)
            .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
    }

    private var pauseFlowSummary: String {
        guard let flow = viewModel.selectedPauseFlow else { return "Sin pausa" }
        return flow.steps.count == 1 ? "1 step" : "\(flow.steps.count) steps"
    }

    private var breakSummary: String {
        guard viewModel.breaksAllowed else { return "No breaks allowed" }
        let breakCount = viewModel.maximumBreaks == 1 ? "1 break" : "\(viewModel.maximumBreaks) breaks"
        let duration = "\(viewModel.maximumBreakMinutes)m"
        let friction = viewModel.selectedPauseFlow.map { $0.steps.count == 1 ? "1 step" : "\($0.steps.count) steps" } ?? "No friction"
        return "\(breakCount) · \(duration) · \(friction)"
    }

    private var readOnlyBreakRow: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Break")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(breakSummary)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var readOnlyColorRow: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Color")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(viewModel.color.rawValue.capitalized)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(LocktyColors.routine(viewModel.color))
                .frame(width: 18, height: 18)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    @ViewBuilder
    private var pauseFlowScreen: some View {
        if let pauseFlowEditor {
            PauseFlowEditorContent(viewModel: pauseFlowEditor) { flow in
                Task {
                    await viewModel.loadPauseFlows()
                    withAnimation(sheetAnimation) {
                        viewModel.pauseFlowID = flow.id
                    }
                    closePauseFlowEditor()
                }
            }
        }
    }

    private var breakSettingsScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Break policy", systemImage: "figure.walk")

            breakAvailabilityCard

            if viewModel.breaksAllowed {
                breakDetailsCard
            }

            sectionHeading("Friction", systemImage: "sparkles.rectangle.stack")

            frictionSelectionCard

            Button {
                openPauseFlowEditor()
            } label: {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("Create friction")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)
                .frame(height: 52)
                .locktyCardBackground(cornerRadius: cardRadius)
            }
            .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var colorScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Routine color", systemImage: "paintpalette")

            HStack(spacing: LocktySpacing.sm) {
                ForEach(RoutineColor.allCases) { routineColor in
                    Button {
                        withAnimation(.smooth(duration: 0.22)) {
                            viewModel.color = routineColor
                        }
                    } label: {
                        Circle()
                            .fill(LocktyColors.routine(routineColor))
                            .frame(width: 38, height: 38)
                            .overlay {
                                Circle()
                                    .stroke(LocktyColors.primaryText.opacity(viewModel.color == routineColor ? 0.95 : 0.2), lineWidth: viewModel.color == routineColor ? 2 : 1)
                            }
                    }
                    .buttonStyle(.locktyInteractive(shape: Circle()))
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .locktyCardBackground(cornerRadius: cardRadius)
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func openPauseFlowEditor() {
        pauseFlowEditor = viewModel.makePauseFlowEditor()
        openChildSheet(.pauseFlow)
    }

    private func closePauseFlowEditor() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            activeSheet = .breakSettings
        }
        pauseFlowEditor = nil
    }

    private var breakAvailabilityCard: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow breaks")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(viewModel.breaksAllowed ? "This rule can temporarily bypass its restriction." : "This rule cannot be bypassed.")
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
    }

    private var breakDetailsCard: some View {
        VStack(spacing: 0) {
            breakStepperRow(
                title: "Max breaks",
                valueText: "\(viewModel.maximumBreaks)",
                decrementDisabled: viewModel.maximumBreaks <= 1,
                incrementDisabled: viewModel.maximumBreaks >= 8,
                onDecrement: { viewModel.maximumBreaks = max(viewModel.maximumBreaks - 1, 1) },
                onIncrement: { viewModel.maximumBreaks = min(viewModel.maximumBreaks + 1, 8) }
            )

            Divider()
                .overlay(LocktyColors.ink(0.10))
                .padding(.leading, 16)

            breakStepperRow(
                title: "Break duration",
                valueText: "\(viewModel.maximumBreakMinutes) min",
                decrementDisabled: viewModel.maximumBreakMinutes <= 1,
                incrementDisabled: viewModel.maximumBreakMinutes >= 15,
                onDecrement: { viewModel.maximumBreakMinutes = max(viewModel.maximumBreakMinutes - 1, 1) },
                onIncrement: { viewModel.maximumBreakMinutes = min(viewModel.maximumBreakMinutes + 1, 15) }
            )

            Divider()
                .overlay(LocktyColors.ink(0.10))
                .padding(.leading, 16)

            breakStepperRow(
                title: "Cooldown",
                valueText: "\(viewModel.minimumBreakIntervalMinutes) min",
                decrementDisabled: viewModel.minimumBreakIntervalMinutes <= 5,
                incrementDisabled: viewModel.minimumBreakIntervalMinutes >= 180,
                onDecrement: { viewModel.minimumBreakIntervalMinutes = max(viewModel.minimumBreakIntervalMinutes - 5, 5) },
                onIncrement: { viewModel.minimumBreakIntervalMinutes = min(viewModel.minimumBreakIntervalMinutes + 5, 180) }
            )
        }
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var frictionSelectionCard: some View {
        VStack(spacing: 0) {
            if viewModel.pauseFlows.isEmpty {
                HStack {
                    Text("No saved frictions yet")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LocktySpacing.md)
                .padding(.vertical, LocktySpacing.md)
            } else {
                ForEach(Array(viewModel.pauseFlows.enumerated()), id: \.element.id) { index, flow in
                    Button {
                        withAnimation(.smooth(duration: 0.24)) {
                            viewModel.pauseFlowID = flow.id
                        }
                    } label: {
                        HStack(spacing: LocktySpacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flow.name)
                                    .font(.system(.subheadline, design: .default, weight: .regular))
                                    .foregroundStyle(LocktyColors.primaryText)

                                Text(flow.steps.count == 1 ? "1 step" : "\(flow.steps.count) steps")
                                    .font(.system(.footnote, design: .default, weight: .regular))
                                    .foregroundStyle(LocktyColors.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: viewModel.pauseFlowID == flow.id ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(viewModel.pauseFlowID == flow.id ? LocktyColors.productive : LocktyColors.secondaryText)
                        }
                        .padding(.horizontal, LocktySpacing.md)
                        .padding(.vertical, LocktySpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < viewModel.pauseFlows.count - 1 {
                        Divider()
                            .overlay(LocktyColors.ink(0.10))
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var checklistScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Checklist", systemImage: "checklist")

            if isCreating || isEditing {
                editableChecklistCard

                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        viewModel.addTask()
                    }
                } label: {
                    HStack(spacing: LocktySpacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text("Add step")
                            .font(.system(.subheadline, design: .default, weight: .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(LocktyColors.primaryText)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 52)
                    .locktyCardBackground(cornerRadius: cardRadius)
                }
                .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
            } else {
                readOnlyTasksCard
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var editableChecklistCard: some View {
        VStack(spacing: 0) {
            ForEach(Array($viewModel.tasks.enumerated()), id: \.element.id) { index, $task in
                RoutineTaskEditorRow(
                    task: $task,
                    isEditing: true,
                    onRemove: {
                        withAnimation(.smooth(duration: 0.22)) {
                            viewModel.removeTask(id: task.id)
                        }
                    }
                )

                if index < viewModel.tasks.count - 1 {
                    Divider()
                        .overlay(LocktyColors.separator.opacity(0.55))
                }
            }
        }
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private func breakStepperRow(
        title: String,
        valueText: String,
        decrementDisabled: Bool,
        incrementDisabled: Bool,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            Button(action: onDecrement) {
                ZStack {
                    Circle()
                        .fill(LocktyColors.primaryText)

                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LocktyColors.onPrimary)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .tappable()
            .disabled(decrementDisabled)
            .opacity(decrementDisabled ? 0.35 : 1)

            Text(valueText)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .locktyNumericTransition(trigger: valueText)
                .frame(minWidth: 84)
                .multilineTextAlignment(.center)

            Button(action: onIncrement) {
                ZStack {
                    Circle()
                        .fill(LocktyColors.primaryText)

                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LocktyColors.onPrimary)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .tappable()
            .disabled(incrementDisabled)
            .opacity(incrementDisabled ? 0.35 : 1)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
    }

    private var strictRow: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: LocktySpacing.sm) {
                    Text("Strict mode")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                        Text("PRO")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LocktyColors.productive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LocktyColors.productive.opacity(0.55), lineWidth: 1)
                    }
                }

                Text("No se permiten desbloqueos")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)

            // On when the routine is strict. It used to be bound to a different setting
            // and read inverted next to its own subtitle.
            LocktySwitch(
                isOn: Binding(
                    get: { viewModel.mode == .strict },
                    set: { viewModel.mode = $0 ? .strict : .normal }
                )
            )
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var strictReadOnlyRow: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Strict mode")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(viewModel.mode == .strict ? "On" : "Desactivado")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: viewModel.mode == .strict ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(
                    viewModel.mode == .strict
                    ? LocktyColors.productive
                    : LocktyColors.secondaryText
                )
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var editorContent: some View {
        // Built to the design, not assembled from the app's other pieces. A List would
        // impose its own row insets, separators and background, and the design has none
        // of those -- what it has is two cards under each heading.
        // No scroll view. The sheet is as tall as this is, so there is never anything
        // below the fold to scroll to -- and a scroll view here would report the height
        // it was given rather than the height of what is in it.
        VStack(alignment: .leading, spacing: 18) {
                sectionHeading("SCHEDULE", systemImage: "calendar")

                scheduleCard

                daysCard

                checklistRow

                sectionHeading("RESTRICTIONS", systemImage: "lock.shield")

                appsRow

                breakRow

                strictRow

                LocktyHoldButton(
                    title: isCreating ? "Hold to confirm" : "Hold to save",
                    // The routine's own colour, not green. Green would say the same thing
                    // on every routine, and red is reserved for the one button that undoes
                    // something -- finishing a running routine.
                    tint: LocktyColors.routine(viewModel.color)
                ) {
                    Task {
                        if await viewModel.save() {
                            // Confirming closes the sheet and leaves the routine made.
                            if isCreating {
                                dismissEditor()
                            } else {
                                withAnimation(sheetAnimation) { isEditing = false }
                            }
                        }
                    }
                }
                .padding(.top, LocktySpacing.sm)
            }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        // The same bloom the preview has. Editing is not a different place, it is the
        // same routine with its fields open, and dropping the colour on the way in made
        // it feel like one.
        .background(alignment: .top) { routineBloom }
    }

    /// The routine's colour, behind whichever screen is showing.
    ///
    /// One definition for the preview and the form both. It is the one thing on either
    /// screen that is purely this routine's -- everything else is a fact or a field --
    /// and it is what makes two routines feel unlike each other at a glance.
    private var routineBloom: some View {
        Ellipse()
            .fill(LocktyColors.routine(viewModel.color))
            .frame(height: 260)
            .blur(radius: 90)
            .opacity(0.26)
            .offset(y: -60)
            .allowsHitTesting(false)
            .animation(.smooth(duration: 0.4), value: viewModel.color)
    }

    private var readOnlyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // A summary, not the form with its controls removed. Reading a routine used
            // to look like editing one that had stopped responding.
            RoutinePreviewContent(
                viewModel: viewModel,
                applicationTokens: previewTokens,
                activeSince: activeRoutineStartedAt,
                nextStart: viewModel.nextScheduledStart
            )

            // Start it, or end it if it is the one running. While a different routine
            // is running there is no button at all: starting this one would mean
            // stopping that one, which is not a decision this button should make.
            if isRoutineActive {
                LocktyHoldButton(
                    title: "Hold to finish",
                    systemImage: "stop.circle",
                    tint: LocktyColors.unproductive
                ) {
                    Task {
                        let stopped = await viewModel.stopRoutine()
                        guard stopped else { return }

                        withAnimation(.smooth(duration: 0.28)) {
                            // The card on Today is a request against the routine that was
                            // running. Ending the routine answers it.
                            router.pendingUnlock = nil
                        }
                        dismissEditor()
                    }
                }
                .padding(.top, LocktySpacing.sm)
                .padding(.horizontal, LocktySpacing.screenInset)
            } else if viewModel.activeRoutine() == nil {
                LocktyHoldButton(title: "Hold to start", systemImage: "play.fill") {
                    Task {
                        await startRoutine()
                        dismissEditor()
                    }
                }
                .padding(.top, LocktySpacing.sm)
                .padding(.horizontal, LocktySpacing.screenInset)
            }
        }
        // No margin of its own: `RoutinePreviewContent` already sits at `screenInset`,
        // and this block used to add a second one, so a routine at rest was inset twice
        // as far as the same routine open for editing.
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { routineBloom }
    }

    /// The apps the routine holds, for the preview's stack.
    private var previewTokens: [ApplicationToken] {
        let tokens = viewModel.selectionPreview.applicationTokens
        return tokens.stablePrefix(tokens.count)
    }

    private var readOnlyDaysCard: some View {
        let selected = viewModel.scheduleTrigger.weekdays

        return VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack {
                Text("On these days:")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: 0)

                Text(RoutineEditorView.presetName(for: selected))
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            HStack(spacing: 10) {
                ForEach(Weekday.orderedWeek, id: \.self) { weekday in
                    let isOn = selected.contains(weekday)

                    Text(weekday.shortLabel)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(isOn ? .black : LocktyColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if isOn {
                                Circle().fill(.white)
                            } else {
                                Circle().stroke(LocktyColors.ink(0.18), lineWidth: 1)
                            }
                        }
                }
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    private var trimmedReadOnlyTasks: [EditableRoutineTask] {
        viewModel.tasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var readOnlyTasksCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(trimmedReadOnlyTasks.enumerated()), id: \.element.id) { index, task in
                HStack(spacing: 12) {
                    Image(systemName: "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(task.title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if index < trimmedReadOnlyTasks.count - 1 {
                    Divider()
                        .overlay(LocktyColors.separator.opacity(0.55))
                }
            }
        }
        .locktyCardBackground(cornerRadius: cardRadius)
    }

    @ViewBuilder
    /// Matches the RESTRICTIONS/SCHEDULE sections: hairline separator above an
    /// uppercase eyebrow caption, sitting outside the section's content. `info`, when
    /// given, adds a tappable (i) beside the caption explaining the section.
    private func editorSection<Content: View>(
        title: String,
        info: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Rectangle()
                .fill(LocktyColors.separator)
                .frame(height: 0.5)

            HStack(spacing: LocktySpacing.xs) {
                Text(title.uppercased())
                    .locktyEyebrow()

                if let info {
                    Button {
                        infoSectionText = info
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .locktyMenu(isPresented: Binding(
                        get: { infoSectionText == info },
                        set: { if !$0 { infoSectionText = nil } }
                    )) {
                        Text(info)
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 220, alignment: .leading)
                            .padding(LocktySpacing.md)
                    }
                }

                Spacer(minLength: 0)
            }

            content()
        }
    }
}

private struct RoutineEditorHero: View {
    @ObservedObject var viewModel: RoutineEditorViewModel
    var isEditing: Bool = true
    @State private var showIconPicker = false

    private var iconImage: some View {
        Image(systemName: viewModel.icon)
            .font(.system(size: 22, weight: .ultraLight))
            .foregroundStyle(LocktyColors.primaryText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            VStack(spacing: LocktySpacing.sm) {
                Text(viewModel.title)
                    .font(.footnote)
                    .foregroundStyle(LocktyColors.tertiaryText)

                // Reading mode is inert: the icon loses its tappable glass and the name
                // loses its field background, so nothing on screen invites an edit.
                if isEditing {
                    Button {
                        showIconPicker = true
                    } label: {
                        iconImage
                            .frame(width: 50, height: 50)
                            .safeGlass(radius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .locktyMenu(isPresented: $showIconPicker) {
                        RoutineIconPickerSheet(selectedIcon: $viewModel.icon)
                    }
                } else {
                    iconImage
                        .frame(width: 50, height: 50)
                }

                if isEditing {
                    CardView(
                        radius: 14,
                        padding: 0,
                        expandsHorizontally: false
                    ) {
                        ZStack {
                            Text(viewModel.name.isEmpty ? "Routine name" : "\(viewModel.name) ")
                                .font(LocktyTypography.body)
                                .foregroundStyle(.clear)
                                .lineLimit(1)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)

                            TextField("Routine name", text: $viewModel.name)
                                .font(LocktyTypography.body)
                                .foregroundStyle(LocktyColors.primaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                        }
                    }
                    // No minimum width: the invisible sizing text above already makes the
                    // field hug its content, so a floor only forced it wider than the
                    // placeholder it's meant to match.
                    .frame(maxWidth: 320)
                } else {
                    Text(viewModel.name)
                        .font(LocktyTypography.body)
                        .foregroundStyle(LocktyColors.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 320)
                }
            }
            .frame(maxWidth: .infinity)

//            VStack(alignment: .leading, spacing: LocktySpacing.md) {
//                Picker("Mode", selection: $viewModel.mode) {
//                    Text("Normal").tag(RoutineMode.normal)
//                    Text("Strict").tag(RoutineMode.strict)
//                }
//                .pickerStyle(.segmented)

//                ToggleRow(
//                    title: "Allow Pause during Strict Mode",
//                    subtitle: "Pause stays available only if this is enabled.",
//                    isOn: $viewModel.allowsPauseDuringStrictMode,
//                    isDisabled: viewModel.mode == .normal
//                )
//            }
        }
    }
}

private struct RoutineTaskEditorRow: View {
    @Binding var task: EditableRoutineTask
    var isEditing: Bool = true
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Task", text: $task.title)
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)
            } else {
                Text(task.title)
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)
            }

            Spacer(minLength: 0)

            if isEditing {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(LocktyColors.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct ScheduleTimeField: View {
    let label: String
    let hour: Int
    let minute: Int
    let onChange: (Int, Int) -> Void
    @State private var isShowingPicker = false

    private var displayText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Every five minutes, plus whatever the routine already has if it is off that grid
    /// (a schedule written before this control, or one the system rounded differently).
    private var minuteOptions: [Int] {
        let grid = Array(stride(from: 0, to: 60, by: 5))
        return grid.contains(minute) ? grid : (grid + [minute]).sorted()
    }

    private var hourBinding: Binding<Int> {
        Binding(get: { hour }, set: { onChange($0, minute) })
    }

    private var minuteBinding: Binding<Int> {
        Binding(get: { minute }, set: { onChange(hour, $0) })
    }

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) {
                isShowingPicker = true
            }
        } label: {
            HStack(spacing: LocktySpacing.sm) {
                Text(displayText)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: displayText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappable()
        .accessibilityLabel(label)
        .locktyMenu(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            ScheduleTimePopoverContent(
                label: label,
                hour: hourBinding,
                minute: minuteBinding,
                minuteOptions: minuteOptions
            )
            .id("schedule-popover-\(label)-\(hour)-\(minute)")
        }
    }

    private func timeWheel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            content()
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 104, height: 144)
                .clipped()
        }
    }
}

/// The colours, and nothing else: a popover carries its own edge, so anything drawn
/// behind these swatches is a second surface inside the first one.
private struct RoutineColorPickerPopover: View {
    @Binding var selectedColor: RoutineColor
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.md), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
            ForEach(RoutineColor.allCases) { routineColor in
                Button {
                    selectedColor = routineColor
                    dismiss()
                } label: {
                    Circle()
                        .fill(LocktyColors.routine(routineColor))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Circle()
                                .stroke(
                                    LocktyColors.primaryText.opacity(selectedColor == routineColor ? 0.9 : 0.22),
                                    lineWidth: selectedColor == routineColor ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
        .padding(LocktySpacing.md)
        .frame(width: 190)
    }
}

private struct ScheduleTimePopoverContent: View {
    let label: String
    @Binding var hour: Int
    @Binding var minute: Int
    let minuteOptions: [Int]

    /// Two wheels, and nothing else. The popover already draws its own surface, so the
    /// rounded black panel behind this was a second one inside it -- and "De"/"A" and
    /// "Horas"/"Minutos" only repeated the row that opened the popover and the numbers
    /// that are already on the wheels.
    var body: some View {
        HStack(spacing: 0) {
            timeWheel {
                Picker("Horas", selection: $hour) {
                    ForEach(0..<24, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
            }

            timeWheel {
                Picker("Minutos", selection: $minute) {
                    ForEach(minuteOptions, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
            }
        }
        .id("schedule-content-\(label)")
        .padding(.vertical, 8)
        .frame(width: 260)
    }

    private func timeWheel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 120, height: 152)
            .clipped()
            .frame(maxWidth: .infinity)
    }
}

/// A flat, always-visible settings-style row (label, or its live summary once set).
enum RestrictionSummary {
    /// e.g. "3 Apps and 1 Category." — nil when nothing is selected.
    static func appsAndCategories(apps: Int, categories: Int) -> String? {
        var parts: [String] = []
        if apps > 0 { parts.append(apps == 1 ? "1 App" : "\(apps) Apps") }
        if categories > 0 { parts.append(categories == 1 ? "1 Category" : "\(categories) Categories") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " and ") + "."
    }

    static func appsCategoriesAndGroups(apps: Int, categories: Int, groups: Int) -> String? {
        var parts: [String] = []
        if apps > 0 { parts.append(apps == 1 ? "1 App" : "\(apps) Apps") }
        if categories > 0 { parts.append(categories == 1 ? "1 Category" : "\(categories) Categories") }
        if groups > 0 { parts.append(groups == 1 ? "1 Group" : "\(groups) Groups") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func domains(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return (count == 1 ? "1 Domain" : "\(count) Domains") + "."
    }
}

struct RestrictionRow: View {
    let label: String
    let summary: String?
    /// Up to 3 app tokens previewed on the trailing side, overlapping.
    var tokens: [ApplicationToken] = []
    var isInteractive: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(summary ?? label)
                .font(LocktyTypography.callout)
                .foregroundStyle(summary == nil ? LocktyColors.secondaryText : LocktyColors.primaryText)
            Spacer()
            // Label(token) renders its own icon and ignores styling applied to it directly, so
            // the overlap is produced by sizing a transparent Color that *hosts* the label as a
            // background — the Color's frame is what the HStack lays out.
            HStack(spacing: 0) {
                // Keyed by token, not by offset: with an offset key SwiftUI reuses the
                // same row when the selection changes and keeps drawing the old icons.
                ForEach(Array(tokens.prefix(3)), id: \.self) { token in
                    Color.clear
                        .frame(width: 20, height: 32)
                        .background {
                            Label(token)
                                .labelStyle(.iconOnly)
                                .frame(width: 32, height: 32)
                        }
                        .id(token)
                }
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .frame(height: 50)
        .background(LocktyColors.elevatedBackground, in: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if isInteractive { action?() }
        }
    }

    init(label: String, summary: String?, tokens: [ApplicationToken] = [], action: @escaping () -> Void) {
        self.label = label
        self.summary = summary
        self.tokens = tokens
        self.isInteractive = true
        self.action = action
    }

    init(label: String, summary: String?, tokens: [ApplicationToken] = []) {
        self.label = label
        self.summary = summary
        self.tokens = tokens
        self.isInteractive = false
        self.action = nil
    }
}

struct EditorTopBar: View {
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .locktySheetDismissStyle()
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.top, LocktySpacing.xs)
        .padding(.bottom, LocktySpacing.sm)
    }
}

private struct EditorActionCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md, interactive: true) {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .safeGlass(radius: 14)

                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text(title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                    Text(value)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LocktyColors.tertiaryText)
            }
        }
    }
}

struct DomainChipFlow: View {
    let domains: [String]
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            ForEach(domains, id: \.self) { domain in
                HStack(spacing: LocktySpacing.sm) {
                    Text(domain)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.primaryText)
                    Spacer()
                    Button(role: .destructive) {
                        onRemove(domain)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LocktyColors.unproductive)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, LocktySpacing.sm)
                .padding(.vertical, LocktySpacing.sm)
                .safeGlass(radius: 12, interactive: true)
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                Text(title)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
            Spacer()
            // The app's own control, not the system switch: see LocktySwitch.
            LocktySwitch(isOn: $isOn, isDisabled: isDisabled)
        }
        .opacity(isDisabled ? 0.48 : 1)
    }
}

struct EditorStepperRow: View {
    let title: String
    var suffix: String = ""
    @Binding var value: Int
    let range: ClosedRange<Int>
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xs) {
            Text(title)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
            Stepper(
                "\(value)\(suffix.isEmpty ? "" : " \(suffix)")",
                value: $value,
                in: range
            )
            .disabled(isDisabled)
        }
        .opacity(isDisabled ? 0.48 : 1)
    }
}
