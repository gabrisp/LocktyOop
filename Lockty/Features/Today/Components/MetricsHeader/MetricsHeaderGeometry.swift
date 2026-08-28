import CoreGraphics

struct MetricsHeaderGeometry {
    static let expandedHeight: CGFloat = 152
    static let collapsedHeight: CGFloat = 54
    static let collapseDistance: CGFloat = 112
    static let expandedDiameter: CGFloat = 92
    static let collapsedDiameter: CGFloat = 26
    static let labelHeight: CGFloat = 16
    static let expandedLabelGap: CGFloat = 8
    static let collapsedLabelGap: CGFloat = 4
    static let expandedLabelWidth: CGFloat = 108
    static let collapsedLabelWidth: CGFloat = 88

    let progress: CGFloat

    var height: CGFloat {
        Self.lerp(Self.expandedHeight, Self.collapsedHeight, progress: progress)
    }

    var ringDiameter: CGFloat {
        Self.lerp(Self.expandedDiameter, Self.collapsedDiameter, progress: progress)
    }

    var strokeWidth: CGFloat {
        Self.lerp(10, 4, progress: progress)
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

    var contentTopOffset: CGFloat {
        Self.lerp(
            ((Self.expandedHeight - Self.expandedDiameter - Self.expandedLabelGap - Self.labelHeight) / 2) + 8,
            (Self.collapsedHeight - Self.collapsedDiameter) / 2,
            progress: progress
        )
    }

    var labelGap: CGFloat {
        Self.lerp(Self.expandedLabelGap, Self.collapsedLabelGap, progress: progress)
    }

    var labelTextShiftProgress: CGFloat {
        Self.rangedProgress(progress, from: 0.55, to: 1)
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
