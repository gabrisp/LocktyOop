import Foundation

/// The only two pushed destinations. Everything else in the app presents as a sheet,
/// including the editors and detail screens opened from inside these two.
enum AppRoute: Hashable {
    case routinesList
    case frictionsList
}
