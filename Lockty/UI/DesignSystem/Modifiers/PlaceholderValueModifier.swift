import SwiftUI

extension View {
    /// Marks a single value as standing in for a real one.
    ///
    /// Applied per value, never to a whole screen or card: the layout, the labels and
    /// the structure are all real from the first frame, and only the things that are
    /// still unknown -- a number, an icon, a name, a bar -- are blurred out. Nothing
    /// mounts or unmounts when the data lands; the values simply sharpen.
    func locktyPlaceholder(_ isPlaceholder: Bool) -> some View {
        self
            .redacted(reason: isPlaceholder ? .placeholder : [])
            .blur(radius: isPlaceholder ? 4 : 0)
            .opacity(isPlaceholder ? 0.85 : 1)
            .animation(.smooth(duration: 0.4), value: isPlaceholder)
    }
}
