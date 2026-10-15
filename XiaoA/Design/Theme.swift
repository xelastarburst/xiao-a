import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The 小A palette, taken from the approved mockups.
enum Palette {
    static let cream = Color(hex: 0xFFF1E8)
    static let paper = Color.white
    static let ink = Color(hex: 0x2B211C)
    static let ink2 = Color(hex: 0x6B5148)
    static let line = Color(hex: 0xE7D3C6)
    static let lineSoft = Color(hex: 0xF3E2D7)

    static let persimmon = Color(hex: 0xC24E1C)
    static let persimmonDeep = Color(hex: 0x8F3610)
    static let teal = Color(hex: 0x0E7470)
    static let tealDeep = Color(hex: 0x08524F)
    static let tealInk = Color(hex: 0x0B5F5C)
    static let mint = Color(hex: 0xDDF1E9)
    static let leaf = Color(hex: 0x3FB39A)

    static let red = Color(hex: 0xC4122F)
    static let redDeep = Color(hex: 0x8E0A20)
    static let redWash = Color(hex: 0xFFF3F3)
    static let redSoft = Color(hex: 0xFFE3E3)
    static let redLine = Color(hex: 0xEBC9C9)

    static let peach = Color(hex: 0xFFD9C2)
    static let peachDeep = Color(hex: 0xEDB592)
    static let sky = Color(hex: 0xD3E6FA)
    static let skyDeep = Color(hex: 0xA7C7EA)
    static let skyWash = Color(hex: 0xE8F1FC)
    static let sage = Color(hex: 0xCBEEDF)
    static let sageDeep = Color(hex: 0x9CD5BD)
    static let butter = Color(hex: 0xFFEDA8)
    static let butterDeep = Color(hex: 0xE6CB6E)
    static let lilac = Color(hex: 0xE3DAFA)
    static let lilacDeep = Color(hex: 0xC0B0EC)
    static let lilacInk = Color(hex: 0x463A66)

    static let warnWash = Color(hex: 0xFFF2C2)
    static let warnInk = Color(hex: 0x4A3800)
    static let gold = Color(hex: 0xE9A800)

    static let mascot = Color(hex: 0xFF8F57)
    static let face = Color(hex: 0xFFE6D3)
    static let blush = Color(hex: 0xFF6F6F)
}

extension Font {
    /// Rounded system type. Chinese falls back to PingFang SC automatically.
    /// Sizes follow the user's text-size setting, capped so the big layouts still fit.
    static func xa(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let scaled = UIFontMetrics.default.scaledValue(for: size)
        return .system(size: min(scaled, size * 1.25), weight: weight, design: .rounded)
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
