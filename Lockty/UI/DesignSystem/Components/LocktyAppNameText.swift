import FamilyControls
import ManagedSettings
import SwiftUI

/// An app's name, taken from its Screen Time token.
///
/// The token is the only thing that carries the real, localized name Apple shows for an
/// app. `AppIdentity.displayName` is a guess assembled from the bundle identifier, which
/// is where "Musically" and "Tweetie2" come from instead of TikTok and X — so anywhere a
/// name is shown to the user goes through here, and the derived name is a last resort
/// for the entries that genuinely have no token.
struct LocktyAppNameText: View {
    let app: AppIdentity

    /// Nudges the rendered name down a notch.
    ///
    /// FamilyControls draws `Label(token)` itself, so the ambient font does not reach it
    /// and the label lays out at its own default size. A scale is the only thing that
    /// actually shrinks it.
    var scale: CGFloat = 1

    /// The label's own layout height, before scaling.
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        Group {
            if let token = app.applicationToken {
                Label(token)
                    .labelStyle(.titleOnly)
            } else {
                Text(app.displayName)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newValue in
            naturalHeight = newValue
        }
        .scaleEffect(scale, anchor: .leading)
        // scaleEffect only changes what is drawn, never the layout, so the row kept
        // reserving the label's full unscaled height and the space around the name
        // wouldn't close up however small the spacing was set. Clamping the frame to the
        // scaled height is what actually gives the row back the difference.
        .frame(height: naturalHeight > 0 ? naturalHeight * scale : nil, alignment: .leading)
    }
}
