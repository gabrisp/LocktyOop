import Foundation

enum ExtensionTargetBoundary: String, CaseIterable, Identifiable {
    case deviceActivityMonitor
    case deviceActivityReport
    case shieldConfiguration
    case shieldAction

    var id: String { rawValue }

    var responsibility: String {
        switch self {
        case .deviceActivityMonitor:
            "Monitor activity thresholds, break expiry, Pause allowance expiry, and shield reapplication."
        case .deviceActivityReport:
            "Own DeviceActivity report UI and usage aggregation surfaces required by Apple APIs."
        case .shieldConfiguration:
            "Build Lockty shield presentation from App Group runtime snapshots."
        case .shieldAction:
            "Handle shield actions, create pending Pause contexts, and request supported Lockty launch routing."
        }
    }

    var dependencyRule: String {
        "Use only extension-safe Core/Domain and Core/Shared code. Do not depend on SwiftData, Appwrite, or SwiftUI feature views."
    }
}
