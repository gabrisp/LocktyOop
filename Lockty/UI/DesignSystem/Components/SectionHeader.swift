import SwiftUI

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            // Same eyebrow treatment the rest of the app's section titles use, so the
            // remaining SectionHeader call sites don't look like a different design.
            Text(title.uppercased())
                .locktyEyebrow()

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LocktyTypography.callout)
            }
        }
    }
}
