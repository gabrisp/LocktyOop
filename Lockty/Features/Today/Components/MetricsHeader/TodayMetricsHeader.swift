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
        // The backdrop is not here: it used to be a .background on this view, which
        // anchors it to a frame that moves as the chrome above the rings appears and
        // disappears, so it slid around and stopped reaching the status bar. TodayView
        // draws it as its own top-anchored layer instead.
        .frame(height: geometry.height + topInset, alignment: .top)
    }
}
