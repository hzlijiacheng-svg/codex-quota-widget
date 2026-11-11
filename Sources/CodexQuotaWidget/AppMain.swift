import AppKit
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusBarBatteryRenderer.width)
    private let popover = NSPopover()
    private let store = QuotaStore()
    private lazy var dashboard = DashboardViewController(store: store)
    private var refreshTimer: Timer?
    private var displayTimer: Timer?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

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
        stopOutsideClickMonitoring()
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
            startOutsideClickMonitoring()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopoverForOutsideClick() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self else { return event }
            let eventWindow = event.window
            let shouldClose = PopoverDismissalPolicy.shouldClose(
                isGlobalEvent: false,
                isPopoverWindow: eventWindow === self.popover.contentViewController?.view.window,
                isStatusItemWindow: eventWindow === self.statusItem.button?.window
            )
            if shouldClose { self.closePopoverForOutsideClick() }
            return event
        }
    }

    private func closePopoverForOutsideClick() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func stopOutsideClickMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    @objc private func refresh() { store.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func renderStatus() {
        let snapshot = store.snapshots[.codex]
        let gateway = store.snapshots[.zcode]
        statusItem.button?.image = StatusBarBatteryRenderer.image(
            codex: snapshot?.windows.first(where: { $0.kind == .weekly })?.remainingPercent,
            codexHasError: store.errors[.codex] != nil,
            zcode: gateway?.gatewayQuota?.remainingPercent,
            zcodeHasError: store.errors[.zcode] != nil
        )
        statusItem.button?.imagePosition = .imageOnly
        let codexText = store.errors[.codex] != nil ? "Codex 更新失败" :
            snapshot?.windows.first(where: { $0.kind == .weekly }).map {
                "Codex 周额度剩余 \(Int($0.remainingPercent.rounded()))%"
            } ?? "Codex 额度暂无数据"
        let gatewayText = store.errors[.zcode] != nil ? "ZCode 网关更新失败" :
            gateway?.gatewayQuota.map { "ZCode 网关剩余 \(Int($0.remainingPercent.rounded()))%" }
            ?? "ZCode 网关额度暂无数据"
        statusItem.button?.toolTip = "\(codexText) · \(gatewayText)"
        statusItem.button?.setAccessibilityLabel("\(codexText) · \(gatewayText)")
        TouchBarController.shared.update(snapshot: snapshot)
    }
}

@main
struct WidgetApplication {
    static func main() {
        if CommandLine.arguments.contains("--print") || CommandLine.arguments.contains("--print-gateway") {
            let providers: [QuotaProvider] = CommandLine.arguments.contains("--print-gateway")
                ? [GatewayProvider()] : [CodexProvider(), GatewayProvider()]
            for provider in providers {
                do {
                    let snapshot = try provider.fetch(now: Date())
                    let windows = snapshot.windows.map {
                        "\($0.kind.rawValue)=\(Int($0.remainingPercent.rounded()))%"
                    }.joined(separator: ",")
                    let gateway = snapshot.gatewayQuota.map {
                        "period=\($0.period) used=\($0.used) limit=\($0.limit)"
                    } ?? ""
                    print("provider=\(provider.id.rawValue) plan=\(snapshot.planName ?? "unknown") \(windows) \(gateway)")
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
