import FamilyControls
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
@Observable
final class RoutineEditorViewModel {
    let editingID: UUID
    let draftID: UUID

    var name = ""
    var icon = ""
    var mode: RoutineMode = .normal
    var allowsPauseDuringStrictMode = true
    var tasks: [EditableRoutineTask] = [EditableRoutineTask()]
    var triggers: [RoutineTrigger] = [.manual]
    var maximumBreaks = 0
    var maximumBreakMinutes = 10
    var minimumBreakIntervalMinutes = 30
    var startAlarmEnabled = false
    var breakTriggerManual = true
    var breakTriggerNFC = false
    var breakTriggerLocation = false
    var blockedDomains: [String] = []
    var pendingDomain = ""
    var errorMessage: String?
    private(set) var selectedApplicationCount = 0
    private(set) var selectionPreview = FamilyActivitySelection()

    private let repository: RoutineRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let routineEngine: RoutineEngine
    private let usageDataService: UsageDataServicing
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
        usageDataService: UsageDataServicing
    ) {
        initialRoutineID = routineID
        editingID = routineID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        self.routineEngine = routineEngine
        self.usageDataService = usageDataService
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
        guard let initialRoutineID else { return }
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
        breakTriggerManual = routine.breakPolicy.allowedTriggers.contains(.manual)
        breakTriggerNFC = routine.breakPolicy.allowedTriggers.contains(.nfc)
        breakTriggerLocation = routine.breakPolicy.allowedTriggers.contains(.location)
        blockedDomains = routine.blockedDomains.sorted()
        refreshSelectionState()
        print("Routine editor loaded routineID=\(initialRoutineID.uuidString) selectionApps=\(selectionPreview.applicationTokens.count) domains=\(blockedDomains.count)")
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
    @State private var viewModel: RoutineEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RoutineEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: LocktySpacing.md) {
            EditorTopBar(title: "Choose Apps", onClose: { dismiss() })

            FamilyActivityPicker(selection: Binding(
                get: { viewModel.selectionPreview },
                set: { newValue in
                    viewModel.replaceSelection(newValue)
                }
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.top, LocktySpacing.sm)
        .padding(.bottom, LocktySpacing.md)
    }
}

private enum RoutineEditorLocalSheet: String, Identifiable {
    case apps
    case domains

    var id: String { rawValue }
}

struct RoutineEditorView: View {
    @State private var viewModel: RoutineEditorViewModel
    let router: AppRouter
    let onCloseEditor: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: RoutineEditorLocalSheet?
    /// The same view serves reading and editing; the pencil flips this rather than
    /// pushing a different screen.
    @State private var isEditing: Bool
    /// Which section's (i) popover is showing, keyed by its info text.
    @State private var infoSectionText: String?

