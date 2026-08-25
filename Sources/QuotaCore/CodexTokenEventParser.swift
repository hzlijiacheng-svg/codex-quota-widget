import Foundation

public enum CodexTokenParseError: Error {
    case invalidEvent
}

public struct CodexTokenEvent: Equatable {
    public let timestamp: Date
    public let breakdown: TokenBreakdown
    public let total: Int64

    public init(timestamp: Date, breakdown: TokenBreakdown, total: Int64) {
        self.timestamp = timestamp
        self.breakdown = breakdown
        self.total = total
    }
}

public enum CodexTokenEventParser {
    public static func parse(data: Data) throws -> CodexTokenEvent {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = timestamp(timestampText),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any] else {
            throw CodexTokenParseError.invalidEvent
        }

        let inputAll = max(0, int64(usage["input_tokens"]))
        let cached = min(inputAll, max(0, int64(usage["cached_input_tokens"])))
        let output = max(0, int64(usage["output_tokens"]))
        let breakdown = TokenBreakdown(
            input: inputAll - cached,
            cachedInput: cached,
            output: output
        )
        let reportedTotal = max(0, int64(usage["total_tokens"]))
        return CodexTokenEvent(
            timestamp: timestamp,
            breakdown: breakdown,
            total: reportedTotal > 0 ? reportedTotal : breakdown.total
        )
    }

    private static func timestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func int64(_ value: Any?) -> Int64 {
        (value as? NSNumber)?.int64Value ?? Int64(value as? String ?? "") ?? 0
    }
}

public struct CodexTokenSummary: Equatable {
    public let breakdown: TokenBreakdown
    public let pace: TokenPace?

    public init(breakdown: TokenBreakdown, pace: TokenPace?) {
        self.breakdown = breakdown
        self.pace = pace
    }
}

public enum CodexTokenAggregator {
    public static func summarize(
        events: [CodexTokenEvent],
        now: Date,
        calendar: Calendar = .current
    ) -> CodexTokenSummary? {
        guard !events.isEmpty else { return nil }
        let startToday = calendar.startOfDay(for: now)
        let secondsToday = now.timeIntervalSince(startToday)
        var today = TokenBreakdown()
        var historical = [Int: Int64]()

        for event in events {
            let dayStart = calendar.startOfDay(for: event.timestamp)
            let dayDistance = calendar.dateComponents(
                [.day], from: dayStart, to: startToday
            ).day ?? -1
            guard dayDistance >= 0 && dayDistance <= 7 else { continue }
            if dayDistance == 0 {
                today = TokenBreakdown(
                    input: today.input + event.breakdown.input,
                    cachedInput: today.cachedInput + event.breakdown.cachedInput,
                    output: today.output + event.breakdown.output
                )
            } else if event.timestamp.timeIntervalSince(dayStart) <= secondsToday {
                historical[dayDistance, default: 0] += event.total
            }
        }

        return CodexTokenSummary(
            breakdown: today,
            pace: TokenPaceCalculator.calculate(
                todayTokens: today.total,
                comparisonTokens: (1...7).compactMap { historical[$0] }
            )
        )
    }
}
