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
    var colorHex: String = RoutineIconColorCatalog.colors.first ?? "#0A84FF"
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

    var isScheduleEnabled: Bool {
        scheduleTrigger != nil
    }

    var scheduleTrigger: RoutineSchedule? {
        for trigger in triggers {
            if case .schedule(let schedule) = trigger { return schedule }
        }
        return nil
    }

    var triggersSummary: String {
        isScheduleEnabled ? "Manual + Schedule" : "Manual"
    }

    func setScheduleEnabled(_ enabled: Bool) {
        if enabled {
            guard scheduleTrigger == nil else { return }
            triggers.append(.schedule(RoutineSchedule(
                hour: 9,
                minute: 0,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            )))
        } else {
            triggers.removeAll { if case .schedule = $0 { true } else { false } }
        }
        if triggers.isEmpty {
            triggers = [.manual]
        }
    }

    func updateSchedule(_ transform: (inout RoutineSchedule) -> Void) {
        guard let index = triggers.firstIndex(where: { if case .schedule = $0 { true } else { false } }) else { return }
        guard case .schedule(var schedule) = triggers[index] else { return }
        transform(&schedule)
        triggers[index] = .schedule(schedule)
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
        colorHex = routine.colorHex ?? colorHex
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
        let selection = (try? selectionStore.load(scope: selectionScope)) ?? FamilyActivitySelection()
        selectionPreview = selection
        selectedApplicationCount = selection.applicationTokens.count
        print("Routine editor refreshed selection scope=\(selectionScope.id) apps=\(selection.applicationTokens.count)")
    }

    func replaceSelection(_ selection: FamilyActivitySelection) {
        var normalized = selection
        normalized.categoryTokens = []
        normalized.webDomainTokens = []
        selectionPreview = normalized
        selectedApplicationCount = normalized.applicationTokens.count
        try? selectionStore.save(normalized, scope: selectionScope)
        print("Routine editor replaced selection scope=\(selectionScope.id) apps=\(normalized.applicationTokens.count)")
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
            colorHex: colorHex,
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
            EditorTopBar(
                title: "Choose Apps",
                confirmTitle: "Done",
                onClose: { dismiss() },
                onConfirm: { dismiss() }
            )

            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text("Choose the applications this routine will restrict.")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                        Text("Selection is saved instantly.")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                }

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
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

struct RoutineEditorView: View {
    @State private var viewModel: RoutineEditorViewModel
    let router: AppRouter
    let onCloseEditor: () -> Void
    @Environment(\.dismiss) private var dismiss

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
        @Bindable var viewModel = viewModel

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                if viewModel.isEditingBlocked {
                    EditingDisabledBanner(message: viewModel.editingBlockDecision.reason ?? "This routine cannot be edited right now.")
                }

                RoutineEditorHero(viewModel: viewModel, router: router)

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    HStack {
                        Text("Restrictions")
                            .font(LocktyTypography.title)
                            .foregroundStyle(LocktyColors.primaryText)
                        Spacer()
                        Menu {
                            Button {
                                router.presentSheet(.routineAppPicker(viewModel.draftID))
                            } label: {
                                Label("Apps", systemImage: "app.badge.checkmark")
                            }
                            Button {
                                router.presentSheet(.routineDomains(viewModel.draftID))
                            } label: {
                                Label("Websites", systemImage: "globe")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LocktyColors.primaryText)
                                .frame(width: 32, height: 32)
                                .safeGlass(radius: 16, interactive: true)
                        }
                    }

