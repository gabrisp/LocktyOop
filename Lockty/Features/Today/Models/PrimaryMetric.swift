import Foundation
import CoreGraphics

/// The three numbers the day is judged by.
///
/// Chosen for one property: you can name what would move each of them tomorrow. The
/// three before these were Productivity, Control and Detox, and two of them were
/// composites of composites -- Control was routine completion plus pause abandonment
/// plus restriction adherence minus a fragmentation penalty -- so nobody could feel what
/// moved them. A metric you cannot act on is decoration.
enum PrimaryMetricKind: String, CaseIterable, Codable, Hashable, Identifiable {
    /// Where the time went, weighted by what each app is called.
    case focus
    /// Time away from the phone, weighted towards long stretches.
    case detox
    /// How many times the phone was picked up.
    case checks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .detox: "Detox"
        case .checks: "Checks"
        }
    }

    /// A glyph for the places that show the three side by side and have no room to
    /// spell them out. Productivity is a leaf rather than a chart: it is about what the
    /// time went to, not how much of it there was.
    var systemImage: String {
        switch self {
        case .focus: "leaf.fill"
        case .detox: "moon.zzz.fill"
        case .checks: "iphone.gen3"
        }
    }

    var collapsedTextWidth: CGFloat {
        switch self {
        case .focus: 56
        case .detox: 52
        case .checks: 60
        }
    }
}

enum DailyScoreTone: String, Codable, Hashable {
    case strong
    case balanced
    case weak

    nonisolated static func tone(for value: Double) -> DailyScoreTone {
        switch value {
        case 80...100:
            .strong
        case 45..<80:
            .balanced
        default:
            .weak
        }
    }
}

struct PrimaryMetric: Codable, Hashable, Identifiable {
    var id: PrimaryMetricKind { kind }

    let kind: PrimaryMetricKind
    /// What the circle shows. A percentage for two of them and a count for Checks, which
    /// is why this is no longer assumed to be the same number as the ring.
    let value: Double
    /// How far round the rim goes, 0 to 1.
    ///
    /// Separate from `value` because a count has no natural hundred. Checks fills its
    /// ring by how it compares with the days before it -- full when well under, empty
    /// when well over -- so a good day is a full ring whichever metric you are reading.
    let progress: Double
    let displayValue: String
    let tone: DailyScoreTone

    /// A score out of a hundred: the value and the ring are the same thing.
    init(kind: PrimaryMetricKind, value: Double) {
        let clampedValue = min(max(value, 0), 100)

        self.kind = kind
        self.value = clampedValue
        self.progress = clampedValue / 100
        self.displayValue = "\(Int(clampedValue.rounded()))%"
        self.tone = DailyScoreTone.tone(for: clampedValue)
    }

    /// A count, with its ring given separately.
    init(kind: PrimaryMetricKind, count: Int, progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)

        self.kind = kind
        self.value = Double(count)
        self.progress = clampedProgress
        self.displayValue = "\(count)"
        // Toned by the ring, not by the count: eighty checks is a good day for one person
        // and a bad one for another, and the ring is the only part that knows which.
        self.tone = DailyScoreTone.tone(for: clampedProgress * 100)
    }
}

struct PrimaryMetricsState: Codable, Hashable {
    var metrics: [PrimaryMetric]

    static let loading = PrimaryMetricsState(
        metrics: PrimaryMetricKind.allCases.map { PrimaryMetric(kind: $0, value: 0) }
    )
}
