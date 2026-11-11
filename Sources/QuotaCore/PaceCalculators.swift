import Foundation

enum WorkdaySpeed: Equatable {
    case slow, balanced, fast

    static func classify(_ ratio: Double) -> WorkdaySpeed {
        let displayed = (ratio * 100).rounded() / 100
        if displayed < 0.8 { return .slow }
        if displayed > 1.2 { return .fast }
        return .balanced
    }

    var title: String {
        switch self {
        case .slow: return "偏慢"
        case .balanced: return "平稳"
        case .fast: return "偏快"
        }
    }
}

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
        guard let budget = workdayBudget(window: window, now: now, calendar: calendar)
        else { return nil }
        return QuotaPace(
            elapsedPercent: budget.elapsedPercent,
            usedPercent: window.usedPercent,
            deltaPercentagePoints: window.usedPercent - budget.elapsedPercent
        )
    }

    public static func workdayBudget(
        window: QuotaWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> WorkdayBudget? {
        guard window.resetMode == .fixedCycle,
              window.durationSeconds > 0,
              let resetAt = window.resetAt else { return nil }
        let startAt = resetAt.addingTimeInterval(-window.durationSeconds)
        let clampedNow = min(resetAt, max(startAt, now))
        let total = workdays(from: startAt, to: resetAt, calendar: calendar)
        guard total > 0 else { return nil }
        let elapsed = workdays(from: startAt, to: clampedNow, calendar: calendar)
        let remaining = max(0, total - elapsed)
        let elapsedPercent = min(100, max(0, elapsed / total * 100))
        // Very early in a cycle, a few requests would produce a misleading ratio.
        let speed = elapsedPercent >= 5 && now < resetAt
            ? window.usedPercent / elapsedPercent : nil
        let dailyBudget = remaining > 0.000_001 && now < resetAt
            ? window.remainingPercent / remaining : nil
        return WorkdayBudget(
            elapsedPercent: elapsedPercent,
            usedPercent: window.usedPercent,
            elapsedWorkdays: elapsed,
            remainingWorkdays: remaining,
            speedIndex: speed,
            dailyBudgetPercent: dailyBudget
        )
    }

    public static func calendarWorkweekElapsedPercent(
        now: Date,
        calendar: Calendar = .current
    ) -> Double {
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday,
                                         to: startOfToday),
              let saturday = calendar.date(byAdding: .day, value: 5, to: monday)
        else { return 0 }
        let clampedNow = min(saturday, max(monday, now))
        let duration = saturday.timeIntervalSince(monday)
        guard duration > 0 else { return 0 }
        return min(100, max(0, clampedNow.timeIntervalSince(monday) / duration * 100))
    }

    private static func workdays(from startAt: Date,
                                 to endAt: Date,
                                 calendar: Calendar) -> Double {
        guard endAt > startAt else { return 0 }
        var cursor = startAt
        var total: TimeInterval = 0
        while cursor < endAt {
            let startOfDay = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            else { break }
            let segmentEnd = min(nextDay, endAt)
            let weekday = calendar.component(.weekday, from: cursor)
            if (2...6).contains(weekday) {
                let dayLength = nextDay.timeIntervalSince(startOfDay)
                if dayLength > 0 { total += segmentEnd.timeIntervalSince(cursor) / dayLength }
            }
            cursor = segmentEnd
        }
        return total
    }
}
