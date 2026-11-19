import Foundation

struct QuotaTrendPoint: Codable, Equatable {
    let at: Date
    let remainingPercent: Double
}

struct QuotaForecast {
    let remainingAtReset: Double
    let exhaustionAt: Date?
}

struct QuotaBudgetSample {
    let at: Date
    let actual: Double
    let budget: Double

    var difference: Double { actual - budget }
}

struct QuotaBudgetBand {
    let start: QuotaBudgetSample
    let end: QuotaBudgetSample

    var isSurplus: Bool { start.difference + end.difference > 0 }
}

enum QuotaTrendCalculator {
    /// Allocates the full quota evenly across the local weekdays in the cycle.
    static func evenBudgetLine(window: QuotaWindow,
                               calendar: Calendar = .current) -> [QuotaTrendPoint]? {
        guard window.resetMode == .fixedCycle, window.durationSeconds > 0,
              let reset = window.resetAt else { return nil }
        let start = reset.addingTimeInterval(-window.durationSeconds)
        let total = QuotaPaceCalculator.workdays(from: start, to: reset, calendar: calendar)
        guard total > 0 else { return nil }

        var boundaries = [start]
        var cursor = start
        while let midnight = calendar.dateInterval(of: .day, for: cursor)?.end,
              midnight > cursor, midnight < reset {
            boundaries.append(midnight)
            cursor = midnight
        }
        boundaries.append(reset)
        return boundaries.map { boundary in
            let elapsed = QuotaPaceCalculator.workdays(from: start, to: boundary, calendar: calendar)
            let remaining = min(100, max(0, 100 * (1 - elapsed / total)))
            return QuotaTrendPoint(at: boundary, remainingPercent: remaining)
        }
    }

    /// Interpolates a chronologically sorted series within its observed range.
    static func remainingPercent(at date: Date, along points: [QuotaTrendPoint]) -> Double? {
        guard let first = points.first, let last = points.last,
              date >= first.at, date <= last.at else { return nil }

        let lower = firstIndexOnOrAfter(date, in: points)
        let next = points[lower]
        if lower == 0 || next.at == date { return next.remainingPercent }
        let previous = points[lower - 1]
        let fraction = date.timeIntervalSince(previous.at) / next.at.timeIntervalSince(previous.at)
        return previous.remainingPercent + fraction * (next.remainingPercent - previous.remainingPercent)
    }

    private static func firstIndexOnOrAfter(_ date: Date, in points: [QuotaTrendPoint]) -> Int {
        var lower = 0
        var upper = points.count - 1
        while lower < upper {
            let midpoint = (lower + upper) / 2
            if points[midpoint].at < date { lower = midpoint + 1 } else { upper = midpoint }
        }
        return lower
    }

    /// Snap to a recorded observation, including unchanged readings between drawn vertices.
    static func nearestReading(to date: Date, in points: [QuotaTrendPoint]) -> QuotaTrendPoint? {
        guard !points.isEmpty else { return nil }
        let index = firstIndexOnOrAfter(date, in: points)
        guard index > 0 else { return points[0] }
        let previous = points[index - 1]
        let next = points[index]
        return date.timeIntervalSince(previous.at) <= next.at.timeIntervalSince(date) ? previous : next
    }

    static func budgetBands(actual: [QuotaTrendPoint], baseline: [QuotaTrendPoint]) -> [QuotaBudgetBand] {
        guard let first = actual.first?.at, let last = actual.last?.at, first < last else { return [] }
        var samples = actual.compactMap { point -> QuotaBudgetSample? in
            guard let budget = remainingPercent(at: point.at, along: baseline) else { return nil }
            return QuotaBudgetSample(at: point.at, actual: point.remainingPercent, budget: budget)
        }
        // Include schedule boundaries so a sparse usage history still has flat budget segments over the weekend.
        samples.append(contentsOf: baseline.compactMap { point in
            guard point.at > first, point.at < last,
                  let actualRemaining = remainingPercent(at: point.at, along: actual) else { return nil }
            return QuotaBudgetSample(at: point.at, actual: actualRemaining, budget: point.remainingPercent)
        })
        samples.sort { $0.at < $1.at }

        var bands: [QuotaBudgetBand] = []
        for (start, end) in zip(samples, samples.dropFirst()) where start.at < end.at {
            let startGap = start.difference
            let endGap = end.difference
            guard startGap != 0 || endGap != 0 else { continue }
            if startGap * endGap < 0 {
                let fraction = startGap / (startGap - endGap)
                let date = start.at.addingTimeInterval(fraction * end.at.timeIntervalSince(start.at))
                let remaining = start.actual + fraction * (end.actual - start.actual)
                let crossing = QuotaBudgetSample(at: date, actual: remaining, budget: remaining)
                bands.append(QuotaBudgetBand(start: start, end: crossing))
                bands.append(QuotaBudgetBand(start: crossing, end: end))
            } else {
                bands.append(QuotaBudgetBand(start: start, end: end))
            }
        }
        return bands
    }

