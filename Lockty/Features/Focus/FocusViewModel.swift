import Foundation
import Combine

@MainActor
final class FocusViewModel: ObservableObject {
    @Published var selectedSection: FocusSection = .routines
}
