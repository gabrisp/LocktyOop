import Combine
import CoreTransferable
import CoreNFC
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FrictionEditorViewModel: ObservableObject {
    let editingID: UUID
    let draftID: UUID

    @Published var draft: FrictionEditorDraft
    @Published var errorMessage: String?

    private let repository: FrictionRepository
    private let initialFrictionID: UUID?
    private var createdAt: Date
    private var hasLoaded = false
    private var baseline: FrictionEditorDraft

    init(
        frictionID: UUID?,
        draftID: UUID,
        repository: FrictionRepository
    ) {
        self.initialFrictionID = frictionID
        self.editingID = frictionID ?? UUID()
        self.draftID = draftID
        self.repository = repository
        let initialDraft = FrictionEditorDraft(id: frictionID ?? UUID())
        self.draft = initialDraft
        self.baseline = initialDraft
        self.createdAt = Date()
    }

    var title: String {
        initialFrictionID == nil ? "New Friction" : "Edit Friction"
    }

    var isCreating: Bool {
        initialFrictionID == nil
    }

    var hasChanges: Bool {
        draft != baseline
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let initialFrictionID, let friction = await repository.friction(id: initialFrictionID) else {
            baseline = draft
            return
        }
        createdAt = friction.createdAt
        let loaded = FrictionEditorDraft(friction: friction)
        draft = loaded
        baseline = loaded
    }

    func addStep(_ item: FrictionCatalogItem) {
        draft.steps.append(item.makeStep())
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = item.title
        }
    }

    func removeStep(id: UUID) {
        draft.steps.removeAll { $0.id == id }
    }

    func moveStepUp(id: UUID) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }), index > 0 else { return }
        draft.steps.swapAt(index, index - 1)
    }

    func moveStepDown(id: UUID) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }), index < draft.steps.count - 1 else { return }
        draft.steps.swapAt(index, index + 1)
    }

    func update(stepID: UUID, with step: FrictionStep) {
        guard let index = draft.steps.firstIndex(where: { $0.id == stepID }) else { return }
        draft.steps[index] = step
    }

    func save() async -> Bool {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Friction name is required."
            return false
        }
        guard !draft.steps.isEmpty else {
            errorMessage = "Add at least one friction step."
            return false
        }
        draft.name = trimmedName

        do {
            draft.steps = try prepareStepsForSaving(draft.steps)
            let friction = draft.makeFriction(createdAt: createdAt, updatedAt: Date())
            try await repository.save(friction)
            baseline = FrictionEditorDraft(friction: friction)
            draft = baseline
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func prepareStepsForSaving(_ steps: [FrictionStep]) throws -> [FrictionStep] {
        let sanitized = steps.compactMap(sanitizedStep)
        guard sanitized.count == steps.count else {
            throw FrictionEditorAssetError.invalidConfiguration
        }
        return try sanitized.map(persistAssetsIfNeeded)
    }

    private func sanitizedStep(_ step: FrictionStep) -> FrictionStep? {
        switch step {
        case .wordSearch(let configuration):
            let trimmed = configuration.targetWord?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .wordSearch(
                WordSearchConfiguration(
                    id: configuration.id,
                    difficulty: configuration.difficulty,
                    targetWord: trimmed?.isEmpty == false ? trimmed?.uppercased() : nil
                )
            )
        case .intentionTemplate(let configuration):
            let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return nil }
            return .intentionTemplate(
                IntentionConfiguration(
                    id: configuration.id,
                    prompt: prompt,
                    minimumLength: configuration.minimumLength,
                    isRequired: configuration.isRequired
                )
            )
        case .customIntention(let configuration):
            let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return nil }
            return .customIntention(
                IntentionConfiguration(
                    id: configuration.id,
                    prompt: prompt,
                    minimumLength: configuration.minimumLength,
                    isRequired: configuration.isRequired
                )
            )
        case .intention(let configuration):
            let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return nil }
            return .intention(
                IntentionConfiguration(
                    id: configuration.id,
                    prompt: prompt,
                    minimumLength: configuration.minimumLength,
                    isRequired: configuration.isRequired
                )
            )
        case .confirmation(let configuration):
            let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return .confirmation(
                ConfirmationConfiguration(
                    id: configuration.id,
                    prompt: prompt.isEmpty ? "Do you still want to continue?" : prompt
                )
            )
        case .personalVideo(let configuration):
            guard !configuration.videoFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return step
        case .personalText(let configuration):
            let phrases = configuration.phrases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !phrases.isEmpty else { return nil }
            return .personalText(PersonalTextConfiguration(id: configuration.id, phrases: phrases))
        case .nfcTag(let configuration):
            let normalized = normalizeFrictionTagIdentifier(configuration.normalizedIdentifier)
            guard !normalized.isEmpty else { return nil }
            return .nfcTag(
                NFCTagConfiguration(
                    id: configuration.id,
                    normalizedIdentifier: normalized,
                    displayName: configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .location(let configuration):
            let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCoordinate = abs(configuration.latitude) > 0.000_001 || abs(configuration.longitude) > 0.000_001
            guard hasCoordinate, configuration.radiusMeters > 0 else { return nil }
            return .location(
                LocationTrigger(
                    id: configuration.id,
                    name: name.isEmpty ? "Saved place" : name,
                    latitude: configuration.latitude,
                    longitude: configuration.longitude,
                    radiusMeters: configuration.radiusMeters,
                    startsOnEntry: true
                )
            )
        default:
            return step
        }
    }

    private func persistAssetsIfNeeded(_ step: FrictionStep) throws -> FrictionStep {
        switch step {
        case .personalVideo(let configuration):
            return .personalVideo(try persistVideoConfiguration(configuration))
        default:
            return step
        }
    }

    private func persistVideoConfiguration(_ configuration: PersonalVideoConfiguration) throws -> PersonalVideoConfiguration {
        let trimmed = configuration.videoFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FrictionEditorAssetError.invalidVideoSelection }

        if !trimmed.hasPrefix("/") {
            return PersonalVideoConfiguration(
                id: configuration.id,
                videoFileName: trimmed,
                displayName: configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let sourceURL = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw FrictionEditorAssetError.invalidVideoSelection
        }

        let destinationDirectory = try frictionVideoDirectoryURL()
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension.lowercased()
        let fileName = "\(configuration.id.uuidString).\(ext)"
        let destinationURL = destinationDirectory.appendingPathComponent(fileName, isDirectory: false)

        if sourceURL.deletingLastPathComponent().standardizedFileURL != destinationDirectory.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            if sourceURL.path.hasPrefix(NSTemporaryDirectory()) {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }

        let displayName = configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonalVideoConfiguration(
            id: configuration.id,
            videoFileName: fileName,
            displayName: displayName?.isEmpty == false ? displayName : sourceURL.deletingPathExtension().lastPathComponent
        )
    }

    private func frictionVideoDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupIdentifier)?
            .appendingPathComponent("SharedState", isDirectory: true)
            ?? fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("LocktySharedFallback", isDirectory: true)

        guard let baseDirectory else {
            throw FrictionEditorAssetError.mediaStorageUnavailable
        }

        let directory = baseDirectory.appendingPathComponent("friction-videos", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum FrictionEditorAssetError: LocalizedError {
    case invalidConfiguration
    case invalidVideoSelection
    case mediaStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Finish configuring every friction step before saving."
        case .invalidVideoSelection:
            "Choose a valid video from your library before saving this friction."
        case .mediaStorageUnavailable:
            "Lockty could not access the shared video storage directory."
        }
    }
}

