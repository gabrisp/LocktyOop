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
            LocktyColors.background
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.7),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(geometry.backgroundOpacity)
                .ignoresSafeArea(edges: .top)

            HStack(alignment: .top, spacing: 0) {
                ForEach(metrics) { metric in
                    Button { onMetricSelected?(metric) } label: {
                        MetricRingView(metric: metric, collapseProgress: collapseProgress)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: geometry.height)
    }
}
