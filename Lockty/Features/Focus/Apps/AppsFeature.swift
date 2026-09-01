import Combine
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
final class AppsLibraryViewModel: ObservableObject {
    private let appGroupRepository: UserAppGroupRepository
    private let autoFocusManager: AutoFocusManager
    private let selectionStore: ScreenTimeSelectionStore
    private let routineEngine: RoutineEngine

    @Published private(set) var appGroups: [AppGroup] = []
    @Published private(set) var groupTokens: [UUID: [ApplicationToken]] = [:]
    @Published private(set) var distractingTokens: [ApplicationToken] = []
    @Published private(set) var alwaysAllowedTokens: [ApplicationToken] = []
    /// Whether the Always Allowed folder can be opened at all.
    ///
    /// It cannot while a routine is running. This is the one list that overrides every
    /// block, so editing it mid-routine is a way to walk straight out of a routine you
    /// committed to -- add the app, and the shield it was holding is gone. Other rule
    /// kinds do not lock it: they are limits you set for yourself, not a session you are
    /// currently inside.
    @Published private(set) var isAlwaysAllowedLocked = false

    init(
        appGroupRepository: UserAppGroupRepository,
        autoFocusManager: AutoFocusManager,
        selectionStore: ScreenTimeSelectionStore,
        routineEngine: RoutineEngine
    ) {
        self.appGroupRepository = appGroupRepository
        self.autoFocusManager = autoFocusManager
        self.selectionStore = selectionStore
        self.routineEngine = routineEngine
    }

    func load() async {
        let groups = await appGroupRepository.appGroups()
        var tokenMap: [UUID: [ApplicationToken]] = [:]
        for group in groups {
            let selection = (try? selectionStore.load(scope: .appGroup(group.id))) ?? FamilyActivitySelection()
            tokenMap[group.id] = selection.applicationTokens.stablePrefix(selection.applicationTokens.count)
        }

        let distractingSelection = autoFocusManager.distractingSelection()
        let allowedSelection = (try? selectionStore.load(scope: .alwaysAllowed)) ?? FamilyActivitySelection()
        let locked = !routineEngine.activeRoutines.isEmpty

        withAnimation(.smooth(duration: 0.25)) {
            appGroups = groups
            groupTokens = tokenMap
            distractingTokens = distractingSelection.applicationTokens.stablePrefix(distractingSelection.applicationTokens.count)
            alwaysAllowedTokens = allowedSelection.applicationTokens.stablePrefix(allowedSelection.applicationTokens.count)
            isAlwaysAllowedLocked = locked
        }
    }

    func tokens(for groupID: UUID) -> [ApplicationToken] {
        groupTokens[groupID] ?? []
    }
}

@MainActor
final class AppGroupEditorViewModel: ObservableObject {
    let editingID: UUID
    let draftID: UUID

    @Published var name = ""
    @Published private(set) var selectionPreview = FamilyActivitySelection()
    @Published var errorMessage: String?

    private let repository: UserAppGroupRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let initialGroupID: UUID?
    private var hasLoaded = false
    private var createdAt = Date()

    init(
        appGroupID: UUID?,
        draftID: UUID,
        repository: UserAppGroupRepository,
        selectionStore: ScreenTimeSelectionStore
    ) {
        initialGroupID = appGroupID
        editingID = appGroupID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        self.selectionStore = selectionStore
    }

    var isCreating: Bool { initialGroupID == nil }

    var title: String {
        isCreating ? "New Group" : "Edit Group"
    }

    var persistedScope: ScreenTimeSelectionScope {
        .appGroup(editingID)
    }

    var draftScope: ScreenTimeSelectionScope {
        .appGroup(draftID)
    }

    var selectedCount: Int {
        selectionPreview.applicationTokens.count
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard let initialGroupID else {
            try? selectionStore.remove(scope: draftScope)
            refreshSelectionState()
            return
        }

        if let group = await repository.appGroup(id: initialGroupID) {
            name = group.name
            createdAt = group.createdAt
        }

        if let selection = try? selectionStore.load(scope: persistedScope) {
            try? selectionStore.save(selection, scope: draftScope)
        } else {
            try? selectionStore.remove(scope: draftScope)
        }
        refreshSelectionState()
    }

