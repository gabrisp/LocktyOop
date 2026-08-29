import FamilyControls
import Combine
import OSLog
import UserNotifications
import SwiftUI

private let pauseEditorLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "pauses")

enum EditablePauseStep: String, CaseIterable, Identifiable {
    case countdown
    case breathing
    case intention
    case confirmation

    var id: String { rawValue }

    var defaultStep: PauseStep {
        switch self {
        case .countdown:
            return .countdown(CountdownConfiguration(duration: 10))
        case .breathing:
            return .breathing(BreathingConfiguration(breathCount: 3))
        case .intention:
            return .intention(
                IntentionConfiguration(
                    prompt: "Why are you opening this app?",
                    minimumLength: 15,
                    isRequired: true
                )
            )
        case .confirmation:
            return .confirmation(ConfirmationConfiguration())
        }
    }
}

@MainActor
final class PauseEditorViewModel: ObservableObject {
    let editingID: UUID
    let draftID: UUID

    @Published var isEnabled = true
    @Published var customName = ""
    @Published var allowanceMinutes = 5
    @Published var relockAfterAllowance = true
    @Published var steps: [PauseStep] = [.countdown(CountdownConfiguration(duration: 10)), .confirmation(ConfirmationConfiguration())]
    @Published var errorMessage: String?
    @Published private(set) var selectedApplication: AppIdentity?
    @Published private(set) var selectionPreview = FamilyActivitySelection()
    @Published private(set) var suggestedApplications: [AppIdentity] = []

    private let initialPauseID: UUID?
    private let repository: PauseRuleRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let routineEngine: RoutineEngine
    private let pauseEngine: PauseEngine
    private let usageDataService: UsageDataServicing
    private var hasLoaded = false
    private var createdAt: Date

    init(
        pauseID: UUID?,
        draftID: UUID,
        repository: PauseRuleRepository,
        selectionStore: ScreenTimeSelectionStore,
        routineEngine: RoutineEngine,
        pauseEngine: PauseEngine,
        usageDataService: UsageDataServicing
    ) {
        initialPauseID = pauseID
        editingID = pauseID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        self.routineEngine = routineEngine
        self.pauseEngine = pauseEngine
        self.usageDataService = usageDataService
        createdAt = Date()
        refreshSelectionState()
    }

    /// Pauses are part of what a running routine enforces, so they are frozen for as
    /// long as one is active -- creating a new one included.
    var isEditingBlocked: Bool {
        routineEngine.activeRoutine() != nil
    }

    var editingBlockedMessage: String {
        let name = routineEngine.activeRoutine()?.nameSnapshot ?? "A routine"
        return "\(name) is running. Pauses can't be changed until it ends."
    }

    var title: String {
        initialPauseID == nil ? "New Pause" : "Edit Pause"
    }

    var isCreating: Bool { initialPauseID == nil }

    var selectionScope: ScreenTimeSelectionScope {
        .pause(editingID)
    }

