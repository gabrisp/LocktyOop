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
        // Solid fill behind the rings (extended up under the status bar), then a real
        // gradient fade below it. Splitting the two means the solid part can grow upward
        // via ignoresSafeArea without the mask's gradient stops shifting with it.
        .background(alignment: .top) {
            VStack(spacing: 0) {
                LocktyColors.background
                    .frame(height: geometry.backdropHeight + topInset)

                LinearGradient(
                    colors: [LocktyColors.background, LocktyColors.background.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
        }
    }
}
