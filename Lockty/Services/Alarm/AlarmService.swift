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
    /// Sets the alarm that goes off before the routine does.
    ///
    /// Separate from the one above, which fires as a routine actually starts. This one is
    /// booked ahead against the clock, because the whole point is to arrive before
    /// anything has happened -- including before the app has been opened that day.
    func scheduleRoutineStartAlarm(for routine: Routine, firingAt date: Date) async throws
    func cancelRoutineStartAlarm(routineID: UUID) async
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

    /// One alarm per routine, keyed by the routine's own id.
    ///
    /// Deriving the alarm id from the routine means rescheduling replaces rather than
    /// stacks: a routine whose time is edited five times would otherwise carry five
    /// alarms, four of them for times it no longer starts.
    private func alarmID(for routineID: UUID) -> UUID { routineID }

    func scheduleRoutineStartAlarm(for routine: Routine, firingAt date: Date) async throws {
        await cancelRoutineStartAlarm(routineID: routine.id)

        guard routine.startAlarmEnabled, routine.startAlarmLeadMinutes > 0 else { return }
        guard date > Date() else { return }

        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) {
            // Asked for here rather than assumed. The authorization sheet only appears
            // once something needs it, and a routine being saved with an alarm is that
            // moment -- waiting for the user to find the Permissions row first meant the
            // alarm quietly never scheduled.
            //
            // It also needs `NSAlarmKitUsageDescription` in the Info.plist, without which
            // the request is refused before it is shown. It was missing, which is why
            // none of this ever fired.
            if AlarmManager.shared.authorizationState == .notDetermined {
                _ = try? await AlarmManager.shared.requestAuthorization()
            }

            guard AlarmManager.shared.authorizationState == .authorized else {
                print("Routine start alarm not scheduled: AlarmKit is \(AlarmManager.shared.authorizationState), routine id=\(routine.id.uuidString)")
                return
            }

            let lead = routine.startAlarmLeadMinutes
            let name = routine.name.isEmpty ? "Lockty" : routine.name
            let attributes = AlarmAttributes<RoutineStartAlarmMetadata>(
                presentation: AlarmPresentation(
                    alert: .init(title: LocalizedStringResource(stringLiteral: "\(name) starts in \(lead) min"))
                ),
                metadata: RoutineStartAlarmMetadata(routineID: routine.id, routineName: routine.name),
                tintColor: .orange
            )

            let configuration = AlarmManager.AlarmConfiguration<RoutineStartAlarmMetadata>(
                schedule: .fixed(date),
                attributes: attributes,
                sound: .default
            )

            do {
                _ = try await AlarmManager.shared.schedule(
                    id: alarmID(for: routine.id),
                    configuration: configuration
                )
                print("Scheduled routine start alarm routine=\(routine.id.uuidString) at \(date) lead=\(lead)m")
            } catch {
                // Said out loud rather than swallowed. Every earlier failure here was
                // silent, which is why a feature that never worked looked like a feature
                // that worked and did nothing.
                print("Routine start alarm failed for \(routine.id.uuidString): \(error)")
            }
            return
        }
        #endif

        print("Routine start alarms unsupported on this OS for routine id=\(routine.id.uuidString)")
    }

    func cancelRoutineStartAlarm(routineID: UUID) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: alarmID(for: routineID))
        }
        #endif
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
