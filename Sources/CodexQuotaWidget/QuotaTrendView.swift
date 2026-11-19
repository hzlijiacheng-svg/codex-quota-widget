import AppKit

final class QuotaTrendView: NSView {
    private let readings: [QuotaTrendPoint]
    private let vertices: [QuotaTrendPoint]
    private let baseline: [QuotaTrendPoint]
    private let bands: [QuotaBudgetBand]
    private let gapLimit: CGFloat
    private let tint: NSColor
    private var tracking: NSTrackingArea?
    private var selected: QuotaTrendPoint? {
        didSet {
            guard oldValue != selected else { return }
            updateAccessibilityValue()
            needsDisplay = true
        }
    }

    init(actual: [QuotaTrendPoint], baseline: [QuotaTrendPoint], tint: NSColor) {
        readings = actual
        vertices = QuotaTrendCalculator.compactActualPoints(actual)
        self.baseline = baseline
        bands = QuotaTrendCalculator.budgetBands(actual: vertices, baseline: baseline)
        let extent = bands.reduce(0.0) { max($0, abs($1.start.difference), abs($1.end.difference)) }
        gapLimit = max(10, ceil(extent / 10) * 10)
        self.tint = tint
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(baseline.isEmpty ? "实际走势" : "实际走势与余量预算差值")
        setAccessibilityHelp("移动指针查看最近的实际记录")
        updateAccessibilityValue()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: baseline.isEmpty ? 114 : 192)
    }

    private var actualPlot: NSRect {
        NSRect(x: 31, y: 7, width: max(1, bounds.width - 37), height: 82)
    }
    private var gapPlot: NSRect {
        NSRect(x: actualPlot.minX, y: 123, width: actualPlot.width, height: 47)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited,
                                                        .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        if let window, window.isVisible {
            selectReading(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        selectReading(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { selected = nil }

    private func selectReading(at point: NSPoint) {
        let region = baseline.isEmpty ? actualPlot : actualPlot.union(gapPlot)
        guard region.insetBy(dx: -3, dy: 0).contains(point),
              visibleRect.contains(point), let first = readings.first, let last = readings.last else {
            selected = nil
            return
        }
        let portion = (point.x - actualPlot.minX) / actualPlot.width
        let date = first.at.addingTimeInterval(last.at.timeIntervalSince(first.at) * portion)
        selected = QuotaTrendCalculator.nearestReading(to: date, in: readings)
    }

    private func x(_ date: Date) -> CGFloat {
        guard let first = readings.first, let last = readings.last, last.at > first.at else { return actualPlot.minX }
        return actualPlot.minX + actualPlot.width * date.timeIntervalSince(first.at) / last.at.timeIntervalSince(first.at)
    }

    private func actualY(_ percent: Double) -> CGFloat { actualPlot.maxY - actualPlot.height * percent / 100 }
    private func gapY(_ gap: Double) -> CGFloat { gapPlot.midY - gapPlot.height * gap / (2 * gapLimit) }

    private func text(_ string: String, size: CGFloat = 10, weight: NSFont.Weight = .regular,
                      color: NSColor = .secondaryLabelColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight), .foregroundColor: color
        ])
    }

    private func line(_ start: NSPoint, _ end: NSPoint, color: NSColor, width: CGFloat = 0.5) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func point(_ center: NSPoint, color: NSColor, ring: Bool = false) {
        let radius: CGFloat = ring ? 3.4 : 2.6
        let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                              width: 2 * radius, height: 2 * radius))
        color.setFill()
        path.fill()
        if ring {
            NSColor.labelColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let first = vertices.first, let last = vertices.last, first.at < last.at else { return }
        for percent in [100, 50, 0] {
            let y = actualY(Double(percent))
            line(NSPoint(x: actualPlot.minX, y: y), NSPoint(x: actualPlot.maxX, y: y),
                 color: NSColor.secondaryLabelColor.withAlphaComponent(0.32))
            drawScaleLabel("\(percent)%", y: y)
        }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x(first.at), y: actualY(first.remainingPercent)))
        for p in vertices.dropFirst() {
            path.line(to: NSPoint(x: x(p.at), y: actualY(p.remainingPercent)))
        }
        path.lineWidth = 2
        path.lineJoinStyle = .round
        tint.setStroke()
        path.stroke()
        point(NSPoint(x: x(last.at), y: actualY(last.remainingPercent)), color: tint)

        if !baseline.isEmpty { drawDifference(latest: last) }
        drawDates(first: first.at, last: last.at)
        if let selected { drawCursor(selected) }
    }

    private func drawScaleLabel(_ caption: String, y: CGFloat) {
        let label = text(caption, size: 9)
        label.draw(at: NSPoint(x: actualPlot.minX - 5 - label.size().width, y: y - label.size().height / 2))
    }

    private func drawDifference(latest: QuotaTrendPoint) {
        text("余量与预算差值", size: 13, weight: .semibold, color: .labelColor).draw(at: NSPoint(x: 0, y: 99))
        if let budget = QuotaTrendCalculator.remainingPercent(at: latest.at, along: baseline) {
            let gap = displayGap(latest, budget)
            let header = text(gap == 0 ? "与预算持平" : String(format: "%+d 个百分点", gap),
                              size: 12, weight: .medium, color: gapColor(gap))
            header.draw(at: NSPoint(x: bounds.maxX - header.size().width, y: 100))
        }

        let surplus = NSBezierPath()
        let deficit = NSBezierPath()
        for band in bands {
            let path = band.isSurplus ? surplus : deficit
            let left = x(band.start.at), right = x(band.end.at)
            path.move(to: NSPoint(x: left, y: gapPlot.midY))
            path.line(to: NSPoint(x: left, y: gapY(band.start.difference)))
            path.line(to: NSPoint(x: right, y: gapY(band.end.difference)))
            path.line(to: NSPoint(x: right, y: gapPlot.midY))
            path.close()
        }
        DashboardPalette.budgetSurplus.withAlphaComponent(0.8).setFill()
        surplus.fill()
        DashboardPalette.warning.withAlphaComponent(0.8).setFill()
        deficit.fill()
        line(NSPoint(x: gapPlot.minX, y: gapPlot.midY), NSPoint(x: gapPlot.maxX, y: gapPlot.midY),
             color: .secondaryLabelColor)
        drawScaleLabel("+\(Int(gapLimit))", y: gapPlot.minY)
        drawScaleLabel("0", y: gapPlot.midY)
        drawScaleLabel("−\(Int(gapLimit))", y: gapPlot.maxY)
    }

    private func drawDates(first: Date, last: Date) {
        let calendar = Calendar.current
        let sameDay = calendar.isDate(first, inSameDayAs: last)
        let format = DateFormatter()
        format.dateFormat = sameDay ? "HH:mm" : "M/d"
        var dates = [first]
        if !sameDay {
            var cursor = first
            while let next = calendar.dateInterval(of: .day, for: cursor)?.end, next > cursor, next < last {
                if !calendar.isDate(next, inSameDayAs: last) { dates.append(next) }
                cursor = next
            }
        } else if last.timeIntervalSince(first) >= 3600 {
            dates.append(first.addingTimeInterval(last.timeIntervalSince(first) / 2))
        }
        dates.append(last)
        let y = (baseline.isEmpty ? actualPlot.maxY : gapPlot.maxY) + 7
        let rightLabel = text(format.string(from: last))
        var previousRight = -CGFloat.infinity
        for date in dates {
            let caption = text(format.string(from: date))
            let width = caption.size().width
            let left = min(bounds.maxX - width, max(actualPlot.minX - width / 2, x(date) - width / 2))
            guard date == last || (left > previousRight + 5 && left + width + 5 < bounds.maxX - rightLabel.size().width)
                else { continue }
            caption.draw(at: NSPoint(x: left, y: y))
            previousRight = left + width
        }
    }

    private func displayGap(_ reading: QuotaTrendPoint, _ budget: Double) -> Int {
        Int(reading.remainingPercent.rounded()) - Int(budget.rounded())
    }

    private func gapColor(_ value: Int) -> NSColor {
        if value == 0 { return .secondaryLabelColor }
        return value > 0 ? DashboardPalette.budgetSurplus : DashboardPalette.warning
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private func cursorLines(_ reading: QuotaTrendPoint, budget: Double?) -> [NSAttributedString] {
        var result = [text(Self.timestamp.string(from: reading.at), size: 10)]
        var values = "实际 \(Int(reading.remainingPercent.rounded()))%"
        if let budget { values += "   预算 \(Int(budget.rounded()))%" }
        result.append(text(values, size: 12, weight: .medium, color: .labelColor))
        if let budget {
            let gap = displayGap(reading, budget)
            let difference = gap == 0 ? "与预算持平" :
                "\(gap > 0 ? "高于" : "低于")预算 \(abs(gap)) 个百分点"
            result.append(text(difference, size: 11, weight: .medium, color: gapColor(gap)))
        }
        return result
    }

    private func updateAccessibilityValue() {
        guard let reading = selected ?? readings.last else { return }
        let budget = QuotaTrendCalculator.remainingPercent(at: reading.at, along: baseline)
        setAccessibilityValue(cursorLines(reading, budget: budget).map(\.string).joined(separator: "，"))
    }

    private func drawCursor(_ reading: QuotaTrendPoint) {
        let cursorX = x(reading.at)
        let budget = QuotaTrendCalculator.remainingPercent(at: reading.at, along: baseline)
        for plot in (budget == nil ? [actualPlot] : [actualPlot, gapPlot]) {
            line(NSPoint(x: cursorX, y: plot.minY), NSPoint(x: cursorX, y: plot.maxY),
                 color: NSColor.labelColor.withAlphaComponent(0.62), width: 0.8)
        }
        let y = actualY(reading.remainingPercent)
        point(NSPoint(x: cursorX, y: y), color: tint, ring: true)
        if let budget {
            point(NSPoint(x: cursorX, y: gapY(reading.remainingPercent - budget)),
                  color: gapColor(displayGap(reading, budget)), ring: true)
        }
        let lines = cursorLines(reading, budget: budget)
        let width = ceil(lines.map { $0.size().width }.max() ?? 0) + 16
        let height = ceil(lines.reduce(CGFloat(10)) { $0 + $1.size().height + 1 })
        let left = cursorX + 9 + width <= bounds.maxX ? cursorX + 9 : cursorX - 9 - width
        let box = NSRect(x: max(0, left), y: max(0, min(actualPlot.maxY - height, y - height / 2)),
                         width: width, height: height)
        let bubble = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        NSColor.windowBackgroundColor.setFill()
        bubble.fill()
        NSColor.separatorColor.setStroke()
        bubble.lineWidth = 1
        bubble.stroke()
        var top = box.minY + 5
        for label in lines {
            label.draw(at: NSPoint(x: box.minX + 8, y: top))
            top += label.size().height + 1
        }
    }
}
