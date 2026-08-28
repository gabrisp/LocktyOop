import SwiftUI

struct TodayDebugCard: View {
    let rawText: String

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text("RAW DEBUG")
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)

                Text(rawText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}
