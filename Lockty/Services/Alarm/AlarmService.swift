import Foundation

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import SwiftUI
#endif

protocol AlarmServicing {
    func capabilities() -> SystemCapabilities
    func authorizationState() async -> AlarmAuthorizationState
    func requestAuthorization() async -> AlarmAuthorizationState
    func triggerRoutineStartAlarm(for routine: Routine) async throws
}

enum AlarmAuthorizationState: String, Codable, Hashable {
    case notDetermined, authorized, denied, unsupported, unavailable
}

struct LiveAlarmService: AlarmServicing {
    func capabilities() -> SystemCapabilities { .current }

    func authorizationState() async -> AlarmAuthorizationState {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            @unknown default: return .unavailable
            }
        }
        #endif
        return .unsupported
    }

    func requestAuthorization() async -> AlarmAuthorizationState {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                switch try await AlarmManager.shared.requestAuthorization() {
                case .notDetermined: return .notDetermined
                case .authorized: return .authorized
                case .denied: return .denied
                @unknown default: return .unavailable
                }
            } catch { return .unavailable }
        }
        #endif
        return .unsupported
    }

    func triggerRoutineStartAlarm(for routine: Routine) async throws {
        guard routine.startAlarmEnabled else { return }

        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) {
            guard AlarmManager.shared.authorizationState == .authorized else {
                print("Routine start alarm skipped because AlarmKit is not authorized for routine id=\(routine.id.uuidString)")
                return
            }

            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(
                    alert: .init(title: "Routine started"),
                    countdown: .init(title: routine.name.isEmpty ? "Lockty" : "Starting \(routine.name)")
                ),
                metadata: RoutineStartAlarmMetadata(routineID: routine.id, routineName: routine.name),
                tintColor: .orange
            )

            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: 1,
                attributes: attributes,
                sound: .default
            )

            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            print("Triggered routine start alarm for routine id=\(routine.id.uuidString) name=\(routine.name)")
            return
        }
        #endif

        print("Routine start alarm unsupported on this OS for routine id=\(routine.id.uuidString)")
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct RoutineStartAlarmMetadata: AlarmMetadata {
    var routineID: UUID
    var routineName: String
}
#endif
