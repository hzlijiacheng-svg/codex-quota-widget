import AppKit

enum StatusBarBatteryRenderer {
    static let width: CGFloat = 153
    private static let codexTint = statusColor(
        light: DashboardPalette.codex,
        dark: NSColor(srgbRed: 202 / 255, green: 100 / 255, blue: 251 / 255, alpha: 1)
    )
    private static let zcodeTint = statusColor(
        light: DashboardPalette.gateway,
        dark: NSColor(srgbRed: 14 / 255, green: 220 / 255, blue: 230 / 255, alpha: 1)
    )

    static func image(codex: Double?, codexHasError: Bool,
                      zcode: Double?, zcodeHasError: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            draw(initial: "C", remaining: codex, hasError: codexHasError,
                 tint: codexTint, x: 0)
            draw(initial: "Z", remaining: zcode, hasError: zcodeHasError,
                 tint: zcodeTint, x: 78)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func statusColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func draw(initial: String, remaining: Double?, hasError: Bool,
                             tint: NSColor, x: CGFloat) {
        let value = remaining.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        (initial as NSString).draw(in: NSRect(x: x, y: 2, width: 10, height: 15),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                             .foregroundColor: tint])

        let body = NSRect(x: x + 13, y: 4.5, width: 22, height: 9)
        let interior = body.insetBy(dx: 1.6, dy: 1.6)
        if !hasError, let value {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: interior, xRadius: 1.3, yRadius: 1.3).addClip()
            tint.setFill()
            NSRect(x: interior.minX, y: interior.minY,
                   width: interior.width * CGFloat(value / 100), height: interior.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: body.midX - 2, y: body.midY))
            dash.line(to: NSPoint(x: body.midX + 2, y: body.midY))
            dash.lineWidth = 1
            NSColor.labelColor.withAlphaComponent(0.65).setStroke()
            dash.stroke()
        }

        let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: 2.8, yRadius: 2.8)
        outline.lineWidth = 1
        NSColor.labelColor.setStroke()
        outline.stroke()
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.3, y: 7, width: 2, height: 4),
                     xRadius: 0.8, yRadius: 0.8).fill()

        let text = hasError ? "!" : value.map { "\(Int($0.rounded()))%" } ?? "--"
        (text as NSString).draw(in: NSRect(x: x + 41, y: 2, width: 32, height: 15),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                             .foregroundColor: hasError ? DashboardPalette.warning : NSColor.labelColor])
    }
}