                    VStack(spacing: LocktySpacing.md) {
                        if !viewModel.selectionPreview.applicationTokens.isEmpty {
                            SelectionPreviewCard(selection: viewModel.selectionPreview)
                        }

                        if !viewModel.blockedDomains.isEmpty {
                            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                    Text("Websites (\(viewModel.blockedDomains.count))")
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
                    Text("Triggers")
                        .font(LocktyTypography.title)
                        .foregroundStyle(LocktyColors.primaryText)

                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(spacing: LocktySpacing.md) {
                            ToggleRow(
                                title: "Schedule",
                                subtitle: viewModel.isScheduleEnabled ? "Starts automatically on selected days." : "Manual start only.",
                                isOn: Binding(
                                    get: { viewModel.isScheduleEnabled },
                                    set: { viewModel.setScheduleEnabled($0) }
                                )
                            )

                            if let schedule = viewModel.scheduleTrigger {
                                VStack(spacing: LocktySpacing.md) {
                                    ScheduleDaysPicker(
                                        selectedWeekdays: Binding(
                                            get: { schedule.weekdays },
                                            set: { newValue in viewModel.updateSchedule { $0.weekdays = newValue } }
                                        )
                                    )
                                    .frame(maxWidth: .infinity, alignment: .center)

                                    HStack(spacing: LocktySpacing.md) {
                                        Picker("Hour", selection: Binding(
                                            get: { schedule.hour },
                                            set: { newValue in viewModel.updateSchedule { $0.hour = newValue } }
                                        )) {
                                            ForEach(0..<24, id: \.self) { hour in
                                                Text(String(format: "%02d", hour)).tag(hour)
                                            }
                                        }
                                        .pickerStyle(.wheel)
                                        .frame(maxWidth: .infinity)

                                        Picker("Minute", selection: Binding(
                                            get: { schedule.minute },
                                            set: { newValue in viewModel.updateSchedule { $0.minute = newValue } }
                                        )) {
                                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                                Text(String(format: "%02d", minute)).tag(minute)
                                            }
                                        }
                                        .pickerStyle(.wheel)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .frame(height: 120)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
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
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeSafeAreaBar(edge: .top, spacing: 0) {
            EditorTopBar(
                title: viewModel.title,
                confirmTitle: "Save",
                onClose: { close() },
                onConfirm: {
                    Task {
                        if await viewModel.save() {
                            close()
                        }
                    }
                }
            )
        }
        .tint(Color(hex: viewModel.colorHex))
        .task {
            await viewModel.load()
            await viewModel.loadMostUsedApplications()
        }
        .onChange(of: router.sheet) { _, newValue in
            if newValue == nil {
                viewModel.refreshSelectionState()
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
    let router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack(alignment: .top, spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Name")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        TextField("Routine name", text: $viewModel.name)
                            .font(LocktyTypography.body)
                            .foregroundStyle(LocktyColors.primaryText)
                    }
                }

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Icon")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Button {
                        router.presentSheet(.routineIconPicker(viewModel.draftID))
                    } label: {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.sm) {
                            Image(systemName: viewModel.icon.isEmpty ? "repeat" : viewModel.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LocktyColors.primaryText)
                                .frame(width: 24, height: 24)
                                .frame(width: 48, height: 48)
                        }
                    }
                    .buttonStyle(.plain)
                    .tappable()
                }
                .frame(width: 72, alignment: .leading)

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Color")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Button {
                        router.presentSheet(.routineColorPicker(viewModel.draftID))
                    } label: {
                        Circle()
                            .fill(Color(hex: viewModel.colorHex))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Circle().stroke(LocktyColors.cardStroke, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .tappable()
                }
                .frame(width: 72, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text("Apps and websites will be blocked while this routine runs.")
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)

                Picker("Mode", selection: $viewModel.mode) {
                    Text("Normal").tag(RoutineMode.normal)
                    Text("Strict").tag(RoutineMode.strict)
                }
                .pickerStyle(.segmented)

//                ToggleRow(
//                    title: "Allow Pause during Strict Mode",
//                    subtitle: "Pause stays available only if this is enabled.",
//                    isOn: $viewModel.allowsPauseDuringStrictMode,
//                    isDisabled: viewModel.mode == .normal
//                )

                HStack(spacing: LocktySpacing.sm) {
                    BadgeView(
                        title: viewModel.mode == .strict ? "Strict" : "Normal",
                        color: viewModel.mode == .strict ? LocktyColors.warning : .accentColor
                    )
                    BadgeView(
                        title: "\(viewModel.trimmedTasksCount) tasks",
                        color: LocktyColors.neutral
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

private struct SelectionPreviewCard: View {
    let selection: FamilyActivitySelection

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text("Selected apps (\(selection.applicationTokens.count))")
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    ForEach(Array(selection.applicationTokens), id: \.self) { token in
                        Label(token)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, LocktySpacing.xs)
                    }
                }
            }
        }
    }
}

struct EditorTopBar: View {
    let title: String
    let confirmTitle: String
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            IconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
            Spacer()
            Text(title)
                .font(LocktyTypography.headline)
                .foregroundStyle(LocktyColors.primaryText)
            Spacer()
            IconButton(systemImage: "checkmark", accessibilityLabel: confirmTitle, action: onConfirm)
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
