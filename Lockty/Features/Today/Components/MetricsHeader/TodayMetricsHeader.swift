import SwiftUI

struct TodayMetricsHeader: View {
    let metrics: [PrimaryMetric]
    let collapseProgress: CGFloat
    var onMetricSelected: ((PrimaryMetric) -> Void)?

    private var geometry: MetricsHeaderGeometry {
        MetricsHeaderGeometry(progress: collapseProgress)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(height: geometry.height)
                .safeGlass(radius: LocktyRadius.large)
                .opacity(geometry.backgroundOpacity)

            HStack(alignment: .top, spacing: 0) {
                ForEach(metrics) { metric in
                    Button { onMetricSelected?(metric) } label: {
                        MetricRingView(metric: metric, collapseProgress: collapseProgress)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, LocktySpacing.sm)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: geometry.height)
    }
}
