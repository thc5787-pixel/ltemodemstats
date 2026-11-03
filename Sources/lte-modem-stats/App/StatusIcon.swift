import AppKit
import ModemCore

/// Signal-bar glyph for the menu bar.
enum StatusIcon {
    static func image(bars: Int, active: Bool, tint: MenuBarPresentation.Tint) -> NSImage {
        let color: NSColor? = switch tint {
        case .none: nil
        case .warning: .systemYellow
        case .critical: .systemRed
        }
        let barWidth: CGFloat = 3
        let gap: CGFloat = 1.5
        let size = NSSize(width: barWidth * 4 + gap * 3, height: 12)

        let image = NSImage(size: size, flipped: false) { _ in
            let base = color ?? .black
            for index in 0 ..< 4 {
                let height = size.height * CGFloat(index + 1) / 4
                let rect = NSRect(x: CGFloat(index) * (barWidth + gap), y: 0, width: barWidth, height: height)
                let filled = active && index < bars
                base.withAlphaComponent(filled ? 1 : 0.25).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        // Template images follow the menu bar's light/dark appearance; tinted ones keep their color.
        image.isTemplate = color == nil
        return image
    }
}
