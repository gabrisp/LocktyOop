import FamilyControls
import ManagedSettings
import SwiftUI

/// Choosing what to unlock and for how long.
///
/// The duration is the flow: it opens on "Durante..." with the app already decided. The
/// app picker is not a step you walk through, it is what the chip in the top right
/// opens -- so changing your mind costs one tap and agreeing costs none.
struct UnlockFlowView: View {
    let tokens: [ApplicationToken]
    /// Preselected when the flow was opened from a specific app.
    var initialToken: ApplicationToken?
    let allowanceRange: ClosedRange<Int>
    let onUnlock: (ApplicationToken?, Int) -> Void
    let onClose: () -> Void

    private enum Step: Hashable {
        case app
        case duration
    }

    @State private var step: Step = .duration
    @State private var selectedOptionID: String?
    @State private var minutes: Int?

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
        // Falls back to the first blocked app rather than to nothing: the flow always
        // has an answer for what it is about to unlock.
        let preselected = initialToken ?? tokens.first
        _selectedOptionID = State(initialValue: preselected.map(Self.optionID(for:)))
        _minutes = State(
            initialValue: min(max(defaultMinutes, allowanceRange.lowerBound), allowanceRange.upperBound)
        )
    }

    private static let allAppsOptionID = "all"

    private static func optionID(for token: ApplicationToken) -> String {
        AppIdentity.ID(token: token).rawValue
    }

    private var optionIDs: [String] {
        [Self.allAppsOptionID] + tokens.map(Self.optionID(for:))
    }

    private func token(forOptionID id: String) -> ApplicationToken? {
        guard id != Self.allAppsOptionID else { return nil }
        return tokens.first { Self.optionID(for: $0) == id }
    }

    private var selectedToken: ApplicationToken? {
        selectedOptionID.flatMap(token(forOptionID:))
    }

    var body: some View {
        LocktyFlowScreen(
            title: step == .app ? "Quiero usar..." : "Durante...",
            stepID: step,
            primaryTitle: step == .app ? "Continuar" : "Desbloquear",
            secondaryTitle: "Déjalo",
            // The rest belongs to the moment of unlocking, not to changing your mind
            // about which app it is.
            restSeconds: step == .duration ? 5 : 0,
            // Only on the duration step: on the app step the chip would open the screen
            // that is already showing.
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
                    onUnlock(selectedToken, minutes ?? allowanceRange.lowerBound)
                }
            },
            onSecondary: onClose
        ) {
            switch step {
            case .app:
                LocktyWheelPicker(items: optionIDs, selection: $selectedOptionID) { id in
                    appRow(id)
                }

            case .duration:
                LocktyWheelPicker(items: Array(allowanceRange), selection: $minutes) { value in
                    Text(value == 1 ? "1 minuto" : "\(value) minutos")
                        .font(.system(.title3, design: .default, weight: value == minutes ? .semibold : .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// A row is exactly as tall as the wheel's row: the icon is sized to sit inside it,
    /// not to set it. Sizing the icon first is what made these rows enormous.
    @ViewBuilder
    private func appRow(_ id: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            if let token = token(forOptionID: id) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .id(token)
                    .frame(width: 34, height: 34)

                // The token is the only thing carrying the app's real name.
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            } else {
                Image(systemName: "iphone")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LocktyColors.elevatedBackground)
                    )

                Text("Todas las apps")
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LocktySpacing.lg)
    }
}
