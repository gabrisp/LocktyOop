import SwiftUI

struct DetoxDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    private var state: TodayDayState { viewModel.state(for: day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text("Best Detox").font(LocktyTypography.largeTitle)
                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text(state.metrics.bestDetox.durationText).font(LocktyTypography.largeTitle).monospacedDigit()
                        Text(state.metrics.bestDetox.comparisonText).font(LocktyTypography.callout).foregroundStyle(LocktyColors.secondaryText)
                        Text("This is calculated from the phone-free intervals available for this day.")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                }
            }
            .padding(LocktySpacing.md)
        }
        .task { await viewModel.load(day: day) }
        .navigationTitle(day.formatted(date: .abbreviated, time: .omitted))
        .locktyScreenBackground()
    }
}
