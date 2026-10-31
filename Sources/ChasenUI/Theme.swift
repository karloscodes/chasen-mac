import SwiftUI

/// The colors and the type of chasenhq.com: a terminal pane. Stone greys,
/// one accent, and mono for everything the machine says. The amber means
/// "live": a change that runs. Red means a failure, never decoration.
public enum Theme {
    public static let background = Color(hex: 0x0c0a09)
    public static let surface = Color(hex: 0x1c1917)
    public static let line = Color(hex: 0x292524)
    public static let text = Color(hex: 0xfafaf9)
    public static let secondary = Color(hex: 0xa8a29e)
    public static let dim = Color(hex: 0x8a837e)
    public static let accent = Color(hex: 0xf5b83d)
    public static let error = Color(hex: 0xf43f5e)

    public static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

extension CGColor {
    static func hex(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}