    init(
        viewModel: RoutineEditorViewModel,
        router: AppRouter,
        startsEditing: Bool = true,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _isEditing = State(initialValue: startsEditing)
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

    var body: some View {
        NavigationStack {
            editorContent
        }
        .presentationDetents([.large])
    }

    private var editorContent: some View {
        @Bindable var viewModel = viewModel

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                if viewModel.isEditingBlocked {
                    EditingDisabledBanner(message: viewModel.editingBlockDecision.reason ?? "This routine cannot be edited right now.")
                }

                RoutineEditorHero(viewModel: viewModel, isEditing: isEditing)

                if !isEditing, !isCreating {
                    HoldDownButton(
                        text: isRoutineActive ? "" : "Hold to start",
                        sessionStartedAt: isRoutineActive ? activeRoutineStartedAt : nil
                    ) {
                        Task { await startRoutine() }
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Rectangle()
                        .fill(LocktyColors.separator)
                        .frame(height: 0.5)
                    Text("RESTRICTIONS")
                        .locktyEyebrow()

                    VStack(spacing: LocktySpacing.sm) {
                        if isEditing {
                            RestrictionRow(
                                label: "Apps",
                                summary: RestrictionSummary.appsAndCategories(
                                    apps: viewModel.selectionPreview.applicationTokens.count,
                                    categories: viewModel.selectionPreview.categoryTokens.count
                                ),
                                tokens: viewModel.selectionPreview.applicationTokens.stablePrefix(3)
                            ) {
                                activeSheet = .apps
                            }

                            RestrictionRow(
                                label: "Domains",
                                summary: RestrictionSummary.domains(viewModel.blockedDomains.count)
                            ) {
                                activeSheet = .domains
                            }
                        } else {
                            RestrictionRow(
                                label: "Apps",
                                summary: RestrictionSummary.appsAndCategories(
                                    apps: viewModel.selectionPreview.applicationTokens.count,
                                    categories: viewModel.selectionPreview.categoryTokens.count
                                ),
                                tokens: viewModel.selectionPreview.applicationTokens.stablePrefix(3)
                            )

                            RestrictionRow(
                                label: "Domains",
                                summary: RestrictionSummary.domains(viewModel.blockedDomains.count)
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Rectangle()
                        .fill(LocktyColors.separator)
                        .frame(height: 0.5)
                    Text("SCHEDULE")
                        .locktyEyebrow()

                    ScheduleDaysPicker(
                        selectedWeekdays: Binding(
                            get: { viewModel.scheduleTrigger.weekdays },
                            set: { newValue in viewModel.updateSchedule { $0.weekdays = newValue } }
                        )
                    )

                    HStack(spacing: LocktySpacing.xl) {
                        ScheduleTimeField(
                            label: "Start",
                            hour: viewModel.scheduleTrigger.hour,
                            minute: viewModel.scheduleTrigger.minute,
                            onChange: { hour, minute in
                                viewModel.updateSchedule {
                                    $0.hour = hour
                                    $0.minute = minute
                                }
                            }
                        )
                        ScheduleTimeField(
                            label: "End",
                            hour: viewModel.scheduleTrigger.endHour,
                            minute: viewModel.scheduleTrigger.endMinute,
                            onChange: { hour, minute in
                                viewModel.updateSchedule {
                                    $0.endHour = hour
                                    $0.endMinute = minute
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    if !viewModel.scheduleTrigger.weekdays.isEmpty {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                            ToggleRow(
                                title: "Sound when routine starts",
                                subtitle: "Only when the routine actually starts.",
                                isOn: $viewModel.startAlarmEnabled
                            )
                        }
                    }
                }
                // Reading mode: the whole schedule block is inert, days and times alike.
                .disabled(!isEditing)

                editorSection(
                    title: "Checklist",
                    info: "Tasks from the active routine. Completing them updates this session only and resets on the next routine run."
                ) {
                    CardView(radius: LocktyRadius.medium, padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array($viewModel.tasks.enumerated()), id: \.element.id) { index, $task in
                                RoutineTaskEditorRow(
                                    task: $task,
                                    isEditing: isEditing,
                                    onRemove: {
                                        withAnimation(.smooth(duration: 0.24)) {
                                            viewModel.removeTask(id: task.id)
                                        }
                                    }
                                )

                                if index < viewModel.tasks.count - 1 {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }

                            // Reading mode has no way to add or remove a task.
                            if isEditing {
                                Divider()
                                    .padding(.leading, 20)

                                Button {
                                    withAnimation(.smooth(duration: 0.24)) {
                                        viewModel.addTask()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .regular))
                                        Text("Add task")
                                            .font(LocktyTypography.callout)
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(LocktyColors.secondaryText)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .tappable()
                            }
                        }
                    }
                }

//                editorSection(title: "Breaks") {
//                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
//                        VStack(alignment: .leading, spacing: LocktySpacing.md) {
//                            EditorStepperRow(title: "Maximum breaks", value: $viewModel.maximumBreaks, range: 0...5)
//                            EditorStepperRow(title: "Break duration", suffix: "min", value: $viewModel.maximumBreakMinutes, range: 1...60, isDisabled: viewModel.maximumBreaks == 0)
//                            EditorStepperRow(title: "Minimum interval", suffix: "min", value: $viewModel.minimumBreakIntervalMinutes, range: 1...240, isDisabled: viewModel.maximumBreaks == 0)
//                            ToggleRow(title: "Manual break", isOn: $viewModel.breakTriggerManual, isDisabled: viewModel.maximumBreaks == 0)
//                            ToggleRow(title: "NFC break", isOn: $viewModel.breakTriggerNFC, isDisabled: viewModel.maximumBreaks == 0)
//                            ToggleRow(title: "Location break", isOn: $viewModel.breakTriggerLocation, isDisabled: viewModel.maximumBreaks == 0)
//                        }
//                    }
//                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.xxl)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Hidden only while editing an existing routine, where the checkmark
            // returns to reading. Creating always keeps a way out.
            if !isEditing || isCreating {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.ultraLight)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard isEditing else {
                        withAnimation(.smooth(duration: 0.28)) { isEditing = true }
                        return
                    }

                    Task {
                        if await viewModel.save() {
                            if isCreating {
                                close()
                            } else {
                                // Editing an existing routine returns to reading it,
                                // rather than dismissing the sheet outright.
                                withAnimation(.smooth(duration: 0.28)) { isEditing = false }
                            }
                        }
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .fontWeight(.ultraLight)
                }
            }
        }
        // Only while editing an existing routine: creating one has an xmark and must
        // stay dismissable, otherwise opening it by mistake leaves no way out.
        .interactiveDismissDisabled(isEditing && !isCreating)
        .task {
            await viewModel.load()
        }
        .onChange(of: activeSheet) { _, newValue in
            if newValue == nil {
                viewModel.refreshSelectionState()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .apps:
                RoutineAppPickerSheet(viewModel: viewModel)
            case .domains:
                RoutineDomainsSheet(viewModel: viewModel)
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
    @Bindable var viewModel: RoutineEditorViewModel
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
            VStack(spacing: LocktySpacing.xs) {
                Text(label.uppercased())
                    .locktyEyebrow()
                Text(displayText)
                    .font(.system(size: 20, weight: .light, design: .default))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: displayText)
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.sm)
            .safeGlass(radius: 12, interactive: true)
        }
        .buttonStyle(.plain)
        .tappable()
        .popover(isPresented: $isPresented) {
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