    func refreshSelectionState() {
        selectionPreview = (try? selectionStore.load(scope: draftScope)) ?? FamilyActivitySelection()
    }

    func replaceSelection(_ selection: FamilyActivitySelection) {
        var normalized = selection
        normalized.categoryTokens = []
        normalized.webDomainTokens = []
        selectionPreview = normalized
        do {
            try selectionStore.save(normalized, scope: draftScope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Group name is required."
            return false
        }
        guard !selectionPreview.applicationTokens.isEmpty else {
            errorMessage = "Select at least one app."
            return false
        }

        do {
            let group = AppGroup(
                id: editingID,
                name: trimmedName,
                createdAt: createdAt,
                updatedAt: Date()
            )
            try selectionStore.save(selectionPreview, scope: persistedScope)
            try? selectionStore.remove(scope: draftScope)
            try await repository.save(group)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func discardDraft() {
        try? selectionStore.remove(scope: draftScope)
    }
}

@MainActor
final class DistractingGroupViewModel: ObservableObject {
    private let autoFocusManager: AutoFocusManager
    private let frictionRepository: FrictionRepository
    private let selectionStore: ScreenTimeSelectionStore

    @Published private(set) var configuration: AutoFocusConfiguration = .default
    @Published private(set) var distractingTokens: [ApplicationToken] = []
    @Published private(set) var frictionName: String?

    init(
        autoFocusManager: AutoFocusManager,
        frictionRepository: FrictionRepository,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.autoFocusManager = autoFocusManager
        self.frictionRepository = frictionRepository
        self.selectionStore = selectionStore
    }

    func load() async {
        let configuration = await autoFocusManager.configuration()
        let selection = (try? selectionStore.load(scope: .distracting)) ?? FamilyActivitySelection()
        let frictionName: String?
        if let frictionID = configuration.frictionID,
           let friction = await frictionRepository.friction(id: frictionID) {
            frictionName = friction.name
        } else {
            frictionName = nil
        }

        withAnimation(.smooth(duration: 0.24)) {
            self.configuration = configuration
            distractingTokens = selection.applicationTokens.stablePrefix(selection.applicationTokens.count)
            self.frictionName = frictionName
        }
    }

    func updateInterventionLevel(_ level: AutoFocusInterventionLevel) async {
        configuration.interventionLevel = level
        configuration.updatedAt = Date()
        if level == .low {
            configuration.frictionID = nil
        }
        try? await autoFocusManager.saveConfiguration(configuration)
        await load()
    }

    func updateFriction(_ frictionID: UUID?) async {
        configuration.frictionID = frictionID
        configuration.updatedAt = Date()
        try? await autoFocusManager.saveConfiguration(configuration)
        await load()
    }

    func updateCooldown(minutes: Int) async {
        configuration.cooldownMinutes = minutes
        configuration.updatedAt = Date()
        try? await autoFocusManager.saveConfiguration(configuration)
        await load()
    }
}

struct AppsListView: View {
    @ObservedObject var viewModel: AppsLibraryViewModel
    @ObservedObject var router: AppRouter

    private let columns = [
        GridItem(.flexible(), spacing: LocktySpacing.md),
        GridItem(.flexible(), spacing: LocktySpacing.md),
        GridItem(.flexible(), spacing: LocktySpacing.md)
    ]
    private let folderShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
            Button {
                router.push(.distractingGroup)
            } label: {
                AppFolderCard(
                    title: "Distracting",
                    subtitle: folderCountText(viewModel.distractingTokens.count),
                    tokens: viewModel.distractingTokens
                )
            }
            .buttonStyle(.locktyInteractive(shape: folderShape))

            ForEach(viewModel.appGroups) { group in
                Button {
                    router.push(.appGroupEditor(AppGroupEditorRoute(appGroupID: group.id)))
                } label: {
                    AppFolderCard(
                        title: group.name,
                        subtitle: folderCountText(viewModel.tokens(for: group.id).count),
                        tokens: viewModel.tokens(for: group.id)
                    )
                }
                .buttonStyle(.locktyInteractive(shape: folderShape))
            }

            Button {
                router.push(.appGroupEditor(AppGroupEditorRoute(appGroupID: nil)))
            } label: {
                AddAppFolderCard()
            }
            .buttonStyle(.locktyInteractive(shape: folderShape))
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private func folderCountText(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

struct DistractingGroupView: View {
    @ObservedObject var viewModel: DistractingGroupViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        LocktySectionScreen(title: "Distracting") {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                AppFolderCard(
                    title: "Distracting",
                    subtitle: viewModel.distractingTokens.isEmpty ? "0 items" : "\(viewModel.distractingTokens.count) items",
                    tokens: viewModel.distractingTokens
                )
                .frame(maxWidth: .infinity)

                settingsRow(
                    title: "Apps",
                    summary: viewModel.distractingTokens.isEmpty ? "No apps yet" : "\(viewModel.distractingTokens.count) selected"
                ) {
                    router.push(.distractingApps)
                }

                settingsRow(
                    title: "Intervention Level",
                    summary: viewModel.configuration.interventionLevel.title
                ) {
                    router.push(.distractingIntervention)
                }

                settingsRow(
                    title: "Friction",
                    summary: viewModel.frictionName ?? "None"
                ) {
                    router.push(.distractingFriction)
                }
                .disabled(viewModel.configuration.interventionLevel == .low)
                .opacity(viewModel.configuration.interventionLevel == .low ? 0.45 : 1)

                VStack(spacing: 0) {
                    cooldownRow(
                        title: "Cooldown",
                        valueText: "\(viewModel.configuration.cooldownMinutes) min",
                        decrementDisabled: viewModel.configuration.cooldownMinutes <= 5,
                        incrementDisabled: viewModel.configuration.cooldownMinutes >= 240,
                        onDecrement: {
                            Task {
                                await viewModel.updateCooldown(minutes: max(viewModel.configuration.cooldownMinutes - 5, 5))
                            }
                        },
                        onIncrement: {
                            Task {
                                await viewModel.updateCooldown(minutes: min(viewModel.configuration.cooldownMinutes + 5, 240))
                            }
                        }
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        .fill(LocktyColors.elevatedBackground)
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private func settingsRow(
        title: String,
        summary: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LocktyTypography.body)
                        .foregroundStyle(LocktyColors.primaryText)
                    Text(summary)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(LocktySpacing.md)
            .background(
                RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                    .fill(LocktyColors.elevatedBackground)
            )
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)))
    }

    private func cooldownRow(
        title: String,
        valueText: String,
        decrementDisabled: Bool,
        incrementDisabled: Bool,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
            Spacer(minLength: 0)
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .disabled(decrementDisabled)

            Text(valueText)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 78)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .disabled(incrementDisabled)
        }
        .padding(LocktySpacing.md)
    }
}

struct DistractingAppsSelectionView: View {
    let manager: AutoFocusManager
    let toastCenter: LocktyToastCenter
    @ObservedObject var router: AppRouter
    @State private var selection: FamilyActivitySelection

    init(manager: AutoFocusManager, toastCenter: LocktyToastCenter, router: AppRouter) {
        self.manager = manager
        self.toastCenter = toastCenter
        self.router = router
        _selection = State(initialValue: manager.distractingSelection())
    }

    var body: some View {
        LocktyActivitySelectionView(
            title: "Distracting",
            addLabel: "Add app",
            selection: $selection,
            rules: .appGroup,
            toastCenter: toastCenter,
            onClose: {},
            onDone: {}
        )
        .locktyScreenBackground()
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        try? await manager.saveDistractingSelection(selection)
                        router.pop()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

struct DistractingInterventionPickerView: View {
    @ObservedObject var viewModel: DistractingGroupViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        LocktySectionScreen(title: "Intervention Level") {
            VStack(spacing: LocktySpacing.md) {
                ForEach(AutoFocusInterventionLevel.allCases) { level in
                    Button {
                        Task {
                            await viewModel.updateInterventionLevel(level)
                            router.pop()
                        }
                    } label: {
                        HStack(spacing: LocktySpacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.title)
                                    .font(LocktyTypography.body)
                                    .foregroundStyle(LocktyColors.primaryText)
                                Text(level.summary)
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: viewModel.configuration.interventionLevel == level ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.configuration.interventionLevel == level ? LocktyColors.productive : LocktyColors.secondaryText)
                        }
                        .padding(LocktySpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                                .fill(LocktyColors.elevatedBackground)
                        )
                    }
                    .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)))
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

struct DistractingFrictionPickerView: View {
    @ObservedObject var viewModel: DistractingGroupViewModel
    let frictionRepository: FrictionRepository
    @ObservedObject var router: AppRouter
    @State private var frictions: [Friction] = []

    var body: some View {
        LocktySectionScreen(title: "Friction") {
            VStack(spacing: LocktySpacing.md) {
                Button {
                    Task {
                        await viewModel.updateFriction(nil)
                        router.pop()
                    }
                } label: {
                    selectionRow(title: "None", isSelected: viewModel.configuration.frictionID == nil)
                }
                .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)))

                ForEach(frictions) { friction in
                    Button {
                        Task {
                            await viewModel.updateFriction(friction.id)
                            router.pop()
                        }
                    } label: {
                        selectionRow(title: friction.name, subtitle: friction.summary, isSelected: viewModel.configuration.frictionID == friction.id)
                    }
                    .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)))
                }
            }
        }
        .task {
            await viewModel.load()
            frictions = await frictionRepository.frictions()
        }
    }

    private func selectionRow(title: String, subtitle: String? = nil, isSelected: Bool) -> some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? LocktyColors.productive : LocktyColors.secondaryText)
        }
        .padding(LocktySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                .fill(LocktyColors.elevatedBackground)
        )
    }
}

