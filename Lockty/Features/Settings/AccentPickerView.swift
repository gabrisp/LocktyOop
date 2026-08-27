import SwiftUI

struct AccentPickerView: View {
    let theme: ThemeManager

    var body: some View {
        NavigationStack {
            List(LocktyAccent.allCases) { accent in
                Button(accent.title) {
                    theme.selectAccent(accent)
                }
            }
            .navigationTitle("Accent")
        }
    }
}
