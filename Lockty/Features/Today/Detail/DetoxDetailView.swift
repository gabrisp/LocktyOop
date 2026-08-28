import SwiftUI

struct DetoxDetailView: View {
    let day: Date
    let viewModel: TodayViewModel
    @Environment(\.dismiss) private var dismiss

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
        .safeSafeAreaBar(edge: .top, spacing: 0) {
            LocktyTopBar(title: "Best Detox") {
                LocktyTopBarIconAction(systemImage: "chevron.left", label: "Back") {
                    dismiss()
                }
            } trailing: {
                Text(day.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .locktyScreenBackground()
    }
}
