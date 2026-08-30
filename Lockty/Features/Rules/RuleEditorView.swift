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
    @Published private(set) var selectionPreview = FamilyActivitySelection()
    @Published private(set) var selectedApplicationCount = 0
    @Published private(set) var frictions: [Friction] = []

    private let repository: RuleRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let frictionRepository: FrictionRepository
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
    }

    init(
        ruleID: UUID?,
        draftID: UUID,
        repository: RuleRepository,
        selectionStore: ScreenTimeSelectionStore,
        frictionRepository: FrictionRepository
    ) {
        self.initialRuleID = ruleID
        self.editingID = ruleID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
        self.frictionRepository = frictionRepository
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
            selectedApplicationCount: selectedApplicationCount
        )
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await loadFrictions()

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
        maximumOpens = rule.openCountLimitConfiguration?.maximumOpens ?? 10
        openCountWindowHours = rule.openCountLimitConfiguration?.windowHours ?? 24
        maximumDailyMinutes = rule.dailyUsageLimitConfiguration?.maximumMinutesPerDay ?? 30
        dailyResetPeriod = rule.dailyUsageLimitConfiguration?.resetPeriod ?? .daily
        maximumSessionMinutes = rule.sessionDurationLimitConfiguration?.maximumMinutesPerSession ?? 5
        maximumBreaks = rule.breakPolicy.maximumBreaks
        maximumBreakMinutes = max(rule.breakPolicy.durationMinutes ?? 5, 1)
        minimumBreakIntervalMinutes = max(rule.breakPolicy.cooldownMinutes, 1)
        breakResetPeriod = rule.breakPolicy.resetPeriod
        requiredFrictionID = rule.breakPolicy.requiredFrictionID
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
        guard !selection.applicationTokens.isEmpty else {
            errorMessage = "Select at least one app."
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
            blockedApplications: Set(selection.applicationTokens.map(AppIdentity.ID.init(token:))),
            openCountLimitConfiguration: kind == .openCountLimit
                ? OpenCountLimitRuleConfiguration(
                    maximumOpens: maximumOpens,
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

    func discardDraft() {
        try? selectionStore.remove(scope: draftSelectionScope)
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
        .interactiveDismissDisabled(viewModel.hasChanges && !isShowingKindChoice && activeSheet == nil)
        .confirmationDialog(
            "¿Descartar los cambios?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) { returnToParentOrDismiss() }
            Button("Seguir editando", role: .cancel) {}
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
            chromeTitleText("Seleccionadas")
        case .breakSettings:
            chromeTitleText("Break")
        case nil:
            chromeTitleText(isNaming ? "Nombre" : (viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Rule" : viewModel.name))
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
        } else {
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
                kindTile(kind: .schedule, subtitle: "Schedule based routine")
                kindTile(kind: .openCountLimit, subtitle: "Max opens in a time window")
                kindTile(kind: .dailyUsageLimit, subtitle: "Max minutes per day")
                kindTile(kind: .sessionDurationLimit, subtitle: "Max minutes per session")
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
        }
    }

    private func kindTile(kind: RuleKind, subtitle: String) -> some View {
        Button {
            viewModel.setKind(kind)
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

                    Text(kind.title)
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
            TextField("Nombre", text: $viewModel.name)
                .focused($isNameFieldFocused)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.lg)
                .padding(.vertical, LocktySpacing.md)
                .background(Capsule(style: .continuous).fill(LocktyColors.elevatedBackground))

            Text(viewModel.kind?.title ?? "")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.vertical, LocktySpacing.lg)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Rule type", systemImage: symbolName(for: viewModel.kind ?? .openCountLimit))

            summaryCard(
                title: viewModel.kind?.title ?? "Rule",
                subtitle: conditionSummary
            )

            sectionHeading("Condition", systemImage: "line.3.horizontal.decrease.circle")

            conditionCard

            sectionHeading("Apps blocked", systemImage: "lock.shield")

            appsRow

            breakRow

            LocktyHoldButton(title: viewModel.isCreating ? "Mantén para confirmar" : "Mantén para guardar") {
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
                menuRow(
                    title: "Max opens",
                    valueText: "\(viewModel.maximumOpens)",
                    options: Array(1...50),
                    format: { "\($0)" },
                    selection: Binding(
                        get: { viewModel.maximumOpens },
                        set: { viewModel.maximumOpens = $0 }
                    )
                )

                dividerInset

                menuRow(
                    title: "Window",
                    valueText: "\(viewModel.openCountWindowHours) h",
                    options: Array(1...24),
                    format: { "\($0) h" },
                    selection: Binding(
                        get: { viewModel.openCountWindowHours },
                        set: { viewModel.openCountWindowHours = $0 }
                    )
                )
            case .dailyUsageLimit:
                menuRow(
                    title: "Daily usage",
                    valueText: "\(viewModel.maximumDailyMinutes) min",
                    options: Array(stride(from: 5, through: 360, by: 5)),
                    format: { "\($0) min" },
                    selection: Binding(
                        get: { viewModel.maximumDailyMinutes },
                        set: { viewModel.maximumDailyMinutes = $0 }
                    )
                )

                dividerInset

                resetPeriodRow(selection: $viewModel.dailyResetPeriod)
            case .sessionDurationLimit:
                menuRow(
                    title: "Session limit",
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
                    Text("Apps selected")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(viewModel.selectedApplicationCount == 0 ? "Choose apps" : "\(viewModel.selectedApplicationCount) selected")
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

                    Text(viewModel.breaksAllowed ? "This rule can open a temporary exception after a friction." : "Blocked means blocked.")
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer(minLength: 0)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { viewModel.breaksAllowed },
                        set: { viewModel.setBreaksAllowed($0) }
                    )
                )
                .labelsHidden()
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
                suggestions: [],
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

    private var breakSummary: String {
        guard viewModel.breaksAllowed else { return "No breaks allowed" }
        let breakCount = viewModel.maximumBreaks == 1 ? "1 break" : "\(viewModel.maximumBreaks) breaks"
        let duration = "\(viewModel.maximumBreakMinutes)m"
        let friction = viewModel.selectedFriction?.name ?? "Choose friction"
        return "\(breakCount) · \(duration) · \(friction)"
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
        options: [Int],
        format: @escaping (Int) -> String,
        selection: Binding<Int>
    ) -> some View {
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
            HStack(spacing: LocktySpacing.md) {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: 0)

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
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
