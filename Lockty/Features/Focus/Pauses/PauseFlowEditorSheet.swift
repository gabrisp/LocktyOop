import Combine
import SwiftUI

@MainActor
final class PauseFlowEditorViewModel: ObservableObject {
    let editingID: UUID

    @Published var name = ""
    @Published var steps: [PauseStep] = PauseFlow.defaultSteps
    @Published var errorMessage: String?
    /// Which step's settings are open. Only one at a time -- the sheet grows to fit it,
    /// and two open at once is most of a screen of controls.
    @Published var expandedStepID: UUID?

    private let repository: PauseFlowRepository
    private let initialFlowID: UUID?
    private var createdAt: Date
    private var hasLoaded = false

    init(flowID: UUID?, repository: PauseFlowRepository) {
        initialFlowID = flowID
        editingID = flowID ?? UUID()
        self.repository = repository
        createdAt = Date()
    }

    var isCreating: Bool { initialFlowID == nil }
    var title: String { isCreating ? "New pause" : "Editar pausa" }

    /// Identity of what is on screen, so the sheet knows when to crossfade and re-measure.
    var contentID: String {
        "\(steps.map(\.id.uuidString).joined())-\(expandedStepID?.uuidString ?? "none")"
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let initialFlowID, let flow = await repository.flow(id: initialFlowID) else { return }
        createdAt = flow.createdAt
        name = flow.name
        steps = flow.steps
    }

    func addStep(_ kind: EditablePauseStep) {
        steps.append(kind.defaultStep)
    }

    func removeStep(id: UUID) {
        steps.removeAll { $0.id == id }
        if expandedStepID == id { expandedStepID = nil }
    }

    func toggleExpanded(_ id: UUID) {
        expandedStepID = expandedStepID == id ? nil : id
    }

