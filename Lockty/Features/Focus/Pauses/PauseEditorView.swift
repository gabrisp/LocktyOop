import FamilyControls
import OSLog
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
@Observable
final class PauseEditorViewModel {
    let editingID: UUID
    let draftID: UUID

    var isEnabled = true
    var allowanceMinutes = 5
    var relockAfterAllowance = true
    var steps: [PauseStep] = [.countdown(CountdownConfiguration(duration: 10)), .confirmation(ConfirmationConfiguration())]
    var errorMessage: String?
    private(set) var selectedApplication: AppIdentity?
    private(set) var selectionPreview = FamilyActivitySelection()

    private let initialPauseID: UUID?
    private let repository: PauseRuleRepository
    private let selectionStore: ScreenTimeSelectionStore
    private var hasLoaded = false
    private var createdAt: Date

    init(
        pauseID: UUID?,
        draftID: UUID,
        repository: PauseRuleRepository,
        selectionStore: ScreenTimeSelectionStore
    ) {
        initialPauseID = pauseID
        editingID = pauseID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        createdAt = Date()
        refreshSelectionState()
    }

    var title: String {
        initialPauseID == nil ? "New Pause" : "Edit Pause"
    }

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
        guard let initialPauseID, let rule = await repository.rule(id: initialPauseID) else { return }
        createdAt = rule.createdAt
        isEnabled = rule.isEnabled
        allowanceMinutes = max(Int(rule.allowanceDuration / 60), 1)
        relockAfterAllowance = rule.relockAfterAllowance
        steps = rule.steps
        refreshSelectionState()
        print("Pause editor loaded pauseID=\(initialPauseID.uuidString) selectionApps=\(selectionPreview.applicationTokens.count) steps=\(steps.count)")
    }

    func refreshSelectionState() {
        let selection = (try? selectionStore.load(scope: selectionScope)) ?? FamilyActivitySelection()
        selectionPreview = selection
        let applications = selection.applicationTokens.map(AppIdentity.init(token:))
        selectedApplication = applications.count == 1 ? applications[0] : nil
        print("Pause editor refreshed selection scope=\(selectionScope.id) apps=\(selection.applicationTokens.count)")
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
        try? selectionStore.save(normalized, scope: selectionScope)
        print("Pause editor replaced selection scope=\(selectionScope.id) apps=\(normalized.applicationTokens.count)")
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
        guard let selection = try? selectionStore.load(scope: selectionScope) else {
            errorMessage = "App selection is unavailable."
            return false
        }

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
            isEnabled: isEnabled,
            steps: sanitizedSteps,
            allowanceDuration: TimeInterval(allowanceMinutes * 60),
            relockAfterAllowance: relockAfterAllowance,
            createdAt: createdAt,
            updatedAt: Date()
        )

        await repository.save(rule)
        pauseEditorLogger.notice("Pause editor saved id=\(rule.id.uuidString, privacy: .public) app=\(application.displayName, privacy: .public) steps=\(sanitizedSteps.count)")
        print("Pause editor saved id=\(rule.id.uuidString) app=\(application.displayName) steps=\(sanitizedSteps.count)")
        return true
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
                        isRequired: configuration.isRequired
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
    @State private var viewModel: PauseEditorViewModel
    let router: AppRouter
    let onCloseEditor: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        viewModel: PauseEditorViewModel,
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
                pauseHero(viewModel: viewModel)

                section(title: "Flow") {
                    VStack(spacing: LocktySpacing.md) {
                        ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                            PauseStepEditorCard(
                                index: index + 1,
                                total: viewModel.steps.count,
                                step: binding(for: step.id),
                                onMoveUp: { viewModel.moveStepUp(id: step.id) },
                                onMoveDown: { viewModel.moveStepDown(id: step.id) },
                                onRemove: { viewModel.removeStep(id: step.id) }
                            )
                        }

                        Menu {
                            ForEach(EditablePauseStep.allCases) { type in
                                Button(type.rawValue.capitalized) {
                                    viewModel.addStep(type)
                                }
                            }
                        } label: {
                            SecondaryButton("Add step", systemImage: "plus") { }
                                .allowsHitTesting(false)
                        }
                    }
                }

                section(title: "Allowance") {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: LocktySpacing.md) {
                            EditorStepperRow(title: "Allow for", suffix: "min", value: $viewModel.allowanceMinutes, range: 1...60)
                            ToggleRow(
                                title: "Relock after allowance",
                                subtitle: "Re-apply shields automatically when time expires.",
                                isOn: $viewModel.relockAfterAllowance
                            )
                        }
                    }
                }
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
        .task {
            await viewModel.load()
        }
        .onChange(of: router.sheet) { _, newValue in
            if newValue == nil {
                viewModel.refreshSelectionState()
            }
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
            Text(title)
                .font(LocktyTypography.title)
                .foregroundStyle(LocktyColors.primaryText)
            content()
        }
    }

    @ViewBuilder
    private func pauseHero(viewModel: PauseEditorViewModel) -> some View {
        CardView(radius: LocktyRadius.large, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Button {
                    router.presentSheet(.pauseAppPicker(viewModel.draftID))
                } label: {
                    HStack(spacing: LocktySpacing.md) {
                        if let token = viewModel.selectionPreview.applicationTokens.first {
                            Label(token)
                                .labelStyle(.iconOnly)
                                .frame(width: 48, height: 48)
                                .safeGlass(radius: 16)
                        } else {
                            Image(systemName: "hand.raised.app")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .safeGlass(radius: 16)
                        }

                        VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                            Text(viewModel.selectedAppSummary)
                                .font(LocktyTypography.title)
                                .foregroundStyle(LocktyColors.primaryText)
                            Text("A Pause targets exactly one application.")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                }
                .buttonStyle(.plain)
                .tappable()

                ToggleRow(
                    title: "Pause enabled",
                    subtitle: "Shield secondary action will offer this flow.",
                    isOn: $viewModel.isEnabled
                )

                if let token = viewModel.selectionPreview.applicationTokens.first {
                    Label(token)
                        .font(LocktyTypography.caption)
                        .padding(.horizontal, LocktySpacing.sm)
                        .padding(.vertical, LocktySpacing.sm)
                        .safeGlass(radius: 12)
                }
            }
        }
    }
}