    static func compactActualPoints(_ points: [QuotaTrendPoint]) -> [QuotaTrendPoint] {
        var result: [QuotaTrendPoint] = []
        for point in points.sorted(by: { $0.at < $1.at }) {
            if result.count >= 2 && result[result.count - 1].remainingPercent == point.remainingPercent &&
                result[result.count - 2].remainingPercent == point.remainingPercent {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        return result
    }

    /// Extends the current cycle's average consumption over future working hours.
    static func forecast(window: QuotaWindow, now: Date,
                         calendar: Calendar = .current) -> QuotaForecast? {
        guard let reset = window.resetAt,
              now < reset,
              let budget = QuotaPaceCalculator.workdayBudget(window: window, now: now, calendar: calendar),
              budget.speedIndex != nil, budget.elapsedWorkdays > 0,
              budget.remainingWorkdays > 0.000_001 else { return nil }

        let rate = window.usedPercent / budget.elapsedWorkdays
        let remainingAtReset = max(0, window.remainingPercent - rate * budget.remainingWorkdays)
        var exhaustionAt: Date? = window.remainingPercent <= 0 ? now : nil
        if exhaustionAt == nil && rate > 0 && remainingAtReset <= 0 {
            let daysUntilExhaustion = window.remainingPercent / rate
            var lower = now
            var upper = reset
            for _ in 0..<40 {
                let midpoint = lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
                let elapsed = QuotaPaceCalculator.workdays(from: now, to: midpoint, calendar: calendar)
                if elapsed >= daysUntilExhaustion { upper = midpoint } else { lower = midpoint }
            }
            exhaustionAt = upper
        }
        return QuotaForecast(remainingAtReset: remainingAtReset, exhaustionAt: exhaustionAt)
    }
}

private struct QuotaHistoryRecord: Codable {
    let provider: ProviderID
    let identity: String?
    let resetAt: Date
    let duration: TimeInterval
    let point: QuotaTrendPoint
}

/// Only hashed account/rule identities and quota percentages are stored on disk.
final class QuotaHistory {
    private let url: URL
    private var records: [QuotaHistoryRecord]
    private(set) var saveFailed = false

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([QuotaHistoryRecord].self, from: data) {
            records = saved.filter { $0.identity != nil }
        } else {
            records = []
        }
    }

    func record(provider: ProviderID, identity: String?, window: QuotaWindow, at: Date) {
        guard window.resetMode == .fixedCycle, let reset = window.resetAt,
              window.durationSeconds > 0, at >= reset.addingTimeInterval(-window.durationSeconds),
              at < reset, window.remainingPercent.isFinite else { return }
        let record = QuotaHistoryRecord(provider: provider, identity: identity, resetAt: reset,
                                        duration: window.durationSeconds,
                                        point: QuotaTrendPoint(at: at, remainingPercent: window.remainingPercent))
        records.removeAll { $0.provider == provider && $0.identity == identity &&
            $0.resetAt == reset && $0.duration == window.durationSeconds && $0.point.at == at }
        records.append(record)
        prune(now: at)
        guard identity != nil else { return }
        save()
    }

    func importPoints(_ points: [QuotaTrendPoint], provider: ProviderID, identity: String?,
                      window: QuotaWindow, now: Date) {
        guard let identity, window.resetMode == .fixedCycle, let reset = window.resetAt,
              window.durationSeconds > 0 else { return }
        let start = reset.addingTimeInterval(-window.durationSeconds)
        var seen = Set(records.filter {
            $0.provider == provider && $0.identity == identity && $0.resetAt == reset &&
                $0.duration == window.durationSeconds
        }.map { $0.point.at })
        var added = false
        for point in points where point.at >= start && point.at < reset && point.at <= now &&
            point.remainingPercent.isFinite && (0...100).contains(point.remainingPercent) {
            guard seen.insert(point.at).inserted else { continue }
            records.append(QuotaHistoryRecord(provider: provider, identity: identity,
                                              resetAt: reset, duration: window.durationSeconds,
                                              point: point))
            added = true
        }
        guard added else { return }
        prune(now: now)
        save()
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-45 * 86_400)
        records = Array(records.filter { $0.point.at >= cutoff }.sorted { $0.point.at < $1.point.at }.suffix(8192))
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(records.filter { $0.identity != nil })
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    func points(provider: ProviderID, identity: String?, window: QuotaWindow, at: Date) -> [QuotaTrendPoint] {
        guard let reset = window.resetAt, window.durationSeconds > 0 else { return [] }
        let start = reset.addingTimeInterval(-window.durationSeconds)
        return records.filter {
            $0.provider == provider && $0.identity == identity && $0.resetAt == reset &&
            $0.duration == window.durationSeconds && $0.point.at >= start &&
            $0.point.at < reset && $0.point.at <= at
        }.map(\.point).sorted { $0.at < $1.at }
    }
}
