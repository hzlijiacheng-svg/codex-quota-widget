import Foundation
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class QuotaStore {
    // GLM/company-gateway support stays compiled but is not enabled until the
    // management API and authentication contract are confirmed by operations.
    private let providers: [QuotaProvider] = [CodexProvider()]
    private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    private(set) var errors: [ProviderID: String] = [:]
    private(set) var isLoadingTokens = false
    var onChange: (() -> Void)?
    private var isRefreshing = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let group = DispatchGroup()
        let lock = NSLock()
        var nextSnapshots: [ProviderID: ProviderSnapshot] = [:]
        var nextErrors: [ProviderID: String] = [:]
        for provider in providers {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                do {
                    let snapshot = try provider.fetch(now: Date())
                    lock.lock(); nextSnapshots[provider.id] = snapshot; lock.unlock()
                } catch {
                    lock.lock(); nextErrors[provider.id] = error.localizedDescription; lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRefreshing = false
            self.snapshots.merge(nextSnapshots) { _, new in new }
            self.errors = nextErrors
            self.onChange?()
            self.refreshCodexTokens()
        }
    }

    private func refreshCodexTokens() {
        guard !isLoadingTokens, snapshots[.codex] != nil else { return }
        isLoadingTokens = true
        onChange?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let now = Date()
            let tokens = CodexTokenLogReader.read(now: now)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingTokens = false
                if let current = self.snapshots[.codex], let tokens {
                    self.snapshots[.codex] = ProviderSnapshot(
                        provider: current.provider,
                        planName: current.planName,
                        windows: current.windows,
                        tokenBreakdown: tokens.breakdown,
                        tokenPace: tokens.pace,
                        updatedAt: current.updatedAt,
                        sourceDescription: "Codex 本地 app-server 与会话日志"
                    )
                }
                self.onChange?()
            }
        }
    }
}