struct PauseAppPickerSheet: View {
    @State private var viewModel: PauseEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PauseEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            EditorTopBar(
                title: "Choose App",
                confirmTitle: "Done",
                onClose: { dismiss() },
                onConfirm: { dismiss() }
            )

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
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

private struct PauseStepEditorCard: View {
    let index: Int
    let total: Int
    @Binding var step: PauseStep
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                HStack(spacing: LocktySpacing.sm) {
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text("\(index). \(step.title)")
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                        Text(step.detail)
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: LocktySpacing.xs) {
                        IconButton(systemImage: "chevron.up", accessibilityLabel: "Move step up", action: onMoveUp)
                            .opacity(index == 1 ? 0.35 : 1)
                            .disabled(index == 1)
                        IconButton(systemImage: "chevron.down", accessibilityLabel: "Move step down", action: onMoveDown)
                            .opacity(index == total ? 0.35 : 1)
                            .disabled(index == total)
                        Button(role: .destructive, action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .safeGlass(radius: 22, interactive: true, tint: LocktyColors.unproductive.opacity(0.14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                switch step {
                case .countdown(let configuration):
                    EditorStepperRow(title: "Duration", suffix: "sec", value: binding(configuration: configuration).duration.intProxy, range: 1...60)

                case .breathing(let configuration):
                    EditorStepperRow(title: "Breaths", value: binding(configuration: configuration).breathCount, range: 1...10)

                case .intention(let configuration):
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        TextField("Prompt", text: binding(configuration: configuration).prompt, axis: .vertical)
                            .font(LocktyTypography.body)
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(2...4)

                        ToggleRow(title: "Required", isOn: binding(configuration: configuration).isRequired)

                        EditorStepperRow(
                            title: "Minimum length",
                            value: Binding(
                                get: { binding(configuration: configuration).minimumLength.wrappedValue ?? 0 },
                                set: { binding(configuration: configuration).minimumLength.wrappedValue = $0 == 0 ? nil : $0 }
                            ),
                            range: 0...100
                        )
                    }

                case .confirmation(let configuration):
                    TextField("Prompt", text: binding(configuration: configuration).prompt, axis: .vertical)
                        .font(LocktyTypography.body)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(2...3)
                }
            }
        }
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

private extension Binding where Value == TimeInterval {
    var intProxy: Binding<Int> {
        Binding<Int>(
            get: { Int(wrappedValue) },
            set: { wrappedValue = TimeInterval($0) }
        )
    }
}