    var selectedAppSummary: String {
        guard let selectedApplication else {
            return "Choose one app"
        }
        return selectedApplication.displayName
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        print("Pause editor load started pauseID=\(initialPauseID?.uuidString ?? "new") draftID=\(draftID.uuidString)")
        await loadSuggestedApplications()
        guard let initialPauseID, let rule = await repository.rule(id: initialPauseID) else { return }
        createdAt = rule.createdAt
        customName = rule.customName ?? ""
        isEnabled = rule.isEnabled
        allowanceMinutes = max(Int(rule.allowanceDuration / 60), 1)
        relockAfterAllowance = rule.relockAfterAllowance
        steps = rule.steps
        refreshSelectionState()
        print("Pause editor loaded pauseID=\(initialPauseID.uuidString) selectionApps=\(selectionPreview.applicationTokens.count) steps=\(steps.count)")
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
            print("Pause editor loaded suggested applications count=\(suggestedApplications.count)")
        } catch {
            print("Pause editor failed loading suggested applications: \(error.localizedDescription)")
        }
    }

    func refreshSelectionState() {
        do {
            let selection = try selectionStore.load(scope: selectionScope)
            selectionPreview = selection
            let applications = selection.applicationTokens.map(AppIdentity.init(token:))
            selectedApplication = applications.count == 1 ? applications[0] : nil
            print("Pause editor refreshed selection scope=\(selectionScope.id) apps=\(selection.applicationTokens.count)")
        } catch {
            selectionPreview = FamilyActivitySelection()
            selectedApplication = nil
            errorMessage = error.localizedDescription
            print("Pause editor failed refreshing selection scope=\(selectionScope.id): \(error.localizedDescription)")
        }
    }

    func replaceSelection(_ selection: FamilyActivitySelection) {
        var normalized = selection
        normalized.categoryTokens = []
        normalized.webDomainTokens = []
        if normalized.applicationTokens.count > 1, let kept = normalized.applicationTokens.first {
            normalized.applicationTokens = [kept]
        }
        selectionPreview = normalized
        let applications = normalized.applicationTokens.map(AppIdentity.init(token:))
        selectedApplication = applications.count == 1 ? applications[0] : nil
        do {
            try selectionStore.save(normalized, scope: selectionScope)
            print("Pause editor replaced selection scope=\(selectionScope.id) apps=\(normalized.applicationTokens.count)")
        } catch {
            errorMessage = error.localizedDescription
            print("Pause editor failed replacing selection scope=\(selectionScope.id): \(error.localizedDescription)")
        }
    }

    func addStep(_ type: EditablePauseStep) {
        steps.append(type.defaultStep)
    }

    func removeStep(id: UUID) {
        steps.removeAll { $0.id == id }
    }

    func moveStepUp(id: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == id }), index > 0 else { return }
        steps.swapAt(index, index - 1)
    }

    func moveStepDown(id: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == id }), index < steps.count - 1 else { return }
        steps.swapAt(index, index + 1)
    }

    func save() async -> Bool {
        guard !isEditingBlocked else {
            errorMessage = editingBlockedMessage
            return false
        }

        let selection = selectionPreview

        let selectedApps = selection.applicationTokens.map(AppIdentity.init(token:))
        guard selectedApps.count == 1, let application = selectedApps.first else {
            errorMessage = "A Pause must target exactly one application."
            return false
        }

        let sanitizedSteps = sanitizeSteps()
        guard !sanitizedSteps.isEmpty else {
            errorMessage = "Add at least one Pause step."
            return false
        }

        let rule = PauseRule(
            id: editingID,
            application: application,
            customName: customName,
            isEnabled: isEnabled,
            steps: sanitizedSteps,
            allowanceDuration: TimeInterval(allowanceMinutes * 60),
            relockAfterAllowance: relockAfterAllowance,
            createdAt: createdAt,
            updatedAt: Date()
        )

        do {
            try selectionStore.save(selection, scope: selectionScope)
            try await repository.save(rule)
            // Saving the rule is not enough on its own -- the shield has to be rebuilt
            // and applied, or the Pause exists but its app is never actually blocked.
            await pauseEngine.refreshShields()
            // The shield can't open the app itself; it posts a notification whose tap
            // brings the user here to run the flow. Ask for permission now, when the
            // Pause that depends on it is created, rather than leaving it to the
            // System Access screen the user may never visit.
            await requestNotificationAuthorizationIfNeeded()
            pauseEditorLogger.notice("Pause editor saved id=\(rule.id.uuidString, privacy: .public) app=\(application.displayName, privacy: .public) steps=\(sanitizedSteps.count)")
            print("Pause editor saved id=\(rule.id.uuidString) app=\(application.displayName) steps=\(sanitizedSteps.count)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Pause editor failed saving id=\(rule.id.uuidString): \(error.localizedDescription)")
            return false
        }
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func sanitizeSteps() -> [PauseStep] {
        steps.compactMap { step in
            switch step {
            case .countdown(let configuration):
                return configuration.duration > 0 ? step : nil
            case .breathing(let configuration):
                return configuration.breathCount > 0 ? step : nil
            case .intention(let configuration):
                let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                return prompt.isEmpty ? nil : .intention(
                    IntentionConfiguration(
                        id: configuration.id,
                        prompt: prompt,
                        minimumLength: configuration.minimumLength,
                        isRequired: true
                    )
                )
            case .confirmation(let configuration):
                let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                return .confirmation(ConfirmationConfiguration(id: configuration.id, prompt: prompt.isEmpty ? "Do you still want to continue?" : prompt))
            }
        }
    }
}

struct PauseEditorView: View {
    @StateObject private var viewModel: PauseEditorViewModel
    let router: AppRouter
    let onCloseEditor: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showAppPicker = false
    @State private var showNameInfo = false
    /// Opening an existing Pause reads it; the pencil turns it into an editor. Creating
    /// one starts in editing, the same way the routine editor behaves.
    @State private var isEditing: Bool

