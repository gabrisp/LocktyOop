import Foundation

enum LocktyDurationFormatter {
    static func abbreviated(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int((duration / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    static func percentOfDay(_ duration: TimeInterval) -> Int {
        Int(((duration / 86_400) * 100).rounded())
    }
}
