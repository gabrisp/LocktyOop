import SwiftUI

struct DigitalBalanceCard: View {
    let state: UsageTimelineChartState
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            LocktySectionTitle(
                "Digital Balance",
                info: "How your screen time was split across the day, coloured by how each app is classified. Taller bands mean heavier use in that part of the day.",
                showsSeparator: false
            )
            .padding(.top, 16)

            Button(action: action) {
                CardView(radius: LocktyRadius.large, padding: LocktySpacing.md, interactive: true) {
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        if state.buckets.isEmpty {
                            EmptyStateView(
                                title: "No timeline available",
                                message: "This graph appears when Lockty has Screen Time activity buckets for the selected day.",
                                systemImage: "waveform.path.ecg.rectangle"
                            )
                            .frame(height: 176)
                        } else {
                            UsageTimelineChart(state: state)
                                .frame(height: 176)
                        }

                        TimelineLegend()
                    }
                }
            }
            .buttonStyle(.locktyInteractive)
            .tappable()
        }
    }
}

private struct TimelineLegend: View {
    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            LegendItem(title: "Productive", color: LocktyColors.productive)
            LegendItem(title: "Neutral", color: LocktyColors.neutral)
            LegendItem(title: "Unproductive", color: LocktyColors.unproductive)
        }
    }
}

private struct LegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: LocktySpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(LocktyTypography.caption)
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
        }
    }
}
