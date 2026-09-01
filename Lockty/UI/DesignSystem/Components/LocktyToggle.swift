import SwiftUI

/// On or off, as a choice you can see both halves of.
///
/// Not a switch. A system `Toggle` brings its own shape, its own tint and its own
/// animation, none of which look like anything else here -- and it states only the side
/// it is on, so "off" is inferred from the absence of green. This shows both words and
/// fills the one that is true, which is the same ON/OFF language the rule cards already
/// use, in the same capsule vocabulary as the rest of the app.
struct LocktySwitch: View {
    @Binding var isOn: Bool
    var isDisabled = false

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            option("On", isSelected: isOn) { isOn = true }
            option("Off", isSelected: !isOn) { isOn = false }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .animation(.snappy(duration: 0.26), value: isOn)
    }

    private func option(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(isSelected ? Color.black : LocktyColors.secondaryText)
                .padding(.horizontal, LocktySpacing.md)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        // One capsule that moves between the two, rather than one fading
                        // in as the other fades out -- the selection slides, which is
                        // what says the two are the same choice.
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .matchedGeometryEffect(id: "lockty.switch", in: selection)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .tappable()
    }
}

/// Kept for callers that only want the control with its own label beside it.
struct LocktyToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            LocktySwitch(isOn: $isOn)
        }
    }
}
