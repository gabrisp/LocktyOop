import CoreGraphics

struct MetricsHeaderGeometry {
    static let expandedHeight: CGFloat = 152
    static let collapsedHeight: CGFloat = 60
    static let collapseDistance: CGFloat = 112
    static let expandedDiameter: CGFloat = 92
    /// Wide enough for the number to sit centred inside the ring rather than fill it.
    static let collapsedDiameter: CGFloat = 34
    static let labelHeight: CGFloat = 16
    static let expandedLabelGap: CGFloat = 6
    static let collapsedLabelGap: CGFloat = 4
    static let expandedLabelWidth: CGFloat = 112
    static let collapsedLabelWidth: CGFloat = 92

    let progress: CGFloat

    var height: CGFloat {
        Self.lerp(Self.expandedHeight, Self.collapsedHeight, progress: progress)
    }

    var ringDiameter: CGFloat {
        Self.lerp(Self.expandedDiameter, Self.collapsedDiameter, progress: progress)
    }

    /// Thinner at both ends than it was: a heavy ring around a small circle leaves the
    /// number nowhere to sit.
    var strokeWidth: CGFloat {
        Self.lerp(7, 2.5, progress: progress)
    }

    var valueOpacity: CGFloat {
        1 - Self.rangedProgress(progress, from: 0.08, to: 0.65)
    }

    var labelProgress: CGFloat {
        Self.rangedProgress(progress, from: 0.12, to: 1)
    }

    var backgroundOpacity: CGFloat {
        Self.rangedProgress(progress, from: 0.45, to: 1)
    }

    var backdropHeight: CGFloat {
        contentTopOffset + ringDiameter + 2
    }

    var contentTopOffset: CGFloat {
        Self.lerp(
            ((Self.expandedHeight - Self.expandedDiameter - Self.expandedLabelGap - Self.labelHeight) / 2) + 2,
            ((Self.collapsedHeight - Self.collapsedDiameter) / 2) + 1,
            progress: progress
        )
    }

    var labelGap: CGFloat {
        Self.lerp(Self.expandedLabelGap, Self.collapsedLabelGap, progress: progress)
    }
    static func collapseProgress(for scrollOffset: CGFloat) -> CGFloat {
        clamp(scrollOffset / collapseDistance)
    }

    nonisolated static func lerp(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * clamp(progress)
    }

    nonisolated static func rangedProgress(_ progress: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return progress >= end ? 1 : 0 }
        return clamp((progress - start) / (end - start))
    }

    nonisolated static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