private enum FrictionEditorLocalSheet: Identifiable, Equatable {
    case catalog
    /// One step's settings, on their own screen.
    case step(UUID)

    var id: String {
        switch self {
        case .catalog: "catalog"
        case .step(let stepID): "step-\(stepID.uuidString)"
        }
    }
}

private enum FrictionEditorCompactScreen: Hashable {
    case editor
    case naming
}

struct FrictionEditorView: View {
    @StateObject private var viewModel: FrictionEditorViewModel
    let isEmbeddedInParentSheet: Bool
    let locationService: LocationTriggerServicing?
    let onReturnToParent: (() -> Void)?
    let onCloseEditor: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: FrictionEditorLocalSheet?
    @State private var isConfirmingDiscard = false
    @State private var isShowingBreatheMenu = false
    /// The form's natural height, so the sheet can be told a number rather than asking a
    /// scroll view how tall it wishes it were.
    @State private var editorContentHeight: CGFloat = 0
    @State private var isGoingBack = false
    @State private var isNaming = false
    @FocusState private var isNameFieldFocused: Bool

    init(
        viewModel: FrictionEditorViewModel,
        isEmbeddedInParentSheet: Bool = false,
        locationService: LocationTriggerServicing? = nil,
        onReturnToParent: (() -> Void)? = nil,
        onCloseEditor: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isEmbeddedInParentSheet = isEmbeddedInParentSheet
        self.locationService = locationService
        self.onReturnToParent = onReturnToParent
        self.onCloseEditor = onCloseEditor
    }

    private var currentCompactScreen: FrictionEditorCompactScreen {
        isNaming ? .naming : .editor
    }

    private var contentID: String {
        if let activeSheet {
            return activeSheet.id
        }
        switch currentCompactScreen {
        case .editor:
            return "editor"
        case .naming:
            return "naming"
        }
    }

    private var chromeID: String {
        let hasName = !viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return "\(contentID)-\(hasName)"
    }

