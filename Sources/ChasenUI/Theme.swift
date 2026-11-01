import ChasenKit
import Observation
import SwiftUI

/// The theme that shows now. A view that reads a color of Theme follows it.
@Observable
public final class Look {
    public static let shared = Look()
    public var theme = ScreenTheme.chasen

    public var noColor: Bool { theme == .monochrome }
}

/// The panel is a panel of macOS: the material of the system, light or dark,
/// with its colors for text. What is Chasen's: the amber of the whisk, for an
/// app that runs, and mono for all that the machine says. Red means a
/// failure, never decoration. The themes of the CLI change those two colors.
public enum Theme {
    public static var accent: Color {
        switch Look.shared.theme {
        case .chasen: Color(hex: 0xf5b83d)
        case .monochrome: .primary
        case .terminal: .accentColor
        }
    }

    public static var error: Color {
        switch Look.shared.theme {
        case .chasen: Color(hex: 0xf43f5e)
        case .monochrome: .primary
        case .terminal: .red
        }
    }

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
