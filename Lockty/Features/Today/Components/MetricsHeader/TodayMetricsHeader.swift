import SwiftUI
import UIKit

struct TodayMetricsHeader: View {
    let metrics: [PrimaryMetric]
    let collapseProgress: CGFloat
    var topInset: CGFloat = 0
    var onMetricSelected: ((PrimaryMetric) -> Void)?

    private var geometry: MetricsHeaderGeometry {
        MetricsHeaderGeometry(progress: collapseProgress)
    }

    /// The status bar / notch inset. Read from the window rather than a GeometryReader
    /// because this view is positioned inside a ZStack that already sits below it.
    private var safeAreaTop: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    /// Exactly the area the backdrop should cover: the safe area above the header plus
    /// the header's own current content height (which shrinks as it collapses), plus 2.
    private var backdropHeight: CGFloat {
        safeAreaTop + geometry.height + topInset + 2
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
        // One gradient spanning the safe area plus the current (collapsing) content
        // height, so it always ends just below the rings instead of being sized to the
        // expanded layout. It stays opaque for most of that span and fades out at the
        // very bottom edge.
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: LocktyColors.background, location: 0),
                    .init(color: LocktyColors.background, location: 0.82),
                    .init(color: LocktyColors.background.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: backdropHeight)
            .ignoresSafeArea(edges: .top)
        }
    }
}