    private var sheetAnimation: Animation { .snappy(duration: 0.4, extraBounce: 0.02) }

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
                editorScaffold
            } else {
                LocktyDynamicSheet(animation: sheetAnimation) {
                    editorScaffold
                }
            }
        }
        .locktyInteractiveDismiss(
            blocked: viewModel.hasChanges && activeSheet == nil,
            onAttempt: requestClose
        )
        .task {
            await viewModel.load()
        }
        .onChange(of: isNaming, initial: false) { _, newValue in
            guard newValue else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(340))
                isNameFieldFocused = true
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { returnToParentOrDismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert(
            "Could not save friction",
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

    private func dismissEditor() {
        onCloseEditor()
        dismiss()
    }

    private func returnToParentOrDismiss() {
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

    private var sheetContent: some View {
        ZStack {
            switch activeSheet {
            case .catalog:
                catalogContent
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            case .step(let stepID):
                stepDetailContent(stepID: stepID)
                    .geometryGroup()
                    .transition(screenTransition)
            case nil:
                switch currentCompactScreen {
                case .editor:
                    editorContent
                        .geometryGroup()
                        .transition(screenTransition)
                case .naming:
                    namingContent
                        .geometryGroup()
                        .transition(screenTransition)
                }
            }
        }
        .geometryGroup()
    }

    @ViewBuilder
    private var centerChrome: some View {
        switch activeSheet {
        case .catalog:
            chromeTitleText("Friction Catalog")
        case .step(let stepID):
            chromeTitleText(viewModel.draft.steps.first { $0.id == stepID }?.title ?? "Step")
        case nil:
            chromeTitleText(isNaming ? "Name" : frictionChromeName)
        }
    }

    private func chromeTitleText(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
    }

    private var frictionChromeName: String {
        let trimmed = viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return viewModel.isCreating ? "New friction" : "Friction"
        }
        return trimmed
    }

    @ViewBuilder
    private var leadingChrome: some View {
        if activeSheet != nil {
            LocktyDynamicSheetBarButton(action: closeCatalog) {
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
            Color.clear
                .frame(width: 44, height: 44)
        } else if isNaming {
            LocktyDynamicSheetBarButton(action: exitNaming) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(viewModel.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
            LocktyDynamicSheetBarButton(action: enterNaming) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
            }
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

    private func openCatalog() {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            activeSheet = .catalog
        }
    }

    private func closeCatalog() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            activeSheet = nil
        }
    }

    private func saveAndClose() {
        Task {
            if await viewModel.save() {
                dismissEditor()
            }
        }
    }

    private var namingContent: some View {
        VStack(spacing: LocktySpacing.lg) {
            TextField("Name", text: $viewModel.draft.name)
                .focused($isNameFieldFocused)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.lg)
                .padding(.vertical, LocktySpacing.md)
                .background(Capsule(style: .continuous).fill(LocktyColors.elevatedBackground))
        }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.vertical, LocktySpacing.lg)
    }

    /// The form, sized to itself until it is too tall, and scrolling after that.
    ///
    /// A bare ScrollView inside this sheet cannot work: the sheet measures its content to
    /// decide its own height, and a scroll view reports the height it was *given* rather
    /// than the height of what is in it. So with enough steps the sheet had nothing to
    /// size itself from and the scroll view had no viewport to scroll inside -- the
    /// content simply ran off the bottom.
    ///
    /// Measuring the stack and framing the scroll view to `min(content, available)` gives
    /// the sheet a definite number either way, and leaves the scroll view a real viewport
    /// exactly when there is more content than room.
    private var editorContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                // No "Enabled" switch. A friction is available the moment it exists --
                // what decides whether one runs is a routine choosing it, not a flag on
                // the friction itself. Nothing ever read the flag, so the switch was a
                // control that did nothing but suggest a friction could be inert.
                breatheRow

                stepsSection

                LocktyHoldButton(
                    title: viewModel.isCreating ? "Hold to confirm" : "Hold to save"
                ) {
                    saveAndClose()
                }
                .padding(.top, LocktySpacing.sm)
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                editorContentHeight = newValue
            }
        }
        .frame(height: min(editorContentHeight, availableEditorHeight))
        .scrollDisabled(editorContentHeight <= availableEditorHeight)
    }

    /// What the sheet can actually give the form: the window, less the room a sheet never
    /// occupies, less the bar above the content.
    private var availableEditorHeight: CGFloat {
        let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 0
        return max(window - 110 - 64, 240)
    }

    /// The breathe every unlock opens on, as one row with its own menu.
    ///
    /// Not a step, and deliberately above the step list: it is the only part of the flow
    /// that is always there, so it is stated once at the top rather than sitting in a
    /// list of things you chose to add.
    private var breatheRow: some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: "wind")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Breathe")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text("Every unlock starts here")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)

            Text(LocktyBreathe.label(viewModel.draft.breatheSeconds))
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.22), value: viewModel.draft.breatheSeconds)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LocktyColors.tertiaryText)
        }
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.vertical, LocktySpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .onTapGesture { isShowingBreatheMenu = true }
        .locktyMenu(isPresented: $isShowingBreatheMenu) {
            LocktyBreatheMenu(seconds: $viewModel.draft.breatheSeconds)
        }
    }

    /// One step's settings, on a screen of their own.
    ///
    /// The list is a list: names and what each one is set to. Every step's controls laid
    /// out inline turned it into a stack of forms, where the shape of the flow -- which
    /// steps, in what order -- was the hardest thing to see on the screen that exists to
    /// show it.
    @ViewBuilder
    private func stepDetailContent(stepID: UUID) -> some View {
        if let index = viewModel.draft.steps.firstIndex(where: { $0.id == stepID }) {
            let step = viewModel.draft.steps[index]

            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                FrictionStepSettings(
                    step: step,
                    locationService: locationService,
                    onChange: { viewModel.update(stepID: stepID, with: $0) }
                )
                .padding(LocktySpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )

                Button(role: .destructive) {
                    viewModel.removeStep(id: stepID)
                    closeStepDetail()
                } label: {
                    HStack(spacing: LocktySpacing.sm) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                        Text("Remove step")
                            .font(.system(.subheadline, design: .default, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(LocktyColors.error)
                    .padding(.horizontal, LocktySpacing.lg)
                    .padding(.vertical, LocktySpacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                    )
                }
                .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)))
                .tappable()
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func openStepDetail(_ stepID: UUID) {
        isGoingBack = false
        withAnimation(sheetAnimation) { activeSheet = .step(stepID) }
    }

    private func closeStepDetail() {
        isGoingBack = true
        withAnimation(sheetAnimation) { activeSheet = nil }
    }

    private var catalogContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                ForEach(FrictionCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        Text(category.title)
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: LocktySpacing.md) {
                                ForEach(FrictionCatalog.items(in: category)) { item in
                                    Button {
                                        viewModel.addStep(item)
                                        closeCatalog()
                                    } label: {
                                        FrictionCatalogCard(item: item)
                                    }
                                    .buttonStyle(.locktyInteractive)
                                    .tappable()
                                }
                            }
                            .padding(.horizontal, LocktySpacing.lg)
                        }
                        .padding(.horizontal, -LocktySpacing.lg)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            Text("STEPS")
                .locktyEyebrow()

            if viewModel.draft.steps.isEmpty {
                Text("Add the first friction step from the catalog.")
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LocktySpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                    )
            } else {
                ForEach(Array(viewModel.draft.steps.enumerated()), id: \.element.id) { index, step in
                    FrictionStepEditorCard(
                        step: step,
                        index: index,
                        isFirst: index == 0,
                        isLast: index == viewModel.draft.steps.count - 1,
                        onOpen: { openStepDetail(step.id) },
                        onMoveUp: { viewModel.moveStepUp(id: step.id) },
                        onMoveDown: { viewModel.moveStepDown(id: step.id) }
                    )
                }
            }

            addStepCard
        }
    }

    /// Adding a step is the last thing in the list, and looks like the things it adds.
    ///
    /// It used to be a bare word floating at the right of the "STEPS" heading, which read
    /// as a link rather than as the way to grow the list -- and put the control at the
    /// top, above the steps it appends to the bottom.
    private var addStepCard: some View {
        Button(action: openCatalog) {
            HStack(spacing: LocktySpacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))

                Text("Add step")
                    .font(.system(.subheadline, design: .default, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)))
        .tappable()
    }

    /// One radius and one inset for every card on this sheet, so the rows, the step
    /// cards and the breathe control read as the same kind of object.
    static let cardRadius: CGFloat = 22
}

