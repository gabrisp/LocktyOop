import SwiftUI

struct PausesView: View {
    let viewModel: PausesViewModel
    let router: AppRouter

    private let columns = [
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing),
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing)
    ]

    var body: some View {
        // Same shape as Routines: a two-column grid whose last tile is "Add", with no
        // separate create button underneath and no summary card above.
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            if viewModel.isLockedByActiveRoutine {
                EditingDisabledBanner(message: viewModel.activeRoutineLockMessage)
            }

//            CardView {
//                HStack(spacing: LocktySpacing.lg) {
//                    MetricRingView(metric: PrimaryMetric(kind: .control, value: Double(viewModel.state.summary.successRateValue ?? 0)), collapseProgress: 0)
//                        .frame(width: 92, height: 92)
//                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
//                        Text("Pause Success")
//                            .font(LocktyTypography.headline)
//                            .foregroundStyle(LocktyColors.primaryText)
//                        Text("\(viewModel.state.summary.stoppedCount) stopped of \(viewModel.state.summary.triggeredCount)")
//                            .font(LocktyTypography.callout)
//                            .foregroundStyle(LocktyColors.secondaryText)
//                        Text("\(viewModel.state.reclaimedTimeText) estimated reclaimed")
//                            .font(LocktyTypography.caption)
//                            .foregroundStyle(LocktyColors.secondaryText)
//                    }
//                }
//            }

            LazyVGrid(columns: columns, spacing: RoutineGridMetrics.spacing) {
                ForEach(viewModel.state.rules) { rule in
                    PauseCard(rule: rule) {
                        router.presentSheet(.pauseEditor(PauseEditorRoute(pauseID: rule.id)))
                    }
                }

                // No way in to creating one while a routine is running.
                if !viewModel.isLockedByActiveRoutine {
                    addPauseTile
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.load()
            }
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                await viewModel.load()
            }
        }
    }

    private var addPauseTile: some View {
        Button {
            router.presentSheet(.pauseEditor(PauseEditorRoute(pauseID: nil)))
        } label: {
            CardView(interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text("Add Pause")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}

/// Grid tile for a Pause, matching RoutineCard.
private struct PauseCard: View {
    let rule: PauseRuleSummaryState
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardView(interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: "pause")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name)
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Text(rule.flow)
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
