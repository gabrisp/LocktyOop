import FamilyControls
import OSLog
import SwiftUI

private let routineEditorLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "routines")

struct EditableRoutineTask: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isOptional: Bool

    init(id: UUID = UUID(), title: String = "", isOptional: Bool = false) {
        self.id = id
        self.title = title
        self.isOptional = isOptional
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
    var breakTriggerManual = true
    var breakTriggerNFC = false
    var breakTriggerLocation = false
    var blockedDomains: [String] = []
    var pendingDomain = ""
    var errorMessage: String?
    private(set) var selectedApplicationCount = 0
    private(set) var selectionPreview = FamilyActivitySelection()
    private(set) var mostUsedApplications: [ApplicationUsage] = []

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

    var editingBlockDecision: StrictModeDecision {
        guard let initialRoutineID, routineEngine.activeRoutine()?.routineID == initialRoutineID else {
            return .allowed
        }
        return strictModePolicy.decision(for: .editRoutine, activeRoutine: routineEngine.activeRoutine())
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

    func loadMostUsedApplications() async {
        guard let usage = try? await usageDataService.mostUsedApplications(for: Date()) else { return }
        mostUsedApplications = Array(usage.sorted { $0.duration > $1.duration }.prefix(6))
        print("Routine editor loaded most used applications count=\(mostUsedApplications.count)")
    }

    func isMostUsedApplicationSelected(_ usage: ApplicationUsage) -> Bool {
        guard let token = usage.app.applicationToken else { return false }
        return selectionPreview.applicationTokens.contains(token)
    }

    func toggleMostUsedApplication(_ usage: ApplicationUsage) async {
        guard let token = usage.app.applicationToken else { return }
        var selection = selectionPreview
        if selection.applicationTokens.contains(token) {
            selection.applicationTokens.remove(token)
        } else {
            selection.applicationTokens.insert(token)
        }
        replaceSelection(selection)
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
            .map { EditableRoutineTask(id: $0.id, title: $0.title, isOptional: $0.isOptional) }
        if tasks.isEmpty {
            tasks = [EditableRoutineTask()]
        }
        maximumBreaks = routine.breakPolicy.maximumBreaks
        maximumBreakMinutes = max(Int(routine.breakPolicy.maximumDuration / 60), 1)
        minimumBreakIntervalMinutes = max(Int(routine.breakPolicy.minimumInterval / 60), 1)
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

        let selection = (try? selectionStore.load(scope: selectionScope)) ?? FamilyActivitySelection()
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
            breakPolicy: breakPolicy,
            allowsPauseDuringStrictMode: allowsPauseDuringStrictMode,
            createdAt: createdAt,
            updatedAt: Date()
        )

        do {
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
                isOptional: task.isOptional
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

        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            EditorTopBar(title: "Choose Apps", onClose: { dismiss() })

            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                if !viewModel.mostUsedApplications.isEmpty {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text("Recommended Restrictions")
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                        RoutineAppsMostUsedSection(viewModel: viewModel)
                    }
                }
            }

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
        .task {
            await viewModel.loadMostUsedApplications()
        }
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

    init(
        viewModel: RoutineEditorViewModel,
        router: AppRouter,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.router = router
        self.onCloseEditor = onCloseEditor
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

                RoutineEditorHero(viewModel: viewModel)

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    HStack {
                        Text("Restrictions")
                            .font(LocktyTypography.title)
                            .foregroundStyle(LocktyColors.primaryText)
                        Spacer()
                        Menu {
                            Button {
                                activeSheet = .apps
                            } label: {
                                Text("Apps")
                            }
                            Button {
                                activeSheet = .domains
                            } label: {
                                Text("Websites")
                            }
                        } label: {
                            Text("Add")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LocktyColors.primaryText)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .safeGlass(radius: 18, interactive: true)
                        }
                    }

                    VStack(spacing: LocktySpacing.md) {
                        if !viewModel.selectionPreview.applicationTokens.isEmpty {
                            SelectionPreviewCard(
                                title: viewModel.selectionPreview.applicationTokens.count == 1 ? "1 App" : "\(viewModel.selectionPreview.applicationTokens.count) Apps",
                                tokens: Array(viewModel.selectionPreview.applicationTokens)
                            ) { token in
                                Label(token)
                                    .labelStyle(EditorTokenLabelStyle())
                            }
                        }

                        if !viewModel.selectionPreview.categoryTokens.isEmpty {
                            SelectionPreviewCard(
                                title: viewModel.selectionPreview.categoryTokens.count == 1 ? "1 Category" : "\(viewModel.selectionPreview.categoryTokens.count) Categories",
                                tokens: Array(viewModel.selectionPreview.categoryTokens)
                            ) { token in
                                Label(token)
                                    .labelStyle(EditorTokenLabelStyle())
                            }
                        }

                        if !viewModel.blockedDomains.isEmpty {
                            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                    Text(viewModel.blockedDomains.count == 1 ? "1 Website" : "\(viewModel.blockedDomains.count) Websites")
                                        .font(LocktyTypography.headline)
                                        .foregroundStyle(LocktyColors.primaryText)

                                    DomainChipFlow(domains: viewModel.blockedDomains) { domain in
                                        viewModel.removeDomain(domain)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Schedule")
                        .font(LocktyTypography.title)
                        .foregroundStyle(LocktyColors.primaryText)

                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(spacing: LocktySpacing.md) {
                            ScheduleDaysPicker(
                                selectedWeekdays: Binding(
                                    get: { viewModel.scheduleTrigger.weekdays },
                                    set: { newValue in viewModel.updateSchedule { $0.weekdays = newValue } }
                                )
                            )
                            .frame(maxWidth: .infinity, alignment: .center)

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
                        }
                    }
                }

//                editorSection(title: "Checklist") {
//                    VStack(spacing: LocktySpacing.md) {
//                        ForEach($viewModel.tasks) { $task in
//                            RoutineTaskEditorCard(
//                                task: $task,
//                                onRemove: { viewModel.removeTask(id: task.id) }
//                            )
//                        }
//
//                        SecondaryButton("Add task", systemImage: "plus") {
//                            viewModel.addTask()
//                        }
//                    }
//                }
//
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
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if await viewModel.save() {
                            close()
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
        .task {
            await viewModel.load()
            await viewModel.loadMostUsedApplications()
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
    private func editorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text(title)
                .font(LocktyTypography.title)
                .foregroundStyle(LocktyColors.primaryText)
            content()
        }
    }
}

private struct RoutineEditorHero: View {
    @Bindable var viewModel: RoutineEditorViewModel
    @State private var showIconPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            HStack(alignment: .top, spacing: LocktySpacing.lg) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Name")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md, height: 50) {
                        TextField("Routine name", text: $viewModel.name)
                            .font(LocktyTypography.body)
                            .foregroundStyle(LocktyColors.primaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Icon")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Button {
                        showIconPicker = true
                    } label: {
                        CardView(radius: LocktyRadius.medium, padding: 0, height: 50) {
                            Image(systemName: viewModel.icon.isEmpty ? "repeat" : viewModel.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LocktyColors.primaryText)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .popover(isPresented: $showIconPicker) {
                        RoutineIconPickerSheet(selectedIcon: $viewModel.icon)
                            .presentationCompactAdaptation(.popover)
                    }
                }
                .frame(width: 74, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text("Apps and websites will be blocked while this routine runs.")
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)

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

                HStack(spacing: LocktySpacing.sm) {
//                    BadgeView(
//                        title: viewModel.mode == .strict ? "Strict" : "Normal",
//                        color: viewModel.mode == .strict ? LocktyColors.warning : .accentColor
//                    )
                    BadgeView(
                        title: viewModel.trimmedTasksCount == 1 ? "1 task" : "\(viewModel.trimmedTasksCount) tasks",
                        color: LocktyColors.neutral
                    )
                    BadgeView(
                        title: viewModel.selectedApplicationCount == 1 ? "1 restriction" : "\(viewModel.selectedApplicationCount + viewModel.selectedWebsiteCount) restrictions",
                        color: LocktyColors.warning
                    )
                }
            }
        }
    }
}

private struct RoutineTaskEditorCard: View {
    @Binding var task: EditableRoutineTask
    let onRemove: () -> Void

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                HStack {
                    TextField("Task", text: $task.title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                    Spacer()
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(LocktyColors.unproductive)
                    }
                    .buttonStyle(.plain)
                }

                ToggleRow(title: "Optional", isOn: $task.isOptional)
            }
        }
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
                    .font(.system(size: 20, weight: .light, design: .rounded))
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

private struct SelectionPreviewCard<Token: Hashable, TokenView: View>: View {
    let title: String
    let tokens: [Token]
    let tokenView: (Token) -> TokenView

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text(title)
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: LocktySpacing.sm) {
                        ForEach(tokens, id: \.self) { token in
                            tokenView(token)
                        }
                    }
                }
            }
        }
    }
}

private struct EditorTokenLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: LocktySpacing.sm) {
            configuration.icon
                .frame(width: 42, height: 42)

            configuration.title
                .font(.caption2.weight(.medium))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 82)
        }
        .frame(width: 82, alignment: .center)
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