struct AppGroupEditorView: View {
    @ObservedObject var viewModel: AppGroupEditorViewModel
    @ObservedObject var router: AppRouter
    let onCloseEditor: () -> Void

    var body: some View {
        LocktySectionScreen(title: viewModel.title) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                AppFolderCard(
                    title: viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New group" : viewModel.name,
                    subtitle: viewModel.selectedCount == 1 ? "1 item" : "\(viewModel.selectedCount) items",
                    tokens: viewModel.selectionPreview.applicationTokens.stablePrefix(viewModel.selectedCount)
                )
                .frame(maxWidth: .infinity)

                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text("Name")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                        TextField("Socials", text: $viewModel.name)
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(LocktyColors.primaryText)
                    }
                }

                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text("Apps")
                            .font(LocktyTypography.body)
                            .foregroundStyle(LocktyColors.primaryText)

                        Text(viewModel.selectedCount == 1 ? "1 app" : "\(viewModel.selectedCount) apps")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }

                PrimaryButton(viewModel.isCreating ? "Save group" : "Save changes", systemImage: "checkmark") {
                    Task {
                        if await viewModel.save() {
                            router.pop()
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            onCloseEditor()
            viewModel.discardDraft()
        }
        .alert(
            "Could not save group",
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
}

extension AppGroupEditorViewModel {
    var initialGroupIDForRoute: UUID? { isCreating ? nil : editingID }
}

struct AppGroupSelectionView: View {
    @ObservedObject var viewModel: AppGroupEditorViewModel
    let toastCenter: LocktyToastCenter
    @ObservedObject var router: AppRouter

    var body: some View {
        LocktyActivitySelectionView(
            title: "Selected",
            addLabel: "Add app",
            selection: Binding(
                get: { viewModel.selectionPreview },
                set: { viewModel.replaceSelection($0) }
            ),
            rules: .appGroup,
            toastCenter: toastCenter,
            onClose: {},
            onDone: {}
        )
        .locktyScreenBackground()
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.pop()
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
        .task {
            await viewModel.load()
            viewModel.refreshSelectionState()
        }
    }
}

struct AddAppFolderCard: View {
    private let folderSide: CGFloat = 110

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LocktyColors.ink(0.045))
                .frame(width: folderSide, height: folderSide)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                }

            Text("New group")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .multilineTextAlignment(.center)

            Text("Reusable")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(width: folderSide)
    }
}

