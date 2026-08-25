import AppKit
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 58)
    private let popover = NSPopover()
    private let store = QuotaStore()
    private lazy var dashboard = DashboardViewController(store: store)
    private var refreshTimer: Timer?
    private var displayTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let positionKey = "NSStatusItem Preferred Position QuotaStatus"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(230, forKey: positionKey)
        }
        statusItem.autosaveName = "QuotaStatus"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = dashboard
        dashboard.onRefresh = { [weak self] in self?.store.refresh() }
        store.onChange = { [weak self] in
            self?.dashboard.rebuild()
            self?.renderStatus()
        }
        renderStatus()
        store.refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.renderStatus()
            if self.popover.isShown { self.dashboard.rebuild() }
        }
        TouchBarController.shared.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchBarController.shared.restorePresentationMode()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "立即刷新", action: #selector(refresh), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else {
            dashboard.rebuild()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func refresh() { store.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func renderStatus() {
        let snapshot = store.snapshots[.codex]
        statusItem.button?.image = Self.statusImage(snapshot: snapshot,
                                                   hasError: store.errors[.codex] != nil)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = snapshot?.tightestWindow.map {
            "Codex 最紧张额度剩余 \(Int($0.remainingPercent.rounded()))%"
        } ?? "Codex 额度暂无数据"
        TouchBarController.shared.update(snapshot: snapshot)
    }

    private static func statusImage(snapshot: ProviderSnapshot?, hasError: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 56, height: 18), flipped: false) { _ in
            let windowsByKind = Dictionary(uniqueKeysWithValues:
                (snapshot?.windows ?? []).map { ($0.kind, $0) })
            let weekly = windowsByKind[.weekly]
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 7, width: 22, height: 5),
                         xRadius: 2.5, yRadius: 2.5).fill()
            if let weekly {
                NSColor.systemPurple.setFill()
                let width = 22 * CGFloat(weekly.remainingPercent / 100)
                NSBezierPath(roundedRect: NSRect(x: 0, y: 7, width: width, height: 5),
                             xRadius: 2.5, yRadius: 2.5).fill()
            }
            let text = hasError ? "!%" : weekly.map {
                "\(Int($0.remainingPercent.rounded()))%"
            } ?? "--%"
            (text as NSString).draw(in: NSRect(x: 27, y: 2, width: 29, height: 15),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular),
                                 .foregroundColor: hasError ? NSColor.systemRed : NSColor.labelColor])
            return true
        }
        image.isTemplate = false
        return image
    }
}

@main
struct WidgetApplication {
    static func main() {
        if CommandLine.arguments.contains("--print") {
            for provider: QuotaProvider in [CodexProvider()] {
                do {
                    let snapshot = try provider.fetch(now: Date())
                    let windows = snapshot.windows.map {
                        "\($0.kind.rawValue)=\(Int($0.remainingPercent.rounded()))%"
                    }.joined(separator: ",")
                    print("provider=\(provider.id.rawValue) plan=\(snapshot.planName ?? "unknown") \(windows)")
                } catch {
                    print("provider=\(provider.id.rawValue) error=\(error.localizedDescription)")
                }
            }
            exit(EXIT_SUCCESS)
        }

        let app = NSApplication.shared
        let appController = AppController()
        app.delegate = appController
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
