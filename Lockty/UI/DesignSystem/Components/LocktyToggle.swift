import SwiftUI

struct LocktyToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(LocktyTypography.body)
            .tint(LocktyColors.primaryText)
    }
}
