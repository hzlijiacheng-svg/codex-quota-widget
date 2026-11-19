import Foundation

struct CodexQuotaLogEvent {
    let point: QuotaTrendPoint
    let resetAt: Date
    let duration: TimeInterval

    func matches(_ window: QuotaWindow) -> Bool {
        window.resetMode == .fixedCycle && window.resetAt == resetAt &&
            window.durationSeconds == duration
    }
}

enum CodexQuotaLogParser {
    private static let fractionalDate: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()
    private static let standardDate = ISO8601DateFormatter()

    static func accountIdentity(_ metadata: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let account = payload["creator_account_id"] as? String, !account.isEmpty else { return nil }
        return HistoryIdentity.hash(["codex", account])
    }

    static func point(_ data: Data, matching window: QuotaWindow) -> QuotaTrendPoint? {
        guard let event = event(data), event.matches(window) else { return nil }
        return event.point
    }

    static func event(_ data: Data) -> CodexQuotaLogEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["timestamp"] as? String,
              let timestamp = fractionalDate.date(from: text) ?? standardDate.date(from: text),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rate = payload["rate_limits"] as? [String: Any],
              rate["limit_id"] as? String == "codex" else { return nil }
        for key in ["primary", "secondary"] {
            guard let raw = rate[key] as? [String: Any],
                  let minutes = (raw["window_minutes"] as? NSNumber)?.doubleValue, minutes > 1440,
                  let resetSeconds = (raw["resets_at"] as? NSNumber)?.doubleValue,
                  let used = (raw["used_percent"] as? NSNumber)?.doubleValue,
                  minutes.isFinite, resetSeconds.isFinite, used.isFinite, (0...100).contains(used)
            else { continue }
            let reset = Date(timeIntervalSince1970: resetSeconds)
            let duration = minutes * 60
            guard timestamp >= reset.addingTimeInterval(-duration), timestamp < reset else { continue }
            return CodexQuotaLogEvent(point: QuotaTrendPoint(at: timestamp, remainingPercent: 100 - used),
                                      resetAt: reset, duration: duration)
        }
        return nil
    }
}
