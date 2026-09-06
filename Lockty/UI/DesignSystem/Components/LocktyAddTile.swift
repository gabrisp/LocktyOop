import SwiftUI

/// The tile that makes a new one of something.
///
/// One of these, used by every list that has one: routines, rules, frictions. There were
/// two shapes doing this job -- the centred plus-in-a-circle on the Focus rows, and a
/// leading glyph with the words at the bottom on each of the full pages -- so the same
/// action looked like a different control depending on which screen you reached it from.
/// This is the Focus one: a filled circle reads as an action where an outline reads as an
/// empty card waiting to be filled.
struct LocktyAddTile: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(
                radius: RoutineGridMetrics.tileRadius,
                interactive: true,
                height: RoutineGridMetrics.tileHeight
            ) {
                VStack(spacing: LocktySpacing.sm) {
                    Spacer(minLength: 0)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        // The page's own ground, so the glyph is a hole in the circle
                        // rather than a colour laid on it -- and it reads the same way
                        // whichever way round the screen is.
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LocktyColors.primaryText))

                    Text(title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}
