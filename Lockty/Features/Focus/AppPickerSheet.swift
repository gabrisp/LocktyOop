import FamilyControls
import Combine
import OSLog
import SwiftUI

private let appPickerLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "selection")

@MainActor
final class AppPickerViewModel: ObservableObject {
    @Published var selection: FamilyActivitySelection
    private let selectionStore: ScreenTimeSelectionStore
    let scope: ScreenTimeSelectionScope

    init(selectionStore: ScreenTimeSelectionStore, scope: ScreenTimeSelectionScope) {
        self.selectionStore = selectionStore
        self.scope = scope
        selection = (try? selectionStore.load(scope: scope)) ?? FamilyActivitySelection()
        normalizeSelection(previousSelection: FamilyActivitySelection())
    }

    func save() throws {
        normalizeSelection(previousSelection: selection)
        try selectionStore.save(selection, scope: scope)
        appPickerLogger.notice("Picker save scope=\(self.scope.id, privacy: .public) apps=\(self.selection.applicationTokens.count) categories=\(self.selection.categoryTokens.count) domains=\(self.selection.webDomainTokens.count)")
    }

    var navigationTitle: String {
        switch scope {
        case .library:
            "Choose Apps and Websites"
        case .routine:
            "Choose Apps"
        case .pause:
            "Choose App"
        case .appGroup:
            "Choose Apps"
        case .distracting:
            "Distracting Apps"
        }
    }

    var showsExplicitSaveAction: Bool {
        !isSingleApplicationScope
    }

    var helperText: String? {
        switch scope {
        case .pause:
            return "Pauses support exactly one application."
        case .routine:
            return "Domains are configured separately in the routine editor."
        case .appGroup:
            return "Reusable App Groups contain applications only."
        case .distracting:
            return "Distracting is the AutoFocus-managed app group."
        case .library:
            return nil
        }
    }

    var descriptionText: String {
        switch scope {
        case .library:
            return "Choose the apps and websites Lockty can use across routines, pauses and reports."
        case .routine:
            return "Choose the applications this routine will restrict when it starts."
        case .pause:
            return "Choose the one application that will trigger this Pause flow."
        case .appGroup:
            return "Choose the applications this reusable App Group should contain."
        case .distracting:
            return "Choose the applications AutoFocus should treat as Distracting."
        }
    }

    func selectionDidChange(from previousSelection: FamilyActivitySelection) {
        normalizeSelection(previousSelection: previousSelection)
    }

    func persistCurrentSelection() throws {
        try save()
    }

    var selectionRules: LocktyActivitySelectionRules {
        switch scope {
        case .library:
            .library
        case .routine:
            .routine
        case .pause:
            .pause
        case .appGroup, .distracting:
            .appGroup
        }
    }

    var addLabel: String {
        switch scope {
        case .library:
            "Añadir App o sitio web"
        case .routine:
            "Añadir App o categoría"
        case .pause:
            "Añadir App"
        case .appGroup, .distracting:
            "Añadir App"
        }
    }

    func shouldAutoCommitSelection(after previousSelection: FamilyActivitySelection) -> Bool {
        guard isSingleApplicationScope else { return false }
        let newApplications = selection.applicationTokens
        let previousApplications = previousSelection.applicationTokens
        return newApplications.count == 1 && newApplications != previousApplications
    }

    /// FamilyActivityPicker can emit a transient change event that resets the
    /// selection to fully empty during its own open/close lifecycle. Persisting
    /// that event would silently wipe out a real selection the user just made.
    /// Guard against auto-saving exactly that transition; an explicit "Done" tap
    /// still persists whatever the true final state is, including an
    /// intentionally-cleared selection.
    func isSpuriousEmptyReset(from previousSelection: FamilyActivitySelection) -> Bool {
        let becameFullyEmpty = selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
        let wasNonEmpty = !previousSelection.applicationTokens.isEmpty
            || !previousSelection.categoryTokens.isEmpty
            || !previousSelection.webDomainTokens.isEmpty
        return becameFullyEmpty && wasNonEmpty
    }

    private var isSingleApplicationScope: Bool {
        if case .pause = scope {
            return true
        }
        return false
    }

    private func normalizeSelection(previousSelection: FamilyActivitySelection) {
        let appsOnlyScope: Bool
        switch scope {
        case .library:
            appsOnlyScope = false
        case .routine, .pause, .appGroup, .distracting:
            appsOnlyScope = true
        }

        if appsOnlyScope {
            if !selection.categoryTokens.isEmpty {
                selection.categoryTokens = []
            }

            if !selection.webDomainTokens.isEmpty {
                selection.webDomainTokens = []
            }
        }

        guard isSingleApplicationScope else { return }

        if selection.applicationTokens.count > 1 {
            let addedApplication = selection.applicationTokens.subtracting(previousSelection.applicationTokens).first
            let keptApplication = addedApplication
                ?? previousSelection.applicationTokens.first(where: { selection.applicationTokens.contains($0) })
                ?? selection.applicationTokens.first

            selection.applicationTokens = keptApplication.map { [$0] } ?? []
        }
    }
}

struct AppPickerSheet: View {
    @ObservedObject var viewModel: AppPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorOverlay: LocktyFeedbackOverlayState?

    var body: some View {
        LocktyActivitySelectionView(
            title: "Seleccionadas",
            addLabel: viewModel.addLabel,
            selection: $viewModel.selection,
            rules: viewModel.selectionRules,
            suggestions: [],
            externalOverlay: $errorOverlay,
            onClose: { dismiss() },
            onDone: {
                do {
                    try viewModel.persistCurrentSelection()
                    dismiss()
                } catch {
                    withAnimation(.smooth(duration: 0.22)) {
                        errorOverlay = LocktyFeedbackOverlayState(
                            systemImage: "exclamationmark.triangle.fill",
                            title: "No se pudo guardar",
                            subtitle: error.localizedDescription,
                            tint: Color.red.opacity(0.5)
                        )
                    }
                }
            }
        )
        .presentationDetents([.large])
    }
}
