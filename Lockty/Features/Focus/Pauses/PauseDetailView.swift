import SwiftUI

@MainActor
@Observable
final class PauseDetailViewModel {
    private let pauseID: UUID
    private let repository: PauseRuleRepository
    private let eventRepository: PauseEventRepository

    private(set) var rule: PauseRule?
    private(set) var events: [PauseEvent] = []

    init(
        pauseID: UUID,
        repository: PauseRuleRepository,
        eventRepository: PauseEventRepository
    ) {
        self.pauseID = pauseID
        self.repository = repository
        self.eventRepository = eventRepository
    }

    func load() async {
        rule = await repository.rule(id: pauseID)
        events = (await eventRepository.events(from: nil, to: nil))
            .filter { $0.pauseRuleID == pauseID }
            .sorted { $0.triggeredAt > $1.triggeredAt }
    }

    func delete() async {
        do {
            try await repository.delete(id: pauseID)
        } catch {
            print("Pause detail failed deleting id=\(pauseID.uuidString): \(error.localizedDescription)")
        }
    }
}

struct PauseDetailView: View {
    @Bindable var viewModel: PauseDetailViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                if let rule = viewModel.rule {
                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text(rule.application.displayName).font(LocktyTypography.title)
                            Text(rule.isEnabled ? "Pause enabled" : "Pause disabled")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                            Text("Allowance: \(LocktyDurationFormatter.abbreviated(rule.allowanceDuration))")
                                .font(LocktyTypography.caption)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text("Flow").font(LocktyTypography.headline)
                            ForEach(Array(rule.steps.enumerated()), id: \.element.id) { index, step in
                                HStack {
                                    Text("\(index + 1). \(step.title)")
                                    Spacer()
                                    Text(step.detail).foregroundStyle(LocktyColors.secondaryText)
                                }
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text("Recent Events").font(LocktyTypography.headline)
                            if viewModel.events.isEmpty {
                                Text("No Pause history yet.")
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                            } else {
                                ForEach(viewModel.events.prefix(20)) { event in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(event.triggeredAt.formatted(date: .abbreviated, time: .shortened))
                                            Spacer()
                                            Text(event.decision.rawValue.capitalized)
                                                .foregroundStyle(event.decision == .abandoned ? LocktyColors.productive : LocktyColors.unproductive)
                                        }
                                        if let intention = event.intention, !intention.isEmpty {
                                            Text(intention)
                                                .font(LocktyTypography.caption)
                                                .foregroundStyle(LocktyColors.secondaryText)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
        .navigationTitle(viewModel.rule?.application.displayName ?? "Pause")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let rule = viewModel.rule {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        router.push(.pauseEditor(PauseEditorRoute(pauseID: rule.id)))
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(role: .destructive) {
                Task {
                    await viewModel.delete()
                    dismiss()
                }
            } label: {
                Text("Delete Pause")
            }
            .buttonStyle(.plain)
            .locktySecondaryActionStyle()
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.sm)
        }
    }
}