struct AppFolderCard: View {
    let title: String
    let subtitle: String
    let tokens: [ApplicationToken]
    /// Drawn as a border around the folder. Used where folders are being picked rather
    /// than opened.
    var isSelected = false

    private let folderSide: CGFloat = 110
    private let iconScale: CGFloat = 1.58

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LocktyColors.ink(0.045))
                .frame(width: folderSide, height: folderSide)
                .overlay {
                    folderGrid
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(LocktyColors.primaryText, lineWidth: 2)
                    }
                }

            // Leading and top, with room for two lines always reserved. Centred and
            // free-height, a folder whose name wrapped grew taller than the ones beside
            // it and dragged the whole row out of line -- and its subtitle sat lower than
            // everyone else's.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(height: 38, alignment: .top)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: folderSide, alignment: .top)
    }

    /// The geometry every cell of the grid gets, icons and the overflow tile alike.
    /// Written once so the two cannot drift apart.
    private func slot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .scaleEffect(iconScale)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
    }

    private var folderGrid: some View {
        let visible = Array(tokens.prefix(4))
        let overflow = max(0, tokens.count - 4)

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 2), spacing: 4) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, token in
                slot {
                    Label(token)
                        .labelStyle(.iconOnly)
                        // Inside the slot, so the scrim is the size of the icon. Outside
                        // it, the overlay took the slot's frame -- which is
                        // maxWidth: .infinity, the whole grid cell -- and the darkening
                        // ran the full width of the column with the icon floating in the
                        // middle of it.
                        .overlay {
                            if index == visible.count - 1, overflow > 0 {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.black.opacity(0.62))

                                    // Divided by the scale the slot applies, so the
                                    // number ends up the size it is written at rather
                                    // than 1.58 times it.
                                    Text("+\(overflow)")
                                        .font(.system(size: 17 / iconScale, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                }
            }

            if visible.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    placeholderDot(stencil: nil)
                }
            } else if visible.count < 4 {
                ForEach(visible.count..<4, id: \.self) { _ in
                    placeholderDot(stencil: visible.first)
                }
            }
        }
    }

    /// An empty slot in the grid, the size of the icons around it.
    ///
    /// Given a stencil it takes an icon's own shape, the same way the overflow tile
    /// does. With none -- a group with no apps in it at all -- there is nothing to copy,
    /// but there are no icons to be out of step with either, so a plain square is the
    /// whole grid and it matches itself.
    @ViewBuilder
    private func placeholderDot(stencil: ApplicationToken?) -> some View {
        if stencil == nil {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LocktyColors.ink(0.035))
                .frame(height: 38)
        } else {
            // Not run through `slot`: that scales by 1.58 because the real icons are
            // drawn smaller than their cell and need to grow into it. A placeholder has
            // no such inset, so the same scale made it burst out of the grid.
            LocktyTokenPlaceholder(
                stencil: stencil,
                fill: LocktyColors.ink(0.035)
            )
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        }
    }
}

