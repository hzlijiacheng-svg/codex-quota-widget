import Foundation
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class QuotaStore {
    private let providers: [QuotaProvider] = [CodexProvider(), GatewayProvider()]
    private let history = QuotaHistory(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexQuotaWidget/quota-history.json"))
    private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    private(set) var errors: [ProviderID: String] = [:]
    private(set) var isLoadingTokens = false
    var onChange: (() -> Void)?
    private var isRefreshing = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let result: Result<ProviderSnapshot, Error>
                do {
                    result = .success(try provider.fetch(now: Date()))
                } catch {
                    result = .failure(error)
                }
                DispatchQueue.main.async { [weak self] in
                    defer { group.leave() }
                    guard let self else { return }
                    switch result {
                    case .success(let snapshot):
                        self.snapshots[provider.id] = snapshot
                        self.errors.removeValue(forKey: provider.id)
                        if let window = self.trendWindow(for: snapshot) {
                            self.history.record(provider: provider.id, identity: snapshot.historyIdentity,
                                                window: window, at: snapshot.updatedAt)
                        }
                        if provider.id == .codex { self.refreshCodexTokens() }
                    case .failure(let error):
                        self.errors[provider.id] = error.localizedDescription
                    }
                    self.onChange?()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRefreshing = false
            self.onChange?()
        }
    }

    private func refreshCodexTokens() {
        guard !isLoadingTokens, let requested = snapshots[.codex] else { return }
        let identity = requested.historyIdentity
        let requestedWindow = trendWindow(for: requested)
        isLoadingTokens = true
        onChange?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let now = Date()
            let tokens = CodexTokenLogReader.read(now: now, historyIdentity: identity,
                                                   window: requestedWindow)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingTokens = false
                if let current = self.snapshots[.codex], let tokens {
                    if current.historyIdentity == identity,
                       let requestedWindow, let currentWindow = self.trendWindow(for: current),
                       requestedWindow.resetAt == currentWindow.resetAt,
                       requestedWindow.durationSeconds == currentWindow.durationSeconds {
                        self.history.importPoints(tokens.quotaPoints, provider: .codex,
                                                  identity: identity, window: currentWindow,
                                                  now: current.updatedAt)
                    }
                    self.snapshots[.codex] = ProviderSnapshot(
                        provider: current.provider,
                        planName: current.planName,
                        windows: current.windows,
                        tokenBreakdown: tokens.breakdown,
                        tokenPace: tokens.pace,
                        updatedAt: current.updatedAt,
                        sourceDescription: "Codex 本地 app-server 与会话日志",
                        historyIdentity: current.historyIdentity
                    )
                }
                self.onChange?()
            }
        }
    }

    func trendWindow(for snapshot: ProviderSnapshot) -> QuotaWindow? {
        if snapshot.provider == .codex {
            return snapshot.windows.first { $0.kind == .weekly && $0.resetMode == .fixedCycle }
        }
        if snapshot.provider == .zcode {
            return snapshot.gatewayQuota?.dailyWorkdayWindow(at: snapshot.updatedAt)
        }
        return nil
    }

    func trendPoints(for snapshot: ProviderSnapshot, window: QuotaWindow) -> [QuotaTrendPoint] {
        history.points(provider: snapshot.provider, identity: snapshot.historyIdentity,
                       window: window, at: snapshot.updatedAt)
    }

    var historySaveFailed: Bool { history.saveFailed }
}
