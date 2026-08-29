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
    var title: String { isCreating ? "Nueva pausa" : "Editar pausa" }

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

    func save() async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Ponle un nombre a la pausa."
            return false
        }
        guard !steps.isEmpty else {
            errorMessage = "Añade al menos un paso."
            return false
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
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// Writing a pause flow. No app anywhere in it: a flow is a way of pausing, and which
/// apps it covers is decided by the routine that picks it up.
struct PauseFlowEditorSheet: View {
    @StateObject private var viewModel: PauseFlowEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PauseFlowEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        LocktyDynamicSheet(animation: .smooth(duration: 0.32), contentID: viewModel.contentID) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                nameField

                stepsSection

                saveButton
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.top, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.xl)
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
        .alert(
            "No se pudo guardar",
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
        TextField("Nombre", text: $viewModel.name)
            .font(LocktyTypography.body)
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
                Label("Añadir paso", systemImage: "plus")
                    .font(LocktyTypography.callout)
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

    private var saveButton: some View {
        Button {
            Task {
                if await viewModel.save() { dismiss() }
            }
        } label: {
            Text("Guardar")
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule(style: .continuous).fill(.white))
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
    }

    private func binding(at index: Int) -> Binding<PauseStep> {
        Binding(
            get: { viewModel.steps[index] },
            set: { viewModel.steps[index] = $0 }
        )
    }
}

/// A step, collapsed to its name and what it does, opening to its settings when tapped.
private struct PauseFlowStepRow: View {
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
            .buttonStyle(.plain)

            if isExpanded {
                settings
                    .transition(.blurReplace.combined(with: .opacity))

                Button(role: .destructive, action: onRemove) {
                    Label("Quitar paso", systemImage: "xmark")
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
            labelled("Segundos", value: "\(Int(configuration.duration))") {
                DurationSlider(value: binding(configuration).duration, range: 1...60)
            }

        case .breathing(let configuration):
            labelled("Respiraciones", value: "\(configuration.breathCount)") {
                DurationSlider(value: binding(configuration).breathCount.doubleProxy, range: 1...10)
            }

        case .intention(let configuration):
            TextField("Pregunta", text: binding(configuration).prompt, axis: .vertical)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(2...4)

        case .confirmation(let configuration):
            TextField("Pregunta", text: binding(configuration).prompt, axis: .vertical)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(2...3)
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

    private func binding(_ configuration: IntentionConfiguration) -> Binding<IntentionConfiguration> {
        Binding(get: { configuration }, set: { step = .intention($0) })
    }

    private func binding(_ configuration: ConfirmationConfiguration) -> Binding<ConfirmationConfiguration> {
        Binding(get: { configuration }, set: { step = .confirmation($0) })
    }
}