private struct FrictionCatalogCard: View {
    let item: FrictionCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: LocktyRadius.large, style: .continuous)
                    .fill(item.tint.gradient.opacity(0.26))
                    .frame(width: 220, height: 152)

                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(item.tint)

                    Spacer(minLength: 0)

                    Text(item.subtitle)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .padding(LocktySpacing.md)
                .frame(width: 220, height: 152, alignment: .leading)
            }

            Text(item.title)
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.primaryText)
        }
        .frame(width: 220, alignment: .leading)
    }
}

private struct FrictionStepEditorCard: View {
    let step: FrictionStep
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    let onOpen: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        CardView(radius: FrictionEditorView.cardRadius, padding: LocktySpacing.lg) {
            HStack(alignment: .center, spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STEP \(index + 1)")
                        .locktyEyebrow()

                    Text(step.title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    // What it is set to, in a line. The list's job is the shape of the
                    // flow; the settings live one tap away.
                    Text(step.detail)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: LocktySpacing.sm) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(isFirst)

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(isLast)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LocktyColors.secondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: FrictionEditorView.cardRadius, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

/// One step's controls, wherever they are shown.
///
/// Split out of the card so the list can be a list. The card names the step and says what
/// it is set to; this is what opens when you tap it.
private struct FrictionStepSettings: View {
    let step: FrictionStep
    let locationService: LocationTriggerServicing?
    let onChange: (FrictionStep) -> Void

    var body: some View {
        configurationView
    }

    @ViewBuilder
    private var configurationView: some View {
        switch step {
        case .countdown(let configuration):
            LocktyCountRow(
                title: "Seconds",
                value: Binding(
                    get: { Int(configuration.duration) },
                    set: { onChange(.countdown(CountdownConfiguration(id: configuration.id, duration: TimeInterval($0)))) }
                ),
                range: 1...60,
                suffix: "s"
            )

        case .breathing(let configuration):
            // Only reachable on a flow saved before the breathe became a setting.
            LocktyCountRow(
                title: "Breaths",
                value: Binding(
                    get: { configuration.breathCount },
                    set: { onChange(.breathing(BreathingConfiguration(id: configuration.id, breathCount: $0))) }
                ),
                range: 1...10
            )

        case .steps(let configuration):
            LocktyCountRow(
                title: "Daily steps",
                value: Binding(
                    get: { configuration.dailyGoal },
                    set: { onChange(.steps(StepsConfiguration(id: configuration.id, dailyGoal: $0))) }
                ),
                range: 1000...25000,
                step: 500
            )

        case .wordSearch(let configuration):
            VStack(alignment: .leading, spacing: 0) {
                EnumPicker(title: "Difficulty", selection: configuration.difficulty) { newValue in
                    onChange(.wordSearch(WordSearchConfiguration(id: configuration.id, difficulty: newValue, targetWord: configuration.targetWord)))
                }

                FrictionSettingsDivider()

                FrictionSettingsField(
                    title: "Target word",
                    text: Binding(
                        get: { configuration.targetWord ?? "" },
                        set: { onChange(.wordSearch(WordSearchConfiguration(id: configuration.id, difficulty: configuration.difficulty, targetWord: $0.isEmpty ? nil : $0.uppercased()))) }
                    )
                )
            }

        case .letterMatch(let configuration):
            LocktyCountRow(
                title: "Pairs",
                value: Binding(
                    get: { configuration.pairCount },
                    set: { onChange(.letterMatch(LetterMatchConfiguration(id: configuration.id, pairCount: $0))) }
                ),
                range: 2...6
            )

        case .operations(let configuration):
            VStack(alignment: .leading, spacing: 0) {
                EnumPicker(title: "Difficulty", selection: configuration.difficulty) { newValue in
                    onChange(.operations(OperationsConfiguration(id: configuration.id, difficulty: newValue, problemCount: configuration.problemCount, allowedOperators: configuration.allowedOperators)))
                }

                FrictionSettingsDivider()

                LocktyCountRow(
                    title: "Problem count",
                    value: Binding(
                        get: { configuration.problemCount },
                        set: { onChange(.operations(OperationsConfiguration(id: configuration.id, difficulty: configuration.difficulty, problemCount: $0, allowedOperators: configuration.allowedOperators))) }
                    ),
                    range: 1...10
                )

                FrictionSettingsDivider()

                operatorToggleRow(configuration: configuration)
            }

        case .intentionTemplate(let configuration):
            intentionFields(configuration: configuration) { onChange(.intentionTemplate($0)) }

        case .customIntention(let configuration):
            intentionFields(configuration: configuration) { onChange(.customIntention($0)) }

        case .intention(let configuration):
            intentionFields(configuration: configuration) { onChange(.intention($0)) }

        case .confirmation(let configuration):
            FrictionSettingsField(
                title: "Prompt",
                text: Binding(
                    get: { configuration.prompt },
                    set: { onChange(.confirmation(ConfirmationConfiguration(id: configuration.id, prompt: $0))) }
                )
            )

        case .personalVideo(let configuration):
            PersonalVideoConfigurationView(
                configuration: configuration,
                onUpdate: { onChange(.personalVideo($0)) }
            )

        case .personalText(let configuration):
            TextEditor(text: Binding(
                get: { configuration.phrases.joined(separator: "\n") },
                set: { newValue in
                    let phrases = newValue
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    onChange(.personalText(PersonalTextConfiguration(id: configuration.id, phrases: phrases)))
                }
            ))
            .frame(minHeight: 120)
            .padding(LocktySpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                    .fill(LocktyColors.elevatedBackground)
            )

        case .nfcTag(let configuration):
            NFCTagConfigurationView(
                configuration: configuration,
                onUpdate: { onChange(.nfcTag($0)) }
            )

        case .location(let configuration):
            LocationFrictionConfigurationView(
                configuration: configuration,
                locationService: locationService,
                onUpdate: { onChange(.location($0)) }
            )
        }
    }

    private func intentionFields(
        configuration: IntentionConfiguration,
        onUpdate: @escaping (IntentionConfiguration) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FrictionSettingsField(
                title: "Prompt",
                text: Binding(
                    get: { configuration.prompt },
                    set: { onUpdate(IntentionConfiguration(id: configuration.id, prompt: $0, minimumLength: configuration.minimumLength, isRequired: configuration.isRequired)) }
                )
            )

            FrictionSettingsDivider()

            LocktyCountRow(
                title: "Minimum length",
                value: Binding(
                    get: { configuration.minimumLength ?? 0 },
                    set: { onUpdate(IntentionConfiguration(id: configuration.id, prompt: configuration.prompt, minimumLength: $0, isRequired: configuration.isRequired)) }
                ),
                range: 0...200,
                step: 5
            )

            FrictionSettingsDivider()

            LocktyToggle(
                title: "Response required",
                isOn: Binding(
                    get: { configuration.isRequired },
                    set: { onUpdate(IntentionConfiguration(id: configuration.id, prompt: configuration.prompt, minimumLength: configuration.minimumLength, isRequired: $0)) }
                )
            )
            .frame(minHeight: 44)
        }
    }

    private func operatorToggleRow(configuration: OperationsConfiguration) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("Operators")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            operatorChips(configuration: configuration)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LocktySpacing.sm)
    }

