import Foundation
import CFNetwork
#if SWIFT_PACKAGE
import QuotaCore
#endif

enum WidgetError: LocalizedError {
    case codexNotFound
    case serviceStopped
    case invalidResponse
    case requestFailed(String)
    case glmCredentialMissing
    case network(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 Codex，请先安装并登录 Codex CLI 或桌面端"
        case .serviceStopped: return "Codex 本地额度服务没有响应"
        case .invalidResponse: return "额度服务返回了无法识别的数据"
        case .requestFailed(let message): return message
        case .glmCredentialMissing: return "未找到 GLM Coding Plan API Key"
        case .network(let message): return message
        }
    }
}

private final class JSONLineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) { self.handle = handle }

    func next() -> Data? {
        while true {
            if let index = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<index])
                buffer.removeSubrange(...index)
                return line
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else { return nil }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(chunk)
        }
    }
}

final class CodexProvider: QuotaProvider {
    let id = ProviderID.codex

    func fetch(now: Date) throws -> ProviderSnapshot {
        let base = ProcessInfo.processInfo.environment
        let settings = (CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]) ?? [:]
        let attempts = SystemProxyEnvironment.candidates(base: base, systemSettings: settings)

        var failures: [String] = []
        for environment in attempts {
            do {
                return try fetch(now: now, environment: environment)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        let detail = failures.last ?? "未知网络错误"
        throw WidgetError.requestFailed("连接 ChatGPT 额度服务失败：\(detail)")
    }

    private func fetch(now: Date, environment: [String: String]) throws -> ProviderSnapshot {
        let process = Process()
        process.executableURL = try Self.executableURL()
        process.arguments = ["app-server"]
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()

        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        try Self.send([
            "method": "initialize", "id": 1,
            "params": [
                "clientInfo": ["name": "codex-quota-widget", "version": "2.0.0"] as [String: Any],
                "capabilities": ["experimentalApi": true]
            ]
        ], to: input.fileHandleForWriting)
        let reader = JSONLineReader(handle: output.fileHandleForReading)
        _ = try Self.response(id: 1, reader: reader)
        try Self.send(["method": "initialized", "params": [String: Any]()],
                      to: input.fileHandleForWriting)
        try Self.send(["method": "account/rateLimits/read", "id": 2],
                      to: input.fileHandleForWriting)
        let response = try Self.response(id: 2, reader: reader)
        return try Self.parse(response: response, now: now)
    }

    private static func parse(response: [String: Any], now: Date) throws -> ProviderSnapshot {
        guard let result = response["result"] as? [String: Any] else {
            throw WidgetError.invalidResponse
        }
        var limit: [String: Any]?
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            limit = byID["codex"] as? [String: Any]
        }
        if limit == nil { limit = result["rateLimits"] as? [String: Any] }
        guard let rateLimit = limit else { throw WidgetError.invalidResponse }

        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let raw = rateLimit[key] as? [String: Any],
                  let durationMinutes = (raw["windowDurationMins"] as? NSNumber)?.doubleValue,
                  let used = (raw["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
            let kind: QuotaWindowKind = durationMinutes <= 24 * 60 ? .session : .weekly
            let reset = (raw["resetsAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue)
            }
            return QuotaWindow(
                kind: kind,
                usedPercent: used,
                resetAt: reset,
                durationSeconds: durationMinutes * 60,
                resetMode: kind == .session ? .rollingRecovery : .fixedCycle
            )
        }.sorted { $0.durationSeconds < $1.durationSeconds }
        guard !windows.isEmpty else { throw WidgetError.invalidResponse }

        return ProviderSnapshot(
            provider: .codex,
            planName: rateLimit["planType"] as? String,
            windows: windows,
            updatedAt: now,
            sourceDescription: "Codex 本地 app-server"
        )
    }

    private static func executableURL() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let path = CodexExecutableLocator.firstExecutable(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: home,
            isExecutable: FileManager.default.isExecutableFile
        ) else {
            throw WidgetError.codexNotFound
        }
        return URL(fileURLWithPath: path)
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func response(id: Int, reader: JSONLineReader) throws -> [String: Any] {
        while let data = reader.next() {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = object["error"] as? [String: Any] {
                throw WidgetError.requestFailed(error["message"] as? String ?? "读取额度失败")
            }
            return object
        }
        throw WidgetError.serviceStopped
    }
}
