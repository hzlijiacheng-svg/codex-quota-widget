import Foundation
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class QuotaStore {
    private let providers: [QuotaProvider] = [CodexProvider(), GatewayProvider()]
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