    private func operatorChips(configuration: OperationsConfiguration) -> some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(ArithmeticOperator.allCases) { operation in
                Button {
                    var next = configuration.allowedOperators
                    if next.contains(operation) {
                        next.remove(operation)
                    } else {
                        next.insert(operation)
                    }
                    if next.isEmpty {
                        next.insert(.addition)
                    }
                    onChange(
                        .operations(
                            OperationsConfiguration(
                                id: configuration.id,
                                difficulty: configuration.difficulty,
                                problemCount: configuration.problemCount,
                                allowedOperators: next
                            )
                        )
                    )
                } label: {
                    Text(operation.rawValue)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(configuration.allowedOperators.contains(operation) ? Color.black : LocktyColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                                .fill(configuration.allowedOperators.contains(operation) ? Color.white : LocktyColors.elevatedBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func unsupportedConfigurationCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xs) {
            Text(title)
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.primaryText)

            Text(message)
                .font(LocktyTypography.caption)
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .padding(LocktySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                .fill(LocktyColors.elevatedBackground)
        )
    }
}

private struct PersonalVideoConfigurationView: View {
    let configuration: PersonalVideoConfiguration
    let onUpdate: (PersonalVideoConfiguration) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            TextField("Video name", text: Binding(
                get: { configuration.displayName ?? "" },
                set: {
                    onUpdate(
                        PersonalVideoConfiguration(
                            id: configuration.id,
                            videoFileName: configuration.videoFileName,
                            displayName: $0
                        )
                    )
                }
            ))
            .locktyGlassInputStyle()

            PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                    Text(isImporting ? "Importando video..." : "Elegir video")
                        .font(LocktyTypography.callout)
                    Spacer(minLength: 0)
                    if isImporting {
                        ProgressView()
                            .tint(LocktyColors.primaryText)
                    }
                }
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        .fill(LocktyColors.elevatedBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .onChange(of: selectedItem, initial: false) { _, newValue in
                guard let newValue else { return }
                Task {
                    await importVideo(from: newValue)
                }
            }

            videoSelectionSummary

            if let errorMessage {
                Text(errorMessage)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.error)
            }
        }
    }

    @ViewBuilder
    private var videoSelectionSummary: some View {
        let label = currentVideoLabel
        if !label.isEmpty {
            HStack(spacing: LocktySpacing.sm) {
                Image(systemName: "film")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)

                Text(label)
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(2)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                    .fill(LocktyColors.elevatedBackground.opacity(0.72))
            )
        }
    }

    private var currentVideoLabel: String {
        let displayName = configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty {
            return displayName
        }

        let fileName = configuration.videoFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else { return "" }
        return URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    @MainActor
    private func importVideo(from item: PhotosPickerItem) async {
        isImporting = true
        errorMessage = nil

        defer {
            isImporting = false
            selectedItem = nil
        }

        do {
            guard let imported = try await item.loadTransferable(type: FrictionImportedVideo.self) else {
                throw FrictionEditorAssetError.invalidVideoSelection
            }

            let fallbackName = imported.url.deletingPathExtension().lastPathComponent
            let displayName = configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)

            onUpdate(
                PersonalVideoConfiguration(
                    id: configuration.id,
                    videoFileName: imported.url.path,
                    displayName: displayName?.isEmpty == false ? displayName : fallbackName
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NFCTagConfigurationView: View {
    let configuration: NFCTagConfiguration
    let onUpdate: (NFCTagConfiguration) -> Void

    @State private var isScanning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            TextField("Tag name", text: Binding(
                get: { configuration.displayName ?? "" },
                set: {
                    onUpdate(
                        NFCTagConfiguration(
                            id: configuration.id,
                            normalizedIdentifier: configuration.normalizedIdentifier,
                            displayName: $0
                        )
                    )
                }
            ))
            .locktyGlassInputStyle()

            Button {
                Task {
                    await registerTag()
                }
            } label: {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: "wave.3.right.circle")
                        .font(.system(size: 17, weight: .medium))
                    Text(isScanning ? "Escaneando etiqueta..." : "Escanear etiqueta")
                        .font(LocktyTypography.callout)
                    Spacer(minLength: 0)
                    if isScanning {
                        ProgressView()
                            .tint(LocktyColors.primaryText)
                    }
                }
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        .fill(LocktyColors.elevatedBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(isScanning)

            if !configuration.normalizedIdentifier.isEmpty {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LocktyColors.productive)

                    Text(configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                         ? configuration.displayName!
                         : configuration.normalizedIdentifier.uppercased())
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(2)
                }
                .padding(.horizontal, LocktySpacing.md)
                .padding(.vertical, LocktySpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        .fill(LocktyColors.elevatedBackground.opacity(0.72))
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.error)
            }
        }
    }

    @MainActor
    private func registerTag() async {
        isScanning = true
        errorMessage = nil

        defer {
            isScanning = false
        }

        do {
            let scannedTag = try await FrictionTagRegistrationScanner().scan()
            let displayName = configuration.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)

            onUpdate(
                NFCTagConfiguration(
                    id: configuration.id,
                    normalizedIdentifier: scannedTag.normalizedIdentifier,
                    displayName: displayName?.isEmpty == false ? displayName : scannedTag.displayName
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LocationFrictionConfigurationView: View {
    let configuration: LocationTrigger
    let locationService: LocationTriggerServicing?
    let onUpdate: (LocationTrigger) -> Void

    @State private var isResolvingLocation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            TextField("Place name", text: Binding(
                get: { configuration.name },
                set: {
                    onUpdate(
                        LocationTrigger(
                            id: configuration.id,
                            name: $0,
                            latitude: configuration.latitude,
                            longitude: configuration.longitude,
                            radiusMeters: configuration.radiusMeters,
                            startsOnEntry: true
                        )
                    )
                }
            ))
            .locktyGlassInputStyle()

            Button {
                Task {
                    await captureCurrentLocation()
                }
            } label: {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 17, weight: .medium))
                    Text(isResolvingLocation ? "Saving location..." : "Use current location")
                        .font(LocktyTypography.callout)
                    Spacer(minLength: 0)
                    if isResolvingLocation {
                        ProgressView()
                            .tint(LocktyColors.primaryText)
                    }
                }
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        .fill(LocktyColors.elevatedBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(isResolvingLocation)

            Stepper(
                "Radio: \(Int(configuration.radiusMeters)) m",
                value: Binding(
                    get: { Int(configuration.radiusMeters) },
                    set: {
                        onUpdate(
                            LocationTrigger(
                                id: configuration.id,
                                name: configuration.name,
                                latitude: configuration.latitude,
                                longitude: configuration.longitude,
                                radiusMeters: Double(min(max($0, 50), 1_000)),
                                startsOnEntry: true
                            )
                        )
                    }
                ),
                in: 50...1_000,
                step: 25
            )
            .foregroundStyle(LocktyColors.primaryText)

            if hasSavedCoordinate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(configuration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved place" : configuration.name)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.primaryText)

                    Text("\(configuration.latitude.formatted(.number.precision(.fractionLength(4)))), \(configuration.longitude.formatted(.number.precision(.fractionLength(4))))")
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
                .padding(.horizontal, LocktySpacing.md)
                .padding(.vertical, LocktySpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        .fill(LocktyColors.elevatedBackground.opacity(0.72))
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.error)
            }
        }
    }

    private var hasSavedCoordinate: Bool {
        abs(configuration.latitude) > 0.000_001 || abs(configuration.longitude) > 0.000_001
    }

    @MainActor
    private func captureCurrentLocation() async {
        guard let locationService else {
            errorMessage = "Location is unavailable in this build."
            return
        }

        isResolvingLocation = true
        errorMessage = nil

        defer {
            isResolvingLocation = false
        }

        do {
            let location = try await locationService.currentLocation()
            let trimmedName = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)

            onUpdate(
                LocationTrigger(
                    id: configuration.id,
                    name: trimmedName.isEmpty ? "Saved place" : trimmedName,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    radiusMeters: configuration.radiusMeters,
                    startsOnEntry: true
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DurationSliderCard: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    /// Rounds the slider's answer. A step goal that lands on 8137 is noise, not a choice.
    var step: Double = 1
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("\(title): \(Int(value).formatted(.number.grouping(.automatic)))")
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.primaryText)

            DurationSlider(
                value: Binding(
                    get: { value },
                    set: { onChange((($0 / step).rounded()) * step) }
                ),
                range: range
            )
        }
    }
}

/// A choice, as a row with a menu -- the same shape as every other setting here.
///
/// It used to be a row of full-width buttons under a caption, which took four lines to
/// say one thing and made a two-option choice look more important than the count above
/// it. A row states the setting and its value; the options are one tap away.
private struct EnumPicker<Value: CaseIterable & Identifiable & Hashable & RawRepresentable>: View where Value.RawValue == String {
    let title: String
    let selection: Value
    let onSelect: (Value) -> Void

    @State private var isShowingOptions = false

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            Text(label(for: selection))
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LocktyColors.tertiaryText)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { isShowingOptions = true }
        .locktyMenu(isPresented: $isShowingOptions) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Value.allCases), id: \.id) { option in
                    Button {
                        onSelect(option)
                        isShowingOptions = false
                    } label: {
                        HStack(spacing: LocktySpacing.md) {
                            Text(label(for: option))
                                .font(.system(.subheadline, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.primaryText)

                            Spacer(minLength: 0)

                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LocktyColors.productive)
                            }
                        }
                        .padding(.horizontal, LocktySpacing.lg)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappable()
                }
            }
            .padding(.vertical, LocktySpacing.sm)
            .frame(width: 200)
        }
    }

    private func label(for value: Value) -> String {
        String(describing: value.rawValue).capitalized
    }
}

