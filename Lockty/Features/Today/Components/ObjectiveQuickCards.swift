import SwiftUI

/// The objectives you tap, above the card that reads them.
///
/// Half-width cards in a row that settles two at a time: a pair fills the screen, the next
/// pair waits at the edge, and a flick moves exactly one pair rather than drifting to a
/// stop somewhere between four of them. That is what makes this a place for quick taps --
/// the two you looked at are still where you left them.
///
/// The card is the tap: pressing it adds one step, which is a glass of water logged from
/// Today without opening anything. The *name* is the way in -- it opens the objectives
/// page with this one already singled out. The ones Health counts have nothing to add by
/// hand, so those open the page wherever they are pressed.
///
/// It does not crop. The row runs the full width of the screen, out through the gutter the
/// cards above and below keep, with the page's inset applied to its contents instead and
/// clipping switched off -- so what sits at the edge is a card peeking rather than a card
/// cut in half.
struct ObjectiveQuickCards: View {
    @ObservedObject var viewModel: ObjectivesViewModel
    /// Opens the objectives page with one singled out.
    var onOpen: ((Objective) -> Void)?

    /// The page's own gutter, given to the scroll's contents rather than to the scroll, so
    /// a card lines up with the cards above it while the row itself spans the screen.
    private let gutter = LocktySpacing.tabInset
    private let spacing = LocktySpacing.md

    /// Two to a screen, which is what makes the pair the thing that snaps.
    private let perPage = 2

    /// Still to do first. This is a strip for what is left, and the ones already done are
    /// behind it for the tap that was not meant.
    private var objectives: [Objective] {
        let daily = viewModel.dailyObjectives
        return daily.filter { !viewModel.isComplete($0) } + daily.filter { viewModel.isComplete($0) }
    }

    /// The row in twos. Pairing them is what makes a flick land on a pair: the scroll
    /// aligns to whatever it is told the items are, and the item here is two cards wide.
    private var pages: [[Objective]] {
        stride(from: 0, to: objectives.count, by: perPage).map { start in
            Array(objectives[start ..< min(start + perPage, objectives.count)])
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    HStack(spacing: spacing) {
                        ForEach(page) { objective in
                            card(objective)
                        }

                        // An odd last one stays half a screen wide rather than stretching
                        // across the pair's place.
                        if page.count < perPage {
                            ForEach(page.count ..< perPage, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    // One pair is one page: the container minus the gutters it was given.
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
            // Room for the press to grow into. A tight row would clip the card being held.
            .padding(.vertical, 4)
        }
        // The inset lives on the contents, not on the view: this way the row still owns
        // the full width, so the next pair shows through the gutter instead of being cut.
        .safeAreaPadding(.horizontal, gutter)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        // Out through the screen's own inset, since everything on Today is already inside
        // it and this is the one thing meant to reach past it.
        .padding(.horizontal, -gutter)
    }

    /// What a press does. Adding a step by hand to something Health counts would be
    /// writing down a number you did not walk, so those open the page instead.
    private func tap(_ objective: Objective) {
        guard !objective.source.isMeasured else {
            onOpen?(objective)
            return
        }

        // Yes or no is a switch, not a tally: pressing it again takes it back.
        if objective.isYesNo {
            if viewModel.isComplete(objective) {
                viewModel.reset(objective)
            } else {
                viewModel.complete(objective)
            }
        } else {
            viewModel.advance(objective)
        }
    }

    private func card(_ objective: Objective) -> some View {
        let colour = LocktyColors.routine(objective.color)

        return Button {
            tap(objective)
        } label: {
            HStack(spacing: LocktySpacing.sm) {
                ObjectiveRing(
                    symbolName: objective.symbolName,
                    fraction: viewModel.fraction(of: objective),
                    isComplete: viewModel.isComplete(objective),
                    color: objective.color,
                    side: 34,
                    lineWidth: 3
                )

                VStack(alignment: .leading, spacing: 1) {
                    // The label is the way in, not the tap: the card logs, the name opens.
                    Text(objective.name)
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen?(objective) }

                    Text(value(objective))
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(viewModel.isComplete(objective) ? colour : LocktyColors.secondaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .background { surface(objective) }
            .compositingGroup()
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
        .animation(.smooth(duration: 0.45), value: viewModel.fraction(of: objective))
    }

    /// "1,242 of 8,000 steps", with the unit said once: half a card is not wide enough
    /// to say it on both sides of the "of".
    private func value(_ objective: Objective) -> String {
        guard !objective.isYesNo else {
            return viewModel.isComplete(objective) ? "Done" : "Not yet"
        }
        return "\(objective.formatNumber(viewModel.value(of: objective))) of \(objective.format(objective.target))"
    }

    @Environment(\.colorScheme) private var colorScheme

    /// The body the score pills wear, in a rounded rectangle: a bloom behind it, the
    /// ground pressed in at the rim, and the rim itself drawn only as far as it has got.
    private func surface(_ objective: Objective) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let colour = LocktyColors.routine(objective.color)
        let isDark = colorScheme == .dark
        let progress = max(viewModel.fraction(of: objective), 0.02)

        return ZStack {
            // The bloom. Added light in the dark, where the ground is nearly black;
            // laid over in the light, where added light does nothing at all.
            if isDark {
                shape
                    .fill(colour)
                    .blur(radius: 12)
                    .opacity(0.45)
                    .blendMode(.plusLighter)
                    .padding(-2)
            } else {
                ZStack {
                    shape.fill(.white).blur(radius: 10)
                    shape.fill(colour).blur(radius: 14).opacity(0.16)
                }
                .padding(-2)
            }

            // Opaque ground first, tint over it: the other way round, the ground washes
            // the colour out and the card reads as grey.
            shape
                .fill(isDark ? LocktyColors.background : LocktyColors.cardSurface)
                .overlay { shape.fill(colour.opacity(isDark ? 0.14 : 0.10)) }
                .overlay {
                    // The inner shadow that presses the face into the rim.
                    shape
                        .stroke(LocktyColors.background, lineWidth: 10)
                        .blur(radius: 6)
                        .mask { shape }
                }

            shape.stroke(LocktyColors.ink(0.10), lineWidth: 2)

            shape
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .blur(radius: 4)
                .opacity(isDark ? 1 : 0.55)
                .blendMode(isDark ? .plusLighter : .normal)

            shape
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .animation(.smooth(duration: 0.6), value: progress)
    }
}
