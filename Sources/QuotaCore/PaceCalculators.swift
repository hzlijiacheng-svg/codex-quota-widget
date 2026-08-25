import Foundation

public enum TokenPaceCalculator {
    public static func calculate(
        todayTokens: Int64,
        comparisonTokens: [Int64],
        minimumSampleDays: Int = 3
    ) -> TokenPace? {
        let samples = comparisonTokens.filter { $0 >= 0 }
        guard samples.count >= minimumSampleDays else { return nil }
        let baseline = Int64((Double(samples.reduce(0, +)) / Double(samples.count)).rounded())
        guard baseline > 0 else { return nil }
        let delta = todayTokens - baseline
        return TokenPace(
            todayTokens: todayTokens,
            baselineTokens: baseline,
            deltaTokens: delta,
            deltaPercent: Double(delta) / Double(baseline) * 100,
            sampleDays: samples.count
        )
    }
}

public enum QuotaPaceCalculator {
    public static func calculate(window: QuotaWindow, now: Date) -> QuotaPace? {
        guard window.resetMode == .fixedCycle,
              window.durationSeconds > 0,
              let resetAt = window.resetAt else { return nil }
        let remaining = min(window.durationSeconds, max(0, resetAt.timeIntervalSince(now)))
        let elapsed = (1 - remaining / window.durationSeconds) * 100
        return QuotaPace(
            elapsedPercent: elapsed,
            usedPercent: window.usedPercent,
            deltaPercentagePoints: window.usedPercent - elapsed
        )
    }

    public static func calculateWorkday(
        window: QuotaWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> QuotaPace? {
        guard window.resetMode == .fixedCycle,
              window.durationSeconds > 0,
              let resetAt = window.resetAt else { return nil }
        let startAt = resetAt.addingTimeInterval(-window.durationSeconds)
        let clampedNow = min(resetAt, max(startAt, now))
        let totalWorkSeconds = workSeconds(from: startAt, to: resetAt, calendar: calendar)
        guard totalWorkSeconds > 0 else { return nil }
        let elapsedWorkSeconds = workSeconds(from: startAt, to: clampedNow, calendar: calendar)
        let elapsed = min(100, max(0, elapsedWorkSeconds / totalWorkSeconds * 100))
        return QuotaPace(
            elapsedPercent: elapsed,
            usedPercent: window.usedPercent,
            deltaPercentagePoints: window.usedPercent - elapsed
        )
    }

    private static func workSeconds(from startAt: Date,
                                    to endAt: Date,
                                    calendar: Calendar) -> TimeInterval {
        guard endAt > startAt else { return 0 }
        var cursor = startAt
        var total: TimeInterval = 0
        while cursor < endAt {
            let startOfDay = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            else { break }
            let segmentEnd = min(nextDay, endAt)
            if !calendar.isDateInWeekend(cursor) {
                total += segmentEnd.timeIntervalSince(cursor)
            }
            cursor = segmentEnd
        }
        return total
    }
}
