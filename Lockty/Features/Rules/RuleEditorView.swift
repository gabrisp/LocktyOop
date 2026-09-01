import Combine
import FamilyControls
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
        toastCenter: LocktyToastCenter
    ) {
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
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selectedAppGroupIDs.isEmpty else {
            errorMessage = "Select at least one app or group."
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
            appGroupIDs: selectedAppGroupIDs,
            blockedApplications: Set(selection.applicationTokens.map(AppIdentity.ID.init(token:))),
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
    @State private var isNaming = false
    @State private var isShowingKindChoice: Bool
    @State private var isConfirmingDiscard = false
    /// Raised by the back chevron when this step has unsaved edits.
    @State private var isConfirmingBack = false
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
    }

    private var sheetAnimation: Animation { .snappy(duration: 0.4, extraBounce: 0.02) }
    private var cardFill: Color { Color.white.opacity(0.055) }
    private var cardRadius: CGFloat { 22 }

    private var chromeID: String {
        "\(contentID)-\(viewModel.name)-\(viewModel.kind?.rawValue ?? "none")"
    }

    private var contentID: String {
        if isShowingKindChoice { return "kind-choice" }
        if viewModel.kind == .schedule { return "schedule" }
        if let activeSheet { return activeSheet.id }
        if isNaming { return "naming" }
        return "editor"
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
            blocked: viewModel.hasChanges && !isShowingKindChoice && activeSheet == nil,
            onAttempt: requestClose
        )
        .confirmationDialog(
            "Discard changes?",
            isPresented: $isConfirmingBack,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { returnToKindChoice() }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { returnToParentOrDismiss() }
            Button("Keep editing", role: .cancel) {}
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
                kindChoiceContent
                    .locktyDynamicSheetChrome(id: chromeID) {
                        chromeTitleText("Create Rule")
                    } leading: {
                        LocktyDynamicSheetBarButton(action: requestClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                        }
                    } trailing: {
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .geometryGroup()
                    .transition(screenTransition)
            } else if viewModel.kind == .schedule {
                makeScheduleRuleEditor(returnToKindChoice)
                    .geometryGroup()
                    .transition(screenTransition)
            } else {
                editorScaffold
                    .geometryGroup()
                    .transition(screenTransition)
            }
        }
        .geometryGroup()
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
        case nil:
            // The generated name, not "New Rule": the rule already has a name by the
            // time this is on screen, and showing a placeholder over a filled field
            // would be the header disagreeing with the form under it.
            chromeTitleText(isNaming ? "Name" : (viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Regla" : viewModel.name))
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
        if activeSheet != nil {
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
            LocktyDynamicSheetBarButton(action: enterNaming) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
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
                kindTile(kind: .openCountLimit, subtitle: "App open limit")
                kindTile(kind: .dailyUsageLimit, subtitle: "Daily time limit")
                kindTile(kind: .sessionDurationLimit, subtitle: "Session time limit")
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
        }
    }

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
        .padding(.horizontal, LocktySpacing.lg)
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
        }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
    }

    private var appsRow: some View {
        Button {
            openChildSheet(.apps)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps seleccionadas")
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
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
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
            .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))

            if viewModel.breaksAllowed {
                VStack(spacing: 0) {
                    menuRow(
                        title: "Max breaks",
                        valueText: "\(viewModel.maximumBreaks)",
                        options: Array(1...8),
                        format: { "\($0)" },
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
                .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))

                sectionHeading("Friction", systemImage: "sparkles.rectangle.stack")

                frictionSelectionCard
            }
        }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.md)
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
    }

    private var selectionScreen: some View {
        VStack {
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
                    rules: .routine,
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
            .overlay(Color.white.opacity(0.10))
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
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white))
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
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white))
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
            .buttonStyle(.plain)
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
                        .fill(isSelected ? Color.white : Color.white.opacity(0.06))
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
        .background(RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardFill))
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
        isConfirmingBack = true
    }

    private func returnToKindChoice() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            isShowingKindChoice = true
            viewModel.kind = nil
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

    private func requestClose() {
        guard viewModel.hasChanges else {
            returnToParentOrDismiss()
            return
        }
        isConfirmingDiscard = true
    }
}
