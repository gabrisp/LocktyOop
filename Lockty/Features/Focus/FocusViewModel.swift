import Foundation
import Observation

@MainActor
@Observable
final class FocusViewModel {
    var selectedSection: FocusSection = .routines
}