private func normalizeFrictionTagIdentifier(_ value: String) -> String {
    value
        .filter(\.isHexDigit)
        .lowercased()
}

private struct FrictionImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let sourceURL = received.file
            let fileManager = FileManager.default
            let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
            let destinationURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return Self(url: destinationURL)
        }
    }
}

private struct FrictionTagRegistrationResult {
    let normalizedIdentifier: String
    let displayName: String
}

private enum FrictionTagRegistrationError: LocalizedError {
    case unavailable
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "NFC is not available on this device."
        case .unsupported:
            "No se pudo leer la identidad de esta etiqueta NFC."
        }
    }
}

private final class FrictionTagRegistrationScanner: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<FrictionTagRegistrationResult, Error>?

    func scan() async throws -> FrictionTagRegistrationResult {
        guard NFCTagReaderSession.readingAvailable else {
            throw FrictionTagRegistrationError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard let session = NFCTagReaderSession(
                pollingOption: [.iso14443, .iso15693, .iso18092],
                delegate: self,
                queue: nil
            ) else {
                self.continuation = nil
                continuation.resume(throwing: FrictionTagRegistrationError.unavailable)
                return
            }
            self.session = session
            session.alertMessage = "Acerca el iPhone a la etiqueta NFC que quieres guardar."
            session.begin()
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        if tags.count > 1 {
            session.alertMessage = "Usa solo una etiqueta NFC a la vez."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }

            if let error {
                self.finish(session: session, error: error)
                return
            }

            do {
                let result = try Self.makeResult(from: tag)
                session.alertMessage = "Etiqueta guardada."
                self.finish(session: session, result: result)
            } catch {
                self.finish(session: session, error: error)
            }
        }
    }

    private func finish(session: NFCTagReaderSession, result: FrictionTagRegistrationResult) {
        let continuation = continuation
        self.continuation = nil
        self.session = nil
        continuation?.resume(returning: result)
        session.invalidate()
    }

    private func finish(session: NFCTagReaderSession, error: Error) {
        let continuation = continuation
        self.continuation = nil
        self.session = nil
        continuation?.resume(throwing: error)
        session.invalidate(errorMessage: error.localizedDescription)
    }

    private static func makeResult(from tag: NFCTag) throws -> FrictionTagRegistrationResult {
        let identifier: Data

        switch tag {
        case .miFare(let tag):
            identifier = tag.identifier
        case .iso7816(let tag):
            identifier = tag.identifier
        case .iso15693(let tag):
            identifier = tag.identifier
        case .feliCa(let tag):
            identifier = tag.currentIDm
        @unknown default:
            throw FrictionTagRegistrationError.unsupported
        }

        let raw = identifier.map { String(format: "%02x", $0) }.joined()
        let normalized = normalizeFrictionTagIdentifier(raw)
        guard !normalized.isEmpty else {
            throw FrictionTagRegistrationError.unsupported
        }

        return FrictionTagRegistrationResult(
            normalizedIdentifier: normalized,
            displayName: "Tag \(normalized.uppercased())"
        )
    }
}