/// The apps nothing may block.
///
/// Deliberately plain: it is one list and one instruction. Everything else in Focus is
/// something you configure; this is something you exempt.
struct AlwaysAllowedGroupView: View {
    @ObservedObject var viewModel: AppsLibraryViewModel
    @ObservedObject var router: AppRouter

    var body: some View {
        LocktySectionScreen(title: "Always Allowed") {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                AppFolderCard(
                    title: "Always Allowed",
                    subtitle: viewModel.alwaysAllowedTokens.count == 1
                        ? "1 item"
                        : "\(viewModel.alwaysAllowedTokens.count) items",
                    tokens: viewModel.alwaysAllowedTokens
                )
                .frame(maxWidth: .infinity)

                Text("These apps are never blocked, not even when a rule blocks their whole category.")
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)

                Button {
                    router.presentSheet(.appPicker(.alwaysAllowed))
                } label: {
                    HStack(spacing: LocktySpacing.md) {
                        Text("Apps")
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)

                        Spacer(minLength: 0)

                        Text(viewModel.alwaysAllowedTokens.isEmpty
                             ? "None"
                             : "\(viewModel.alwaysAllowedTokens.count) selected")
                            .font(.system(.footnote, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                    .padding(.horizontal, LocktySpacing.md)
                    .padding(.vertical, LocktySpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LocktyColors.ink(0.055))
                    )
                }
                .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .tappable()
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task { await viewModel.load() }
        }
    }
}
