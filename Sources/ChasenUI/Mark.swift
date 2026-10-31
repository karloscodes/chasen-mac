import AppKit
import ChasenKit

/// The Chasen mark on a pixel grid: a bamboo whisk. The same cells as
/// src/data/mark.ts of chasenhq.com: seven tines, a binding, and a handle,
/// 13 cells wide and 14 tall. The menu bar, the panel, and the app icon draw
/// from here.
public enum Mark {
    static let tines = [0, 2, 4, 6, 8, 10, 12]
    static let tineRows = 9
    static let solid: [(row: Int, from: Int, to: Int)] = [(9, 2, 10), (10, 3, 9), (11, 5, 7), (12, 5, 7), (13, 5, 7)]
    public static let height = 14

    /// How far the cell of tine i in a row sits from its column, in cells. At
    /// rest the outer tines lean out, like a real whisk. sway, from -1 to 1,
    /// bends the tips to one side: the whisk moves while a change ships.
    static func flare(_ i: Int, _ row: Int, sway: Double) -> Double {
        let up = pow(Double(tineRows - 1 - row) / Double(tineRows - 1), 1.5) // 1 at the tip, 0 at the binding
        return (Double(i) - Double(tines.count - 1) / 2) * 0.4 * up + sway * 0.8 * up
    }

    /// The cells from the top left, in cells. A small mark snaps x to half
    /// cells, so a cell stays sharp on a Retina screen at one point for each
    /// cell. A large one, like the icon, keeps the curve of the tines.
    public static func cells(sway: Double = 0, snap: Bool = true) -> [(x: Double, y: Int)] {
        var cells: [(x: Double, y: Int)] = []
        for (i, column) in tines.enumerated() {
            for row in 0..<tineRows {
                let x = Double(column) + flare(i, row, sway: sway)
                cells.append((snap ? (x * 2).rounded() / 2 : x, row))
            }
        }
        for part in solid {
            for column in part.from...part.to {
                cells.append((Double(column), part.row))
            }
        }
        return cells
    }

    /// The tips reach 2 cells out on each side, so the mark is 17 cells wide
    /// with the room to sway. left is where column 0 goes.
    public static let width = 17
    public static let left = 2.0

    /// Draws the mark in a context whose y goes down.
    public static func draw(in context: CGContext, at origin: CGPoint, cell: CGFloat, gap: CGFloat = 0, color: CGColor, sway: Double = 0, snap: Bool = true) {
        context.setFillColor(color)
        for c in cells(sway: sway, snap: snap) {
            context.fill(CGRect(x: origin.x + (c.x + left) * cell + gap / 2, y: origin.y + CGFloat(c.y) * cell + gap / 2, width: cell - gap, height: cell - gap))
        }
    }

    /// The image of the menu bar, one point for each cell. Calm is dim, a
    /// warning is the full color of the menu bar, and trouble is red. While a
    /// change ships, the whisk sways.
    public static func menuImage(_ level: Mood.Level, sway: Double = 0) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, at: .zero, cell: 1, color: menuColor(level), sway: sway)
            return true
        }
        // A template follows the menu bar, light or dark. Red does not.
        image.isTemplate = level != .trouble
        image.accessibilityDescription = "Chasen"
        return image
    }

    public static func menuColor(_ level: Mood.Level) -> CGColor {
        switch level {
        case .empty, .calm: .hex(0x000000, alpha: 0.5)
        case .warning: .hex(0x000000)
        case .trouble: .hex(0xf43f5e)
        }
    }

    /// The app icon: the amber whisk on the stone of the site, in the shape
    /// and the margins of a macOS icon (824 of 1024, corners of 185).
    public static func appIcon(size: Int) -> CGImage? {
        let s = CGFloat(size) / 1024
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)

        let shape = CGPath(roundedRect: CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
        context.addPath(shape)
        context.setFillColor(.hex(0x0c0a09))
        context.fillPath()
        context.addPath(shape)
        context.setStrokeColor(.hex(0x292524))
        context.setLineWidth(6 * s)
        context.strokePath()

        // At rest the mark spans the columns -1 to 13: 15 cells.
        let cell = (40 * s).rounded()
        let origin = CGPoint(x: (512 * s - 7.5 * cell - (left - 1) * cell).rounded(), y: (512 * s - 7 * cell).rounded())
        draw(in: context, at: origin, cell: cell, gap: max(1, (3 * s).rounded()), color: .hex(0xf5b83d), snap: false)
        return context.makeImage()
    }
}
