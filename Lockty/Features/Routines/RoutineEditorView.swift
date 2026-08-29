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
    @Published var icon = ""
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
    @Published var breakTriggerManual = true
    @Published var breakTriggerNFC = false
    @Published var breakTriggerLocation = false
    @Published var blockedDomains: [String] = []
    @Published var pendingDomain = ""
    @Published var errorMessage: String?
    @Published private(set) var selectedApplicationCount = 0
    @Published private(set) var selectionPreview = FamilyActivitySelection()
    @Published private(set) var suggestedApplications: [AppIdentity] = []

    private let repository: RoutineRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let routineEngine: RoutineEngine
    private let usageDataService: UsageDataServicing
    private let pauseFlowRepository: PauseFlowRepository
    /// What the routine looked like when the editor opened. Everything that decides
    /// whether there is anything to discard is compared against this rather than tracked
    /// by a flag, so undoing an edit by hand counts as no change again.
    private var baseline: Snapshot?

    private struct Snapshot: Equatable {
        var name: String
        var icon: String
        var mode: RoutineMode
        var triggers: [RoutineTrigger]
        var tasks: [EditableRoutineTask]
        var blockedDomains: [String]
        var startAlarmEnabled: Bool
        var pauseFlowID: UUID?
        var allowsPauseDuringStrictMode: Bool
        var selectedApplicationCount: Int
    }

    private var snapshot: Snapshot {
        Snapshot(
            name: name,
            icon: icon,
            mode: mode,
            triggers: triggers,
            tasks: tasks,
            blockedDomains: blockedDomains,
            startAlarmEnabled: startAlarmEnabled,
            pauseFlowID: pauseFlowID,
            allowsPauseDuringStrictMode: allowsPauseDuringStrictMode,
            selectedApplicationCount: selectedApplicationCount
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
        pauseFlowRepository: PauseFlowRepository
    ) {
        initialRoutineID = routineID
        editingID = routineID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        self.routineEngine = routineEngine
        self.usageDataService = usageDataService
        self.pauseFlowRepository = pauseFlowRepository
        createdAt = Date()
        refreshSelectionState()
    }

    var isCreating: Bool { initialRoutineID == nil }

    func activeRoutine() -> ActiveRoutine? {
        routineEngine.activeRoutine()
    }

    /// Manual start from the routine's own sheet (hold-to-start).
    func startRoutine() async {
        guard let initialRoutineID,
              let routines = try? await repository.routines(),
              let routine = routines.first(where: { $0.id == initialRoutineID })
        else { return }

        await routineEngine.start(routine)
        if case .failed(let message) = routineEngine.state {
            errorMessage = message
        }
    }

    var title: String {
        initialRoutineID == nil ? "New Routine" : "Edit Routine"
    }

    var selectionScope: ScreenTimeSelectionScope {
        .routine(editingID)
    }

    var selectedWebsiteCount: Int {
        blockedDomains.count
    }

    var appRestrictionSummary: String {
        selectedApplicationCount == 0 ? "Choose apps" : "\(selectedApplicationCount) selected"
    }

    var webRestrictionSummary: String {
        selectedWebsiteCount == 0 ? "No websites yet" : "\(selectedWebsiteCount) selected"
    }

    var trimmedTasksCount: Int {
        sanitizedTasks().count
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
        // A new routine's baseline is its empty form, so typing a name already counts.
        guard let initialRoutineID else {
            captureBaseline()
            return
        }
        guard let routines = try? await repository.routines(), let routine = routines.first(where: { $0.id == initialRoutineID }) else {
            return
        }

        createdAt = routine.createdAt
        name = routine.name
        icon = routine.icon ?? ""
        mode = routine.mode
        triggers = routine.triggers.isEmpty ? [.manual] : routine.triggers
        allowsPauseDuringStrictMode = routine.allowsPauseDuringStrictMode
        tasks = routine.tasks
            .sorted { $0.order < $1.order }
            .map { EditableRoutineTask(id: $0.id, title: $0.title) }
        if tasks.isEmpty {
            tasks = [EditableRoutineTask()]
        }
        maximumBreaks = routine.breakPolicy.maximumBreaks
        maximumBreakMinutes = max(Int(routine.breakPolicy.maximumDuration / 60), 1)
        minimumBreakIntervalMinutes = max(Int(routine.breakPolicy.minimumInterval / 60), 1)
        startAlarmEnabled = routine.startAlarmEnabled
        pauseFlowID = routine.pauseFlowID
        breakTriggerManual = routine.breakPolicy.allowedTriggers.contains(.manual)
        breakTriggerNFC = routine.breakPolicy.allowedTriggers.contains(.nfc)
        breakTriggerLocation = routine.breakPolicy.allowedTriggers.contains(.location)
        blockedDomains = routine.blockedDomains.sorted()
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

    func refreshSelectionState() {
        do {
            let selection = try selectionStore.load(scope: selectionScope)
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
            try selectionStore.save(normalized, scope: selectionScope)
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
        guard !selection.applicationTokens.isEmpty || !blockedDomains.isEmpty else {
            errorMessage = "Select at least one app or add at least one domain."
            print("Routine editor refused save because no app/domain restrictions were configured")
            return false
        }
        let tasks = sanitizedTasks()
        let breakPolicy = makeBreakPolicy()
        let routine = Routine(
            id: editingID,
            name: trimmedName,
            icon: icon.isEmpty ? nil : icon,
            mode: mode,
            triggers: triggers,
            blockedApplications: Set(selection.applicationTokens.map(AppIdentity.ID.init(token:))),
            blockedDomains: Set(blockedDomains),
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
            try selectionStore.save(selection, scope: selectionScope)
            try await repository.save(routine)
            routineEditorLogger.notice("Routine editor saved id=\(routine.id.uuidString, privacy: .public) name=\(routine.name, privacy: .public) tasks=\(tasks.count) apps=\(selection.applicationTokens.count) domains=\(self.blockedDomains.count)")
            print("Routine editor saved id=\(routine.id.uuidString) name=\(routine.name) tasks=\(tasks.count) apps=\(selection.applicationTokens.count) domains=\(blockedDomains.count)")
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
        let triggers = Set([
            breakTriggerManual ? BreakTrigger.manual : nil,
            breakTriggerNFC ? BreakTrigger.nfc : nil,
            breakTriggerLocation ? BreakTrigger.location : nil
        ].compactMap { $0 })

        guard maximumBreaks > 0, !triggers.isEmpty else {
            return .none
        }

        return BreakPolicy(
            maximumBreaks: maximumBreaks,
            maximumDuration: TimeInterval(maximumBreakMinutes * 60),
            minimumInterval: TimeInterval(minimumBreakIntervalMinutes * 60),
            allowedTriggers: triggers
        )
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
}

struct RoutineAppPickerSheet: View {
    @ObservedObject var viewModel: RoutineEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyActivitySelectionView(
            title: "Seleccionadas",
            addLabel: "Añadir App o categoría",
            selection: Binding(
                get: { viewModel.selectionPreview },
                set: { newValue in
                    withAnimation(.smooth(duration: 0.28)) {
                        viewModel.replaceSelection(newValue)
                    }
                }
            ),
            rules: .routine,
            suggestions: viewModel.suggestedApplications,
            onClose: { dismiss() },
            onDone: { dismiss() }
        )
        .presentationDetents([.large])
    }
}

private enum RoutineEditorLocalSheet: String, Identifiable {
    case apps
    case domains

    var id: String { rawValue }
}

private enum RoutineEditorCompactScreen: Hashable {
    case reading
    case editing
    case naming
}

struct RoutineEditorView: View {
    @StateObject private var viewModel: RoutineEditorViewModel
    let router: AppRouter
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
    /// Raised by any attempt to leave with unsaved edits.
    @State private var isConfirmingDiscard = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isGoingBack = false

    init(
        viewModel: RoutineEditorViewModel,
        router: AppRouter,
        startsEditing: Bool = true,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isEditing = State(initialValue: startsEditing && !viewModel.isEditingBlocked)
        self.router = router
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

    private func close() {
        onCloseEditor()
        dismiss()
    }

    /// Leaving is free until something has been edited, and then it asks. Applies to the
    /// X and to the naming screen's back chevron alike -- both are ways out of the same
    /// unsaved state.
    private func requestClose() {
        guard viewModel.hasChanges else {
            close()
            return
        }
        isConfirmingDiscard = true
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
        LocktyDynamicSheet(animation: sheetAnimation) {
            sheetContent
                .locktyDynamicSheetChrome(id: contentID) {
                    centerChrome
                } leading: {
                    leadingChrome
                } trailing: {
                    trailingChrome
                }
        }
        .interactiveDismissDisabled(viewModel.hasChanges && activeSheet == nil)
        .confirmationDialog(
            "¿Descartar los cambios?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) { close() }
            Button("Seguir editando", role: .cancel) {}
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

    private var sheetAnimation: Animation { .snappy(duration: 0.8, extraBounce: 0.1) }

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
                    .frame(maxHeight: .infinity)
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            case .domains:
                domainsScreen
                    .frame(maxHeight: .infinity)
                    .locktyDynamicSheetSizes([.large])
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
            chromeTitleText("Seleccionadas")
        case .domains:
            chromeTitleText("Websites")
        case nil:
            if isNaming {
                chromeTitleText("Nombre")
            } else {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: viewModel.icon.isEmpty ? "repeat" : viewModel.icon)
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
        return isCreating ? "Nueva rutina" : "Rutina"
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
        } else {
            LocktyDynamicSheetBarButton(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }

    @ViewBuilder
    private var trailingChrome: some View {
        if activeSheet != nil {
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
                TextField("Nombre", text: $viewModel.name)
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
                    Image(systemName: viewModel.icon.isEmpty ? "square.grid.2x2" : viewModel.icon)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(LocktyColors.elevatedBackground))
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                .popover(isPresented: $isShowingIconPicker) {
                    RoutineIconPickerSheet(selectedIcon: $viewModel.icon)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .padding(.horizontal, LocktySpacing.lg)
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
            isEditing = true
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

    private var cardFill: Color { Color.white.opacity(0.055) }
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
                .overlay(Color.white.opacity(0.10))
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
        .overlay(alignment: .topLeading) {
            // The run between the two marks, drawn once across both rows rather than
            // half in each, so it lines up whatever the rows end up measuring.
            Rectangle()
                .fill(Color.white.opacity(0.35))
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
                .overlay(Color.white.opacity(0.10))
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.35))
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
                .fill(isStart ? Color.white.opacity(0.75) : .clear)
                .overlay {
                    if !isStart {
                        Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5)
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
                .fill(isStart ? Color.white.opacity(0.75) : .clear)
                .overlay {
                    if !isStart {
                        Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5)
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
                Text("Estos días:")
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
                                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.locktyInteractive(shape: Circle()))
                }
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
    }

    /// The name for a set of days when it happens to be one, and the count when it isn't.
    private static func presetName(for weekdays: Set<Weekday>) -> String {
        let weekend: Set<Weekday> = [.saturday, .sunday]
        let workweek: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

        switch weekdays {
        case []: return "Nunca"
        case weekend: return "Fines de semana"
        case workweek: return "Entre semana"
        case Set(Weekday.orderedWeek): return "Todos los días"
        default: return weekdays.count == 1 ? "1 día" : "\(weekdays.count) días"
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
                    RestrictionSummary.appsAndCategories(
                        apps: viewModel.selectionPreview.applicationTokens.count,
                        categories: viewModel.selectionPreview.categoryTokens.count
                    ) ?? "Ninguna"
                )
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }

    @ViewBuilder
    private var selectionScreen: some View {
        Group {
            if isCreating || isEditing {
                LocktyActivitySelectionView(
                    title: "Seleccionadas",
                    addLabel: "Añadir App o categoría",
                    selection: Binding(
                        get: { viewModel.selectionPreview },
                        set: { newValue in
                            withAnimation(.smooth(duration: 0.28)) {
                                viewModel.replaceSelection(newValue)
                            }
                        }
                    ),
                    rules: .routine,
                    suggestions: viewModel.suggestedApplications,
                    onClose: {},
                    onDone: {}
                )
            } else {
                LocktyReadOnlyActivitySelectionView(
                    title: "Seleccionadas",
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

    private var strictRow: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: LocktySpacing.sm) {
                    Text("Modo estricto")
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
            Toggle(
                "",
                isOn: Binding(
                    get: { viewModel.mode == .strict },
                    set: { viewModel.mode = $0 ? .strict : .normal }
                )
            )
            .labelsHidden()
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
    }

    private var strictReadOnlyRow: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modo estricto")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(viewModel.mode == .strict ? "Activado" : "Desactivado")
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
    }

    private var editorContent: some View {
        // Built to the design, not assembled from the app's other pieces. A List would
        // impose its own row insets, separators and background, and the design has none
        // of those -- what it has is two cards under each heading.
        // No scroll view. The sheet is as tall as this is, so there is never anything
        // below the fold to scroll to -- and a scroll view here would report the height
        // it was given rather than the height of what is in it.
        VStack(alignment: .leading, spacing: 18) {
                sectionHeading("Durante este horario", systemImage: "calendar")

                scheduleCard

                daysCard

                sectionHeading("Apps bloqueadas", systemImage: "lock.shield")

                appsRow

                strictRow

                HoldDownButton(
                    text: isCreating ? "Mantén para confirmar" : "Mantén para guardar",
                    isProminent: true
                ) {
                    Task {
                        if await viewModel.save() {
                            if isCreating {
                                close()
                            } else {
                                withAnimation(.smooth(duration: 0.28)) { isEditing = false }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, LocktySpacing.sm)
            }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var readOnlyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Durante este horario", systemImage: "calendar")

            readOnlyScheduleCard

            readOnlyDaysCard

            sectionHeading("Apps bloqueadas", systemImage: "lock.shield")

            appsRow

            strictReadOnlyRow

            if !trimmedReadOnlyTasks.isEmpty {
                sectionHeading("To Do", systemImage: "checklist")
                readOnlyTasksCard
            }
        }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var readOnlyDaysCard: some View {
        let selected = viewModel.scheduleTrigger.weekdays

        return VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack {
                Text("Estos días:")
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
                                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                            }
                        }
                }
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
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
                    .popover(isPresented: Binding(
                        get: { infoSectionText == info },
                        set: { if !$0 { infoSectionText = nil } }
                    )) {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                            Text(info)
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.primaryText)
                                .frame(width: 220, alignment: .leading)
                        }
                        .presentationCompactAdaptation(.popover)
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
        Image(systemName: viewModel.icon.isEmpty ? "square.and.arrow.up.fill" : viewModel.icon)
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
                    .popover(isPresented: $showIconPicker) {
                        RoutineIconPickerSheet(selectedIcon: $viewModel.icon)
                            .presentationCompactAdaptation(.popover)
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

    @State private var isPresented = false
    @State private var draftDate = Date()

    private var displayText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var body: some View {
        Button {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            draftDate = Calendar.current.date(from: components) ?? Date()
            isPresented = true
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
        .popover(isPresented: $isPresented) {
            // Apple's own wheel. The app's wheel picker is for the flows, where the rows
            // are app names and minutes; a time is a time and the system already has the
            // control for it.
            DatePicker("", selection: $draftDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .onChange(of: draftDate) { _, newValue in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    onChange(components.hour ?? hour, components.minute ?? minute)
                }
                .presentationCompactAdaptation(.popover)
        }
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
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(isDisabled)
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
