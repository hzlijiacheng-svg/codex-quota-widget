import Foundation

enum DashboardCopy {
    static func tokenHeadline(_ pace: TokenPace) -> String {
        let direction = pace.deltaTokens >= 0 ? "多用" : "少用"
        let sign = pace.deltaPercent >= 0 ? "+" : ""
        return "今天比近期同时段\(direction) \(compactTokens(abs(pace.deltaTokens))) Token（\(sign)\(Int(pace.deltaPercent.rounded()))%）"
    }

    static func cycleComparison(deltaPercentagePoints: Double) -> String {
        let magnitude = abs(deltaPercentagePoints)
        guard magnitude >= 2 else { return "额度与周期进度基本匹配" }
        let direction = deltaPercentagePoints >= 0 ? "快" : "慢"
        let advice: String
        if deltaPercentagePoints > 0 {
            advice = magnitude >= 10 ? "建议大幅节省" : "建议稍微省一点"
        } else {
            advice = magnitude >= 10 ? "目前大额富余" : "目前小额富余"
        }
        return "额度比周期进度\(direction) \(Int(magnitude.rounded()))% · \(advice)"
    }

    static func compactTokens(_ value: Int64) -> String {
        let number = Double(value)
        if abs(number) >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        }
        if abs(number) >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        }
        return "\(value)"
    }
}
