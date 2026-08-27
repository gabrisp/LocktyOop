import SwiftUI

struct MetricTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.title3, design: .default, weight: .semibold))
            .foregroundStyle(LocktyColors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}
