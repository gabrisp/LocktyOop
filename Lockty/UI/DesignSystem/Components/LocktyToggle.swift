import SwiftUI

/// On or off, as a choice you can see both halves of.
///
/// Not a switch. A system `Toggle` brings its own shape, its own tint and its own
/// animation, none of which look like anything else here -- and it states only the side
/// it is on, so "off" is inferred from the absence of green. This shows both words and
/// fills the one that is true, which is the same ON/OFF language the rule cards already
/// use, in the same capsule vocabulary as the rest of the app.
///
/// The pill is dragged, not just tapped. It used to be a `matchedGeometryEffect` shared
/// between two buttons, which can only ever jump from one to the other: you pressed a
/// side and it arrived. A control shaped like something that slides should slide, and
/// under your finger rather than after it -- so the pill carries its own offset, the
/// drag writes straight into it, and letting go snaps to whichever side it is nearer.
struct LocktySwitch: View {
    @Binding var isOn: Bool
    var isDisabled = false

    /// Both words, measured together so the two halves are the same width whatever they
    /// say. "Off" is wider than "On", and sizing each half to its own word put the pill
    /// on a track with a step in the middle of it.
    @State private var optionSize: CGSize = .zero
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false

    private let inset: CGFloat = 3

    /// Where the pill sits for the value, with no finger on it.
    private var restingOffset: CGFloat { isOn ? 0 : optionSize.width }

    /// Where it is right now, kept on the track however far the finger goes past the end.
    private var pillOffset: CGFloat {
        min(max(restingOffset + dragTranslation, 0), optionSize.width)
    }

    /// What the switch would be if the finger let go now: whichever half the pill is more
    /// than halfway into.
    private var draggedValue: Bool {
        pillOffset < optionSize.width / 2
    }

    /// What the words show. While a drag is in progress this is where the pill is, not
    /// where the value still is, so the labels change as it crosses the middle instead of
    /// all at once on release.
    private var displayedValue: Bool {
        isDragging ? draggedValue : isOn
    }

    var body: some View {
        ZStack(alignment: .leading) {
            pill

            HStack(spacing: 0) {
                label("On", isSelected: displayedValue)
                label("Off", isSelected: !displayedValue)
            }
        }
        .padding(inset)
        // The track is glass as well, not a flat wash. The pill slides over it and the
        // whole control is one thing being pressed, so a solid channel under a glass pill
        // read as two materials that happened to be the same shape.
        .safeGlass(radius: 999, interactive: true)
        .contentShape(Capsule(style: .continuous))
        .gesture(dragGesture)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .sensoryFeedback(.selection, trigger: displayedValue)
        .background(alignment: .topLeading) { stencil }
    }

    /// Tinted glass rather than a flat fill: it is the one moving part of the control, and
    /// what is underneath showing through it is what makes it read as a thing on a track
    /// rather than a rectangle being redrawn in two places.
    private var pill: some View {
        Color.clear
            .frame(width: optionSize.width, height: optionSize.height)
            .safeGlass(radius: 999, interactive: true, tint: LocktyColors.primaryText)
            .offset(x: pillOffset)
            // No animation while the finger is down. An animated offset lags behind the
            // touch by however long the animation takes, which is exactly the thing this
            // was rewritten to stop doing.
            .animation(isDragging ? nil : .snappy(duration: 0.3), value: pillOffset)
    }

    private var dragGesture: some Gesture {
        // Zero minimum distance, so this handles the taps as well. Two gestures -- a
        // button per half and a drag over both -- would have to agree on which of them
        // owned a press, and a press that begins as a tap and turns into a drag belongs
        // to neither until it is over.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isDisabled else { return }
                isDragging = true
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard !isDisabled else { return }
                let wasDragged = abs(value.translation.width) > 2
                // A tap has no travel to read, so it goes by where the finger landed:
                // the left half means On, the right half Off, which is what the words
                // under it say.
                let next = wasDragged
                    ? draggedValue
                    : value.startLocation.x < optionSize.width + inset

                isDragging = false
                dragTranslation = 0
                withAnimation(.snappy(duration: 0.3)) { isOn = next }
            }
    }

    private func label(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(.footnote, design: .default, weight: .semibold))
            .foregroundStyle(isSelected ? LocktyColors.onPrimary : LocktyColors.secondaryText)
            .frame(width: optionSize.width, height: optionSize.height)
            .animation(.snappy(duration: 0.22), value: isSelected)
    }

    /// Both words laid over each other, hidden, so the pair takes the width of the wider
    /// and every part of the control can be sized from one number.
    private var stencil: some View {
        ZStack {
            Text("On")
            Text("Off")
        }
        .font(.system(.footnote, design: .default, weight: .semibold))
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, 6)
        .hidden()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            optionSize = newValue
        }
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