/// Minutes and seconds, on two sliders.
///
/// Two rather than one, because a single slider spanning five seconds to three minutes
/// gives about a pixel per second at the short end -- where all the useful values are.
/// Splitting it means the minute slider picks the scale and the second slider is precise
/// within it.
private struct LocktyBreatheMenu: View {
    @Binding var seconds: Int

    private var minutes: Int { seconds / 60 }
    private var remainder: Int { seconds % 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            Text(LocktyBreathe.label(seconds))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.22), value: seconds)
                .frame(maxWidth: .infinity)

            slider(
                title: "Minutes",
                value: Double(minutes),
                range: 0...Double(LocktyBreathe.maximumSeconds / 60)
            ) { newValue in
                update(minutes: Int(newValue.rounded()), remainder: remainder)
            }

            slider(
                title: "Seconds",
                value: Double(remainder),
                range: 0...59
            ) { newValue in
                update(minutes: minutes, remainder: Int(newValue.rounded()))
            }
        }
        .padding(LocktySpacing.lg)
        .frame(width: 260)
    }

    private func slider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xs) {
            Text(title)
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            DurationSlider(
                value: Binding(get: { value }, set: onChange),
                range: range
            )
        }
    }

    /// Clamped on the way in, so the two sliders cannot between them ask for less than
    /// the minimum or more than the maximum -- dragging minutes to three while seconds
    /// sit at thirty would otherwise land past the top.
    private func update(minutes: Int, remainder: Int) {
        seconds = LocktyBreathe.clamped(minutes * 60 + remainder)
    }
}

/// A labelled field, laid out like the rows beside it.
///
/// The bare glass text field was the one control on the sheet with no name of its own --
/// its placeholder had to do that job, and vanished the moment anything was typed.
private struct FrictionSettingsField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            TextField("", text: $text, axis: .vertical)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1...4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LocktySpacing.sm)
    }
}

/// The rule between two settings. Inset from neither edge, because the card's own padding
/// is the inset -- a divider that stops short of the text above it reads as a mistake.
private struct FrictionSettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(LocktyColors.separator.opacity(0.45))
    }
}
