import SwiftUI

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        if sanitized.count == 6 {
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        } else {
            red = 255
            green = 255
            blue = 255
        }

        self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}
