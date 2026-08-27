import SwiftUI

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(LocktyTypography.headline)
                .foregroundStyle(LocktyColors.primaryText)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LocktyTypography.callout)
            }
        }
    }
}
