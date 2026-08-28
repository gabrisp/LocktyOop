import SwiftUI

struct TodayMetricsHeader: View {
    let metrics: [PrimaryMetric]
    let collapseProgress: CGFloat
    var topInset: CGFloat = 0
    var onMetricSelected: ((PrimaryMetric) -> Void)?

    private var geometry: MetricsHeaderGeometry {
        MetricsHeaderGeometry(progress: collapseProgress)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(metrics) { metric in
                Button { onMetricSelected?(metric) } label: {
                    MetricRingView(metric: metric, collapseProgress: collapseProgress)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity)
        .frame(height: geometry.height + topInset, alignment: .top)
        // The backdrop is applied as a background (not a sibling in a ZStack) so it can extend
        // past this view's own bounds into the status bar area without the layout clipping it,
        // and spans the full width because no horizontal padding is applied outside this view.
        .background {
            LocktyColors.background
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.65),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(edges: .top)
        }
    }
}
