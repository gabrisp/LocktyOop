import Foundation
import CoreGraphics

enum PrimaryMetricKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case productivity
    case control
    case detox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .productivity: "Productivity"
        case .control: "Control"
        case .detox: "Detox"
        }
    }

    var collapsedTextWidth: CGFloat {
        switch self {
        case .productivity:
            84
        case .control:
            56
        case .detox:
            44
        }
    }
}

enum DailyScoreTone: String, Codable, Hashable {
    case strong
    case balanced
    case weak

    nonisolated static func tone(for value: Double) -> DailyScoreTone {
        switch value {
        case 70...100:
            .strong
        case 40..<70:
            .balanced
        default:
            .weak
        }
    }
}

struct PrimaryMetric: Codable, Hashable, Identifiable {
    var id: PrimaryMetricKind { kind }

    let kind: PrimaryMetricKind
    let value: Double
    let progress: Double
    let displayValue: String
    let tone: DailyScoreTone

    init(kind: PrimaryMetricKind, value: Double) {
        let clampedValue = min(max(value, 0), 100)

        self.kind = kind
        self.value = clampedValue
        self.progress = clampedValue / 100
        self.displayValue = "\(Int(clampedValue.rounded()))%"
        self.tone = DailyScoreTone.tone(for: clampedValue)
    }
}

struct PrimaryMetricsState: Codable, Hashable {
    var metrics: [PrimaryMetric]

    static let loading = PrimaryMetricsState(
        metrics: PrimaryMetricKind.allCases.map { PrimaryMetric(kind: $0, value: 0) }
    )
}
