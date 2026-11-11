import Foundation
import CoreFoundation

enum GatewayQuotaError: LocalizedError {
    case invalidRule
    case invalidUsage

    var errorDescription: String? {
        switch self {
        case .invalidRule: return "网关配额规则未启用或不是 Token 规则"
        case .invalidUsage: return "网关未返回有效的额度和用量"
        }
    }
}

enum GatewayQuotaParser {
    static func parse(rule: [String: Any], usage: [String: Any]) throws -> GatewayQuota {
        guard (rule["ruleStatus"] as? String)?.lowercased() == "enabled",
              (rule["quotaDimension"] as? String)?.lowercased() == "token"
        else { throw GatewayQuotaError.invalidRule }
        guard let limit = integer(usage["totalQuota"]), limit > 0,
              let used = integer(usage["usedAmount"]), used >= 0
        else { throw GatewayQuotaError.invalidUsage }

        let dateString = rule["currentCycleResetAt"] as? String
        let formatter = ISO8601DateFormatter()
        var reset = dateString.flatMap { formatter.date(from: $0) }
        if reset == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = dateString.flatMap { formatter.date(from: $0) }
        }
        return GatewayQuota(
            name: (rule["ruleName"] as? String) ?? "网关额度",
            period: (rule["periodType"] as? String) ?? "unknown",
            alignment: rule["windowAlignment"] as? String,
            used: used, limit: limit,
            input: integer(usage["inputAmount"]),
            output: integer(usage["outputAmount"]),
            cached: integer(usage["cachedAmount"]),
            resetAt: reset
        )
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let n = number.doubleValue
        guard n.isFinite, n >= 0, n < Double(Int64.max), n.rounded(.towardZero) == n
        else { return nil }
        return number.int64Value
    }
}
