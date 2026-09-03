import SwiftUI

/// An app's own name, in a colour we choose.
///
/// `Label(token)` is the only thing that carries an app's real, localized name -- the
/// system renders it out of process, and the alternative is a bundle identifier. What it
/// does not do is take styling applied from outside: the label draws itself.
///
/// A `LabelStyle` reaches the part that is ours. The configuration hands back the title
/// as a view, and a view can be told what colour to be, so the name arrives from the
/// system and the colour from us -- which is how "TikTok" can be red on a screen that
/// has decided TikTok is a distraction.
struct LocktyAppNameLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.title
            .foregroundStyle(color)
    }
}

extension LabelStyle where Self == LocktyAppNameLabelStyle {
    /// The app's name alone, in the colour of what it has been called.
    static func locktyAppName(_ color: Color) -> LocktyAppNameLabelStyle {
        LocktyAppNameLabelStyle(color: color)
    }
}
