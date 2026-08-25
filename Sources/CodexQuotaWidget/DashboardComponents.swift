import AppKit

final class LevelBar: NSView {
    var percent: Double = 0 { didSet { needsDisplay = true } }
    var tint: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 112, height: 10) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        NSColor.white.withAlphaComponent(0.10).setFill(); track.fill()
        let width = bounds.width * CGFloat(min(100, max(0, percent))) / 100
        guard width > 0 else { return }
        tint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
                     xRadius: 5, yRadius: 5).fill()
    }
}

final class RingProgressView: NSView {
    let title: String
    var percent: Double { didSet { needsDisplay = true; updateAccessibility() } }
    var tint: NSColor { didSet { needsDisplay = true } }

    init(title: String, percent: Double, tint: NSColor) {
        self.title = title
        self.percent = percent
        self.tint = tint
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        updateAccessibility()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 104, height: 104) }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 8
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius,
                        startAngle: 90, endAngle: -270, clockwise: true)
        track.lineWidth = 9
        track.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.10).setStroke()
        track.stroke()

        let clamped = min(100, max(0, percent))
        if clamped > 0 {
            let progress = NSBezierPath()
            progress.appendArc(withCenter: center, radius: radius,
                               startAngle: 90,
                               endAngle: 90 - CGFloat(clamped / 100 * 360),
                               clockwise: true)
            progress.lineWidth = 9
            progress.lineCapStyle = .round
            tint.setStroke()
            progress.stroke()
        }

        let value = "\(Int(clamped.rounded()))%" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(at: NSPoint(x: center.x - size.width / 2,
                               y: center.y - size.height / 2),
                   withAttributes: attributes)
    }

    private func updateAccessibility() {
        setAccessibilityLabel(title)
        setAccessibilityValue("\(Int(percent.rounded()))%")
    }
}

final class RingMetricView: NSStackView {
    init(title: String, percent: Double, tint: NSColor) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .centerX
        spacing = 5
        let ring = RingProgressView(title: title, percent: percent, tint: tint)
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.textColor = .secondaryLabelColor
        addArrangedSubview(ring)
        addArrangedSubview(caption)
        setAccessibilityElement(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

final class InsightBanner: NSView {
    init(text: String, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = 8

        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        field.textColor = tint
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 38),
            widthAnchor.constraint(equalToConstant: 392)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
