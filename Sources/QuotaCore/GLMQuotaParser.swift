import Foundation

public enum ProviderParseError: LocalizedError {
    case invalidResponse
    case providerError(String)
    case noQuotaWindows

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "额度服务返回了无法识别的数据"
        case .providerError(let message): return message
        case .noQuotaWindows: return "额度服务没有返回 5 小时或每周窗口"
        }
    }
}

public enum GLMQuotaParser {
    public static func parse(data: Data, now: Date) throws -> ProviderSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderParseError.invalidResponse
        }
        if let success = root["success"] as? Bool, !success {
            throw ProviderParseError.providerError(root["msg"] as? String ?? "GLM 额度查询失败")
        }
        guard let payload = root["data"] as? [String: Any],
              let rawLimits = payload["limits"] as? [[String: Any]] else {
            throw ProviderParseError.invalidResponse
        }

        let windows = rawLimits.compactMap(parseWindow).sorted {
            $0.durationSeconds < $1.durationSeconds
        }
        guard !windows.isEmpty else { throw ProviderParseError.noQuotaWindows }
        return ProviderSnapshot(
            provider: .glm,
            planName: (payload["level"] as? String)?.uppercased(),
            windows: windows,
            updatedAt: now,
            sourceDescription: "GLM Coding Plan 账户接口"
        )
    }

    private static func parseWindow(_ raw: [String: Any]) -> QuotaWindow? {
        guard let type = raw["type"] as? String,
              type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT",
              let unit = number(raw["unit"]),
              let used = number(raw["percentage"]) else { return nil }

        let kind: QuotaWindowKind
        let duration: TimeInterval
        let resetMode: ResetMode
        switch Int(unit) {
        case 3:
            kind = .session
            duration = 5 * 60 * 60
            resetMode = .rollingRecovery
        case 6:
            kind = .weekly
            duration = 7 * 24 * 60 * 60
            resetMode = .fixedCycle
        default:
            return nil
        }

        let resetAt = number(raw["nextResetTime"]).map {
            Date(timeIntervalSince1970: $0 > 1_000_000_000_000 ? $0 / 1000 : $0)
        }
        return QuotaWindow(
            kind: kind,
            usedPercent: used,
            resetAt: resetAt,
            durationSeconds: duration,
            resetMode: resetMode
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
