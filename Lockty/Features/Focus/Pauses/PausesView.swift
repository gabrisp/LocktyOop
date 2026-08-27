import SwiftUI

struct PausesView: View {
    let viewModel: PausesViewModel
    let router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack {
                SectionHeader(title: "Pauses")
                IconButton(systemImage: "plus", accessibilityLabel: "Add Pause") {
                    router.push(.pauseEditor(nil))
                }
            }

            CardView {
                HStack(spacing: LocktySpacing.lg) {
                    MetricRingView(metric: PrimaryMetric(kind: .control, value: Double(viewModel.state.summary.successRateValue ?? 0)), collapseProgress: 0)
                        .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text("Pause Success")
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                        Text("\(viewModel.state.summary.stoppedCount) stopped of \(viewModel.state.summary.triggeredCount)")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                        Text("\(viewModel.state.reclaimedTimeText) estimated reclaimed")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
            }

            SectionHeader(title: "Your Pauses")
            if viewModel.state.rules.isEmpty {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        EmptyStateView(
                            title: "No Pauses Yet",
                            message: "Create a Pause to force a deliberate decision before opening one distracting app.",
                            systemImage: "pause.circle"
                        )

                        PrimaryButton("Create Pause", systemImage: "plus") {
                            router.push(.pauseEditor(nil))
                        }
                    }
                }
            } else {
                ForEach(viewModel.state.rules) { rule in
                    Button { router.push(.pauseDetail(rule.id)) } label: {
                        CardView(interactive: true) {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                HStack {
                                    Text(rule.name).font(LocktyTypography.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(LocktyColors.tertiaryText)
                                }
                                Text(rule.flow).font(LocktyTypography.caption).foregroundStyle(LocktyColors.secondaryText)
                                Text("\(rule.successRate) · \(rule.stopped) stopped")
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(LocktyColors.productive)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .tappable()
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.load()
            }
        }
        .onChange(of: router.path) { _, _ in
            Task {
                await viewModel.load()
            }
        }
    }
}