    init(
        viewModel: PauseEditorViewModel,
        router: AppRouter,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isEditing = State(initialValue: viewModel.isCreating && !viewModel.isEditingBlocked)
        self.router = router
        self.onCloseEditor = onCloseEditor
    }

    private var isCreating: Bool { viewModel.isCreating }

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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                if viewModel.isEditingBlocked {
                    EditingDisabledBanner(message: viewModel.editingBlockedMessage)
                }

                pauseHero(viewModel: viewModel)

                section(title: "Flow") {
                    VStack(spacing: LocktySpacing.md) {
                        ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { _, step in
                            PauseStepEditorCard(
                                step: binding(for: step.id),
                                isEditing: isEditing,
                                onRemove: {
                                    withAnimation(.smooth(duration: 0.24)) {
                                        viewModel.removeStep(id: step.id)
                                    }
                                }
                            )
                        }

                        if isEditing {
                        Menu {
                            ForEach(EditablePauseStep.allCases) { type in
                                Button(type.rawValue.capitalized) {
                                    withAnimation(.smooth(duration: 0.24)) {
                                        viewModel.addStep(type)
                                    }
                                }
                            }
                        } label: {
                            Text("New Step")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, LocktySpacing.md)
                                .safeGlass(radius: LocktyRadius.medium, interactive: true)
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }

                section(title: "Allowance") {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text("Duration")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)

                        Text(LocktyDurationFormatter.abbreviated(TimeInterval(viewModel.allowanceMinutes * 60)))
                            .font(.system(size: 28, weight: .light, design: .rounded))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: viewModel.allowanceMinutes)

                        DurationSlider(
                            value: Binding(
                                get: { Double(viewModel.allowanceMinutes) },
                                set: { viewModel.allowanceMinutes = Int($0) }
                            ),
                            range: 1...60
                        )
                    }
                    .padding(LocktySpacing.md)
                    .background(LocktyColors.elevatedBackground, in: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous))

                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        ToggleRow(
                            title: "Relock after allowance",
                            subtitle: "Re-apply shields automatically when time expires.",
                            isOn: $viewModel.relockAfterAllowance
                        )
                    }
                }
                // Reading mode: the allowance slider and relock switch are inert.
                .disabled(!isEditing)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.xxl)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Hidden only while editing an existing Pause, where the checkmark returns
            // to reading. Creating always keeps a way out.
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

            // No pencil at all while a routine is running: there is nothing to switch
            // into, so the editor stays a reader.
            if !viewModel.isEditingBlocked {
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
        }
        .interactiveDismissDisabled(isEditing && !isCreating)
        .task {
            await viewModel.load()
        }
        .onChange(of: showAppPicker) { _, newValue in
            if !newValue {
                viewModel.refreshSelectionState()
            }
        }
        .sheet(isPresented: $showAppPicker) {
            PauseAppPickerSheet(viewModel: viewModel)
        }
        .alert(
            "Could not save Pause",
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

    private func binding(for stepID: UUID) -> Binding<PauseStep> {
        Binding(
            get: {
                viewModel.steps.first(where: { $0.id == stepID }) ?? .confirmation(ConfirmationConfiguration())
            },
            set: { newValue in
                guard let index = viewModel.steps.firstIndex(where: { $0.id == stepID }) else { return }
                viewModel.steps[index] = newValue
            }
        )
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Rectangle()
                .fill(LocktyColors.separator)
                .frame(height: 0.5)
            Text(title.uppercased())
                .locktyEyebrow()
            content()
        }
    }

    @ViewBuilder
    private func appIcon(viewModel: PauseEditorViewModel) -> some View {
        if let token = viewModel.selectionPreview.applicationTokens.first {
            // .id(token): SwiftUI reuses the existing Label in place when the token
            // changes, so without this it keeps drawing the previously selected icon.
            Label(token)
                .labelStyle(.iconOnly)
                .id(token)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LocktyColors.primaryText)
        }
    }

    @ViewBuilder
    private func pauseHero(viewModel: PauseEditorViewModel) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            VStack(spacing: LocktySpacing.sm) {
                Text(viewModel.title)
                    .font(.footnote)
                    .foregroundStyle(LocktyColors.tertiaryText)

                // Reading mode is inert: the app tile loses its tappable glass and the
                // name loses its field background, so nothing invites an edit.
                if isEditing {
                    Button {
                        showAppPicker = true
                    } label: {
                        appIcon(viewModel: viewModel)
                            .frame(width: 50, height: 50)
                            .safeGlass(radius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                } else {
                    appIcon(viewModel: viewModel)
                        .frame(width: 50, height: 50)
                }

                HStack(spacing: LocktySpacing.xs) {
                    if isEditing {
                    CardView(
                        radius: 14,
                        padding: 0,
                        expandsHorizontally: false
                    ) {
                        ZStack {
                            // Invisible sizing text so the field hugs its content.
                            Text(viewModel.customName.isEmpty ? "Pause name" : "\(viewModel.customName) ")
                                .font(LocktyTypography.body)
                                .foregroundStyle(.clear)
                                .lineLimit(1)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)

                            TextField("Pause name", text: $viewModel.customName)
                                .font(LocktyTypography.body)
                                .foregroundStyle(LocktyColors.primaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                        }
                    }
                    .frame(maxWidth: 320)
                    } else {
                        Text(viewModel.customName)
                            .font(LocktyTypography.body)
                            .foregroundStyle(LocktyColors.primaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .frame(maxWidth: 320)
                    }

                    Button {
                        showNameInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .popover(isPresented: $showNameInfo) {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                            Text("You can give this Pause a custom name. Apple only hands apps an anonymous token for your selection, so Lockty can't read the app's real name — a name you set here is what it will be called.")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.primaryText)
                                .frame(width: 240, alignment: .leading)
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct PauseAppPickerSheet: View {
    @ObservedObject var viewModel: PauseEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyActivitySelectionView(
            title: "Seleccionadas",
            addLabel: "Añadir App",
            selection: Binding(
                get: { viewModel.selectionPreview },
                set: { newValue in
                    withAnimation(.smooth(duration: 0.28)) {
                        viewModel.replaceSelection(newValue)
                    }
                }
            ),
            rules: .pause,
            suggestions: viewModel.suggestedApplications,
            onClose: { dismiss() },
            onDone: { dismiss() }
        )
        .presentationDetents([.large])
    }
}


private struct PauseStepEditorCard: View {
    @Binding var step: PauseStep
    var isEditing: Bool = true
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack {
                Text(step.title)
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)
                Spacer()
                if isEditing {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            switch step {
            case .countdown(let configuration):
                Text("\(Int(configuration.duration)) s")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: configuration.duration)

                DurationSlider(value: binding(configuration: configuration).duration, range: 1...60)

            case .breathing(let configuration):
                Text("\(configuration.breathCount) breaths")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: configuration.breathCount)

                DurationSlider(value: binding(configuration: configuration).breathCount.doubleProxy, range: 1...10)

            case .intention(let configuration):
                TextField("Prompt", text: binding(configuration: configuration).prompt, axis: .vertical)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(2...4)

            case .confirmation(let configuration):
                TextField("Prompt", text: binding(configuration: configuration).prompt, axis: .vertical)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2...3)
            }
        }
        // Reading mode: sliders and prompt fields are inert, the step still reads.
        .disabled(!isEditing)
        .padding(LocktySpacing.md)
        .background(LocktyColors.elevatedBackground, in: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous))
    }

    private func binding(configuration: CountdownConfiguration) -> Binding<CountdownConfiguration> {
        Binding(
            get: { configuration },
            set: { step = .countdown($0) }
        )
    }

    private func binding(configuration: BreathingConfiguration) -> Binding<BreathingConfiguration> {
        Binding(
            get: { configuration },
            set: { step = .breathing($0) }
        )
    }

    private func binding(configuration: IntentionConfiguration) -> Binding<IntentionConfiguration> {
        Binding(
            get: { configuration },
            set: { step = .intention($0) }
        )
    }

    private func binding(configuration: ConfirmationConfiguration) -> Binding<ConfirmationConfiguration> {
        Binding(
            get: { configuration },
            set: { step = .confirmation($0) }
        )
    }
}

private extension Binding where Value == CountdownConfiguration {
    var duration: Binding<TimeInterval> {
        Binding<TimeInterval>(
            get: { wrappedValue.duration },
            set: {
                var copy = wrappedValue
                copy.duration = $0
                wrappedValue = copy
            }
        )
    }
}

private extension Binding where Value == Int {
    var doubleProxy: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Int($0) }
        )
    }
}

private struct DurationSlider: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>

    var body: some View {
        Slider(value: value, in: range)
            .tint(LocktyColors.primaryText)
    }
}
