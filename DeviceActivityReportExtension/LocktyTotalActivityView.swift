import SwiftUI

struct LocktyTotalActivityView: View {
    let configuration: LocktyActivityReportConfiguration

    var body: some View {
        VStack(spacing: 8) {
            Text("Lockty")
                .font(.headline)
            Text(Duration.seconds(configuration.totalActivityDuration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                .font(.title2.monospacedDigit())
        }
        .padding()
    }
}
