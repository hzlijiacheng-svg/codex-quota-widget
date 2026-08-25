import AppKit
import ObjectiveC.runtime
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()
    private static let trayID = NSTouchBarItem.Identifier("local.codex.quota-widget.touchbar")
    private static let panelID = NSTouchBarItem.Identifier("local.codex.quota-widget.panel")
    private static let touchBarAgentID = "com.apple.touchbar.agent" as CFString
    private static let presentationModeKey = "PresentationModeGlobal" as CFString
    private static let originalModeKey = "TouchBarOriginalPresentationMode"
    private typealias PresenceFunction = @convention(c) (CFString, DarwinBoolean) -> Void
    private let setPresence: PresenceFunction?
    private let strip = TouchBarQuotaView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
    private var trayItem: NSCustomTouchBarItem?
    private var bar: NSTouchBar?

    private override init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY),
           let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") {
            setPresence = unsafeBitCast(symbol, to: PresenceFunction.self)
        } else { setPresence = nil }
        super.init()
    }

    func install() {
        guard setPresence != nil, trayItem == nil else { return }
        let modeChanged = preparePresentationMode()
        if modeChanged { restartControlStrip() }
        for delay in TouchBarPresentationModePolicy.presentationDelays(modeChanged: modeChanged) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                [weak self] in self?.registerAndPresent()
            }
        }
    }

    func restorePresentationMode() {
        guard let originalMode = UserDefaults.standard.string(forKey: Self.originalModeKey)
        else { return }
        CFPreferencesSetAppValue(Self.presentationModeKey,
                                 originalMode as CFString,
                                 Self.touchBarAgentID)
        guard CFPreferencesAppSynchronize(Self.touchBarAgentID) else { return }
        UserDefaults.standard.removeObject(forKey: Self.originalModeKey)
        restartControlStrip()
    }

    private func registerAndPresent() {
        guard trayItem == nil else {
            present()
            return
        }
        let button = NSButton(title: "Q", target: self, action: #selector(present))
        button.font = .systemFont(ofSize: 12, weight: .bold)
        let item = NSCustomTouchBarItem(identifier: Self.trayID); item.view = button
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard NSTouchBarItem.responds(to: selector) else { return }
        NSTouchBarItem.perform(selector, with: item)
        setPresence?(Self.trayID.rawValue as CFString, true)
        trayItem = item
        present()
    }

    private func preparePresentationMode() -> Bool {
        let currentMode = CFPreferencesCopyAppValue(Self.presentationModeKey,
                                                    Self.touchBarAgentID) as? String
            ?? TouchBarPresentationModePolicy.desiredMode
        let storedMode = UserDefaults.standard.string(forKey: Self.originalModeKey)
        if let originalMode = TouchBarPresentationModePolicy.originalModeToStore(
            currentMode: currentMode,
            storedOriginalMode: storedMode
        ), storedMode == nil {
            UserDefaults.standard.set(originalMode, forKey: Self.originalModeKey)
        }
        guard currentMode != TouchBarPresentationModePolicy.desiredMode else { return false }
        CFPreferencesSetAppValue(Self.presentationModeKey,
                                 TouchBarPresentationModePolicy.desiredMode as CFString,
                                 Self.touchBarAgentID)
        return CFPreferencesAppSynchronize(Self.touchBarAgentID)
    }

    private func restartControlStrip() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["ControlStrip"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    func update(snapshot: ProviderSnapshot?) {
        strip.snapshot = snapshot
        strip.needsDisplay = true
    }

    @objc private func present() {
        if bar == nil {
            let newBar = NSTouchBar(); newBar.delegate = self
            newBar.defaultItemIdentifiers = [Self.panelID]; bar = newBar
        }
        guard let bar else { return }
        let knownSelectors = [
            TouchBarPresentationPolicy.placementSelector,
            TouchBarPresentationPolicy.legacySelector
        ]
        let availableSelectors = Set(knownSelectors.filter {
            NSTouchBar.responds(to: NSSelectorFromString($0))
        })
        switch TouchBarPresentationPolicy.select(availableSelectors: availableSelectors) {
        case .modalWithControlStrip:
            presentLegacy(bar)
        case .modalWithPlacement:
            presentWithControlStrip(bar)
        case .unavailable:
            break
        }
    }

    private func presentWithControlStrip(_ bar: NSTouchBar) {
        let selector = NSSelectorFromString(TouchBarPresentationPolicy.placementSelector)
        guard let method = class_getClassMethod(NSTouchBar.self, selector) else { return }
        typealias Function = @convention(c)
            (AnyObject, Selector, NSTouchBar, Int64, NSString?) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBar.self, selector, bar, 0, nil)
    }

    private func presentLegacy(_ bar: NSTouchBar) {
        let selector = NSSelectorFromString(TouchBarPresentationPolicy.legacySelector)
        guard let method = class_getClassMethod(NSTouchBar.self, selector) else { return }
        typealias Function = @convention(c)
            (AnyObject, Selector, NSTouchBar, NSString?) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBar.self, selector, bar, Self.trayID.rawValue as NSString)
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.panelID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier); item.view = strip
        return item
    }
}

private final class TouchBarQuotaView: NSView {
    var snapshot: ProviderSnapshot?
    override var intrinsicContentSize: NSSize { NSSize(width: 600, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let presentation = TouchBarQuotaPresenter.make(snapshot: snapshot, now: Date()) else {
            drawText("Codex 周额度", x: 8, width: 88, size: 11.5,
                     color: .white, weight: .medium)
            drawText("暂无数据", x: 108, width: 80, size: 11,
                     color: .secondaryLabelColor)
            return
        }

        drawText(presentation.title, x: 8, width: 88, size: 11.5,
                 color: .white, weight: .medium)

        let barRect = NSRect(x: 102, y: 11.5, width: 132, height: 6)
        NSColor.darkGray.setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3).fill()
        NSColor.systemPurple.setFill()
        let fillWidth = barRect.width * CGFloat(presentation.remainingPercent / 100)
        NSBezierPath(roundedRect: NSRect(x: barRect.minX, y: barRect.minY,
                                        width: fillWidth, height: barRect.height),
                     xRadius: 3, yRadius: 3).fill()

        drawText(presentation.remaining, x: 246, width: 50, size: 15,
                 color: .systemPurple, weight: .medium)
        drawText(presentation.used, x: 302, width: 58, size: 10,
                 color: .lightGray)
        drawText(presentation.reset, x: 368, width: 104, size: 10.5,
                 color: .white)
        drawText(presentation.pace, x: 482, width: 110, size: 10.5,
                 color: paceColor(presentation.paceTone), weight: .medium)
    }

    private func drawText(_ text: String, x: CGFloat, width: CGFloat, size: CGFloat,
                          color: NSColor, weight: NSFont.Weight = .regular) {
        (text as NSString).draw(in: NSRect(x: x, y: 7, width: width, height: 18),
                               withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color])
    }

    private func paceColor(_ tone: TouchBarPaceTone) -> NSColor {
        switch tone {
        case .fast: return .systemOrange
        case .slow: return .systemTeal
        case .normal: return .systemGreen
        case .unavailable: return .secondaryLabelColor
        }
    }
}