    /// Returns the saved flow so whatever asked for it can use it -- the routine editor
    /// selects the pause it just created rather than making the user find it again.
    func save() async -> PauseFlow? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Ponle un nombre a la pausa."
            return nil
        }
        guard !steps.isEmpty else {
            errorMessage = "Add at least one step."
            return nil
        }

        let flow = PauseFlow(
            id: editingID,
            name: trimmedName,
            steps: steps,
            createdAt: createdAt,
            updatedAt: Date()
        )

        do {
            try await repository.save(flow)
            return flow
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

/// Writing a pause flow. No app anywhere in it: a flow is a way of pausing, and which
/// apps it covers is decided by the routine that picks it up.
///
/// The sheet is only the frame. Everything on it lives in PauseFlowEditorContent, which
/// the routine editor pushes into its own sheet so a pause can be written from there
/// without leaving the routine being written.
struct PauseFlowEditorSheet: View {
    @StateObject private var viewModel: PauseFlowEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PauseFlowEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        LocktyDynamicSheet(animation: .snappy(duration: 0.3, extraBounce: 0)) {
            PauseFlowEditorContent(viewModel: viewModel) { _ in dismiss() }
                .locktyDynamicSheetChrome(id: viewModel.contentID) {
                    Text(viewModel.title)
                        .font(.system(.title3, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                } leading: {
                    Color.clear
                } trailing: {
                    LocktyDynamicSheetBarButton(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
        }
        .task { await viewModel.load() }
    }
}

/// The pause itself: its name, its steps, and the hold that commits it.
struct PauseFlowEditorContent: View {
    @ObservedObject var viewModel: PauseFlowEditorViewModel
    /// Handed the flow that was written, so the host can select it or dismiss.
    let onSaved: (PauseFlow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            nameField

            stepsSection

            LocktyHoldButton(title: viewModel.isCreating ? "Hold to create" : "Hold to save") {
                Task {
                    if let flow = await viewModel.save() { onSaved(flow) }
                }
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.lg)
        .padding(.bottom, LocktySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var nameField: some View {
        TextField("Name", text: $viewModel.name)
            .font(.system(.subheadline, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LocktyColors.elevatedBackground)
            )
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("FLUJO")
                .locktyEyebrow()

            ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                PauseFlowStepRow(
                    step: binding(at: index),
                    isExpanded: viewModel.expandedStepID == step.id,
                    onToggle: {
                        withAnimation(.smooth(duration: 0.3)) {
                            viewModel.toggleExpanded(step.id)
                        }
                    },
                    onRemove: {
                        withAnimation(.smooth(duration: 0.3)) {
                            viewModel.removeStep(id: step.id)
                        }
                    }
                )
            }

            Menu {
                ForEach(EditablePauseStep.allCases) { kind in
                    Button(kind.rawValue.capitalized) {
                        withAnimation(.smooth(duration: 0.3)) {
                            viewModel.addStep(kind)
                        }
                    }
                }
            } label: {
                Label("Add step", systemImage: "plus")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LocktySpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LocktyColors.elevatedBackground)
                    )
            }
        }
    }

    private func binding(at index: Int) -> Binding<PauseStep> {
        Binding(
            get: { viewModel.steps[index] },
            set: { viewModel.steps[index] = $0 }
        )
    }
}

/// A step, collapsed to its name and what it does, opening to its settings when tapped.
struct PauseFlowStepRow: View {
    @Binding var step: PauseStep
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            Button(action: onToggle) {
                HStack(spacing: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title)
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)

                        Text(step.detail)
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))

            if isExpanded {
                settings
                    .transition(.blurReplace.combined(with: .opacity))

                Button(role: .destructive, action: onRemove) {
                    Label("Remove step", systemImage: "xmark")
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(LocktySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LocktyColors.elevatedBackground)
        )
    }

    @ViewBuilder
    private var settings: some View {
        switch step {
        case .countdown(let configuration):
            labelled("Seconds", value: "\(Int(configuration.duration))") {
                DurationSlider(value: binding(configuration).duration, range: 1...60)
            }

        case .breathing(let configuration):
            labelled("Breaths", value: "\(configuration.breathCount)") {
                DurationSlider(value: binding(configuration).breathCount.doubleProxy, range: 1...10)
            }

        case .steps(let configuration):
            labelled(
                "Daily steps",
                value: configuration.dailyGoal.formatted(.number.grouping(.automatic))
            ) {
                DurationSlider(value: binding(configuration).dailyGoal.doubleProxy, range: 1000...25000)
            }

        case .intention(let configuration):
            TextField("Question", text: binding(configuration).prompt, axis: .vertical)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(2...4)

        case .confirmation(let configuration):
            TextField("Question", text: binding(configuration).prompt, axis: .vertical)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(2...3)

        case .wordSearch,
             .letterMatch,
             .operations,
             .intentionTemplate,
             .customIntention,
             .personalVideo,
             .personalText,
             .nfcTag,
             .location:
            Text(step.detail)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.secondaryText)
        }
    }

    @ViewBuilder
    private func labelled<Control: View>(
        _ title: String,
        value: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            HStack {
                Text(title)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.secondaryText)

                Spacer(minLength: 0)

                Text(value)
                    .font(.system(.subheadline, design: .rounded, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(LocktyColors.primaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: value)
            }

            control()
        }
    }

    private func binding(_ configuration: CountdownConfiguration) -> Binding<CountdownConfiguration> {
        Binding(get: { configuration }, set: { step = .countdown($0) })
    }

    private func binding(_ configuration: BreathingConfiguration) -> Binding<BreathingConfiguration> {
        Binding(get: { configuration }, set: { step = .breathing($0) })
    }

    private func binding(_ configuration: StepsConfiguration) -> Binding<StepsConfiguration> {
        Binding(get: { configuration }, set: { step = .steps($0) })
    }

    private func binding(_ configuration: IntentionConfiguration) -> Binding<IntentionConfiguration> {
        Binding(get: { configuration }, set: { step = .intention($0) })
    }

    private func binding(_ configuration: ConfirmationConfiguration) -> Binding<ConfirmationConfiguration> {
        Binding(get: { configuration }, set: { step = .confirmation($0) })
    }
}
