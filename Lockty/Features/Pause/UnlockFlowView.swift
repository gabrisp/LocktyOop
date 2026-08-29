import FamilyControls
import ManagedSettings
import SwiftUI

/// Choosing what to unlock and for how long.
///
/// Two steps in one screen: which app, then how many minutes. The chrome never changes,
/// only the middle, and the chip in the top right goes back to the first step once an
/// app has been chosen.
struct UnlockFlowView: View {
    let tokens: [ApplicationToken]
    /// Preselected when the flow was opened from a specific app's shield.
    var initialToken: ApplicationToken?
    let allowanceRange: ClosedRange<Int>
    let onUnlock: (ApplicationToken?, Int) -> Void
    let onClose: () -> Void

    private enum Step: Hashable {
        case app
        case duration
    }

    @State private var step: Step
    @State private var selectedOptionID: String?
    @State private var minutes: Int

    init(
        tokens: [ApplicationToken],
        initialToken: ApplicationToken? = nil,
        allowanceRange: ClosedRange<Int> = 1...15,
        defaultMinutes: Int = 5,
        onUnlock: @escaping (ApplicationToken?, Int) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.tokens = tokens
        self.initialToken = initialToken
        self.allowanceRange = allowanceRange
        self.onUnlock = onUnlock
        self.onClose = onClose
        // The flow is always the same two steps. An app the flow was opened from is
        // preselected, not skipped -- the picker stays so it can be changed.
        _step = State(initialValue: .app)
        _selectedOptionID = State(initialValue: initialToken.map(Self.optionID(for:)))
        _minutes = State(initialValue: min(max(defaultMinutes, allowanceRange.lowerBound), allowanceRange.upperBound))
    }

    private static let allAppsOptionID = "all"

    private static func optionID(for token: ApplicationToken) -> String {
        AppIdentity.ID(token: token).rawValue
    }

    private var options: [LocktyPickerOption] {
        var result = [
            LocktyPickerOption(
                id: Self.allAppsOptionID,
                systemImage: "iphone",
                title: "Todas las apps"
            )
        ]
        result.append(contentsOf: tokens.map { LocktyPickerOption(id: Self.optionID(for: $0), token: $0) })
        return result
    }

    private var selectedToken: ApplicationToken? {
        guard let selectedOptionID, selectedOptionID != Self.allAppsOptionID else { return nil }
        return tokens.first { Self.optionID(for: $0) == selectedOptionID }
    }

    private var hasChosenApp: Bool {
        selectedOptionID != nil
    }

    var body: some View {
        LocktyFlowScreen(
            title: step == .app ? "Quiero usar..." : "Durante...",
            stepID: step,
            primaryTitle: step == .app ? "Continuar" : "Desbloquear",
            secondaryTitle: "Déjalo",
            isPrimaryEnabled: step == .app ? hasChosenApp : true,
            // Only on the duration step, and only for a real app: it is the way back to
            // the choice that got you here.
            accessoryToken: step == .duration ? selectedToken : nil,
            onAccessory: {
                withAnimation(.smooth(duration: 0.34)) { step = .app }
            },
            onClose: onClose,
            onPrimary: {
                switch step {
                case .app:
                    withAnimation(.smooth(duration: 0.34)) { step = .duration }
                case .duration:
                    onUnlock(selectedToken, minutes)
                }
            },
            onSecondary: onClose
        ) {
            switch step {
            case .app:
                LocktyListPicker(options: options, selection: $selectedOptionID)

            case .duration:
                LocktyMinutesPicker(range: allowanceRange, minutes: $minutes)
            }
        }
    }
}
