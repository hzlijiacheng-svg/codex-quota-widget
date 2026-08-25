import Foundation

enum TouchBarPaceTone: Equatable {
    case fast
    case slow
    case normal
    case unavailable
}

struct TouchBarQuotaPresentation: Equatable {
    let title: String
    let remaining: String
    let remainingPercent: Double
    let used: String
    let reset: String
    let pace: String
    let paceTone: TouchBarPaceTone
}

enum TouchBarQuotaPresenter {
    static func make(snapshot: ProviderSnapshot?,
                     now: Date,
                     calendar: Calendar = .current) -> TouchBarQuotaPresentation? {
        guard let snapshot,
              let weekly = snapshot.windows.first(where: { $0.kind == .weekly })
        else { return nil }

        let pace = QuotaPaceCalculator.calculateWorkday(
            window: weekly, now: now, calendar: calendar
        )
        let paceText: String
        let paceTone: TouchBarPaceTone
        if let delta = pace?.deltaPercentagePoints {
            let rounded = Int(abs(delta).rounded())
            if rounded >= 2, delta > 0 {
                paceText = "工作日快 \(rounded)%"
                paceTone = .fast
            } else if rounded >= 2, delta < 0 {
                paceText = "工作日慢 \(rounded)%"
                paceTone = .slow
            } else {
                paceText = "工作日匹配"
                paceTone = .normal
            }
        } else {
            paceText = "工作日暂无"
            paceTone = .unavailable
        }

        return TouchBarQuotaPresentation(
            title: "\(snapshot.provider.displayName) 周额度",
            remaining: "\(Int(weekly.remainingPercent.rounded()))%",
            remainingPercent: weekly.remainingPercent,
            used: "已用 \(Int(weekly.usedPercent.rounded()))%",
            reset: resetText(weekly.resetAt, now: now),
            pace: paceText,
            paceTone: paceTone
        )
    }

    private static func resetText(_ resetAt: Date?, now: Date) -> String {
        guard let resetAt else { return "重置时间暂无" }
        let seconds = max(0, Int(resetAt.timeIntervalSince(now)))
        if seconds >= 86_400 {
            return "\(seconds / 86_400)天\((seconds % 86_400) / 3_600)小时后重置"
        }
        if seconds >= 3_600 {
            return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分后重置"
        }
        return "\(max(1, seconds / 60))分后重置"
    }
}
