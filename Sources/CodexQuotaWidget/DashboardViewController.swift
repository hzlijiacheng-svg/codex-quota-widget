import AppKit
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class DashboardViewController: NSViewController {
    let store: QuotaStore
    var onRefresh: (() -> Void)?
    private let content = NSStackView()
    private var errorDetail: String?

    init(store: QuotaStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 440, height: 640)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        view = effect
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
        rebuild()
    }

    func rebuild() {
        guard isViewLoaded else { return }
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = label("Codex 额度", size: 22, weight: .semibold)
        content.addArrangedSubview(title)
        addDivider()

        guard let snapshot = store.snapshots[.codex] else {
            let message = store.errors[.codex] ?? "正在读取…"
            if store.errors[.codex] != nil {
                errorDetail = message
                content.addArrangedSubview(label("暂时无法读取额度", size: 17, weight: .semibold,
                                                 color: .systemOrange))
                let summary = label(Self.errorSummary(message), size: 13,
                                    color: .secondaryLabelColor)
                summary.maximumNumberOfLines = 3
                summary.lineBreakMode = .byWordWrapping
                summary.widthAnchor.constraint(equalToConstant: 392).isActive = true
                content.addArrangedSubview(summary)
                let detail = NSButton(title: "查看错误详情…", target: self,
                                      action: #selector(showErrorDetail))
                detail.controlSize = .small
                content.addArrangedSubview(detail)
            } else {
                content.addArrangedSubview(label(message, size: 14, color: .secondaryLabelColor))
            }
            addFooter()
            return
        }
        errorDetail = nil

        addWindows(snapshot)
        addQuotaPace(snapshot)
        addTokenPace(snapshot)
        addTokenBreakdown(snapshot)
        addFooter()
    }

    private func addTokenPace(_ snapshot: ProviderSnapshot) {
        content.addArrangedSubview(label("今日用量对比", size: 13, color: .secondaryLabelColor))
        if let pace = snapshot.tokenPace {
            content.addArrangedSubview(label(DashboardCopy.tokenHeadline(pace), size: 17,
                                             weight: .semibold,
                                             color: pace.deltaPercent > 15 ? .systemOrange : .labelColor))
            content.addArrangedSubview(label(
                "今日 \(Self.tokens(pace.todayTokens))  ·  近期同时段均值 \(Self.tokens(pace.baselineTokens))  ·  \(pace.sampleDays) 天样本",
                size: 11, color: .tertiaryLabelColor
            ))
        } else if let breakdown = snapshot.tokenBreakdown {
            content.addArrangedSubview(label("今日 \(Self.tokens(breakdown.total)) · 历史样本不足，暂不判断快慢",
                                                   size: 16, weight: .medium))
        } else if store.isLoadingTokens {
            content.addArrangedSubview(label("正在扫描本机 Token 日志…", size: 16,
                                                   color: .secondaryLabelColor))
        } else {
            content.addArrangedSubview(label("暂无可核验的 Token 明细", size: 16,
                                                   color: .secondaryLabelColor))
        }
        addDivider()
    }

    private func addQuotaPace(_ snapshot: ProviderSnapshot) {
        guard let weekly = snapshot.windows.first(where: { $0.kind == .weekly }),
              let naturalPace = QuotaPaceCalculator.calculate(window: weekly, now: Date()),
              let workdayPace = QuotaPaceCalculator.calculateWorkday(window: weekly, now: Date())
        else { return }
        content.addArrangedSubview(label("额度节奏", size: 13, color: .secondaryLabelColor))
        let rings = NSStackView()
        rings.orientation = .horizontal
        rings.distribution = .fillEqually
        rings.spacing = 4
        rings.widthAnchor.constraint(equalToConstant: 392).isActive = true
        rings.addArrangedSubview(RingMetricView(title: "本周时间",
                                               percent: naturalPace.elapsedPercent,
                                               tint: .systemBlue))
        rings.addArrangedSubview(RingMetricView(title: "工作日已过",
                                               percent: workdayPace.elapsedPercent,
                                               tint: .systemTeal))
        rings.addArrangedSubview(RingMetricView(title: "额度已用",
                                               percent: workdayPace.usedPercent,
                                               tint: .systemPurple))
        content.addArrangedSubview(rings)
        let insightTint: NSColor
        if workdayPace.deltaPercentagePoints >= 2 {
            insightTint = .systemOrange
        } else if workdayPace.deltaPercentagePoints <= -2 {
            insightTint = .systemTeal
        } else {
            insightTint = .systemGreen
        }
        content.addArrangedSubview(InsightBanner(
            text: DashboardCopy.workdayComparison(
                deltaPercentagePoints: workdayPace.deltaPercentagePoints
            ),
            tint: insightTint
        ))
        content.addArrangedSubview(label("工作日进度仅排除周六、周日",
                                         size: 10, color: .tertiaryLabelColor))
        addDivider()
    }

    private func addWindows(_ snapshot: ProviderSnapshot) {
        for window in snapshot.windows {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let name = window.kind == .session ? "5 小时额度" : "7 天额度"
            let pct = Int(window.remainingPercent.rounded())
            let reset = window.resetAt.map { Self.countdown(to: $0) } ?? "重置时间未知"
            let title = label(name, size: 14, weight: .semibold)
            title.widthAnchor.constraint(equalToConstant: 62).isActive = true
            let bar = LevelBar()
            bar.percent = window.remainingPercent
            bar.tint = window.kind == .session ? .systemBlue : .systemPurple
            bar.widthAnchor.constraint(equalToConstant: 112).isActive = true
            let percent = label("剩余 \(pct)%", size: 14, weight: .semibold,
                                color: pct <= 20 ? .systemRed : .labelColor)
            percent.widthAnchor.constraint(equalToConstant: 62).isActive = true
            let resetLabel = label(reset, size: 13, weight: .semibold,
                                   color: window.resetAt == nil ? .secondaryLabelColor : .systemOrange)
            resetLabel.alignment = .right
            resetLabel.widthAnchor.constraint(equalToConstant: 126).isActive = true
            row.addArrangedSubview(title)
            row.addArrangedSubview(bar)
            row.addArrangedSubview(percent)
            row.addArrangedSubview(resetLabel)
            content.addArrangedSubview(row)
        }
        addDivider()
    }

    private func addTokenBreakdown(_ snapshot: ProviderSnapshot) {
        guard let tokens = snapshot.tokenBreakdown else { return }
        content.addArrangedSubview(label("今日 Token 构成  \(Self.tokens(tokens.total))",
                                         size: 13, weight: .semibold,
                                         color: .secondaryLabelColor))
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 392).isActive = true
        row.addArrangedSubview(compactMetric("输入", tokens.input, .systemGreen))
        row.addArrangedSubview(compactMetric("缓存", tokens.cachedInput, .systemPurple))
        row.addArrangedSubview(compactMetric("输出", tokens.output, .systemOrange))
        content.addArrangedSubview(row)
    }

    private func compactMetric(_ title: String, _ value: Int64, _ color: NSColor) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.addArrangedSubview(label(title, size: 11, color: .secondaryLabelColor))
        stack.addArrangedSubview(label(Self.tokens(value), size: 15,
                                         weight: .semibold, color: color))
        return stack
    }

    private func addFooter() {
        addDivider()
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
        let method = NSButton(title: "统计口径…", target: self, action: #selector(showMethod))
        let logs = NSButton(title: "打开日志目录", target: self, action: #selector(openLogs))
        let refresh = NSButton(title: "立即刷新", target: self, action: #selector(refresh))
        [method, logs, refresh].forEach { $0.controlSize = .small }
        logs.toolTip = "在 Finder 中打开 ~/.codex/sessions，不修改日志"
        row.addArrangedSubview(method)
        row.addArrangedSubview(logs)
        row.addArrangedSubview(refresh)
        content.addArrangedSubview(row)
    }

    private func addDivider() {
        let line = NSBox(); line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 392).isActive = true
        content.addArrangedSubview(line)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = 2
        return field
    }

    @objc private func refresh() { onRefresh?() }

    @objc private func showErrorDetail() {
        let alert = NSAlert()
        alert.messageText = "额度读取失败"
        alert.informativeText = errorDetail ?? "暂无错误详情"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        )
    }

    @objc private func showMethod() {
        let alert = NSAlert()
        alert.messageText = "统计口径"
        alert.informativeText = "额度来自本机 Codex app-server。Token 来自本机 Codex 会话日志，只读取 token_count 数值，不读取或上传提示词与回复。今日用量比较今日 00:00 至当前时刻，与此前 7 个自然日同一时段的平均值；少于 3 天不下结论。工作日进度按同一个 7 天额度周期计算，仅排除周六、周日，不包含法定节假日。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private static func tokens(_ value: Int64) -> String {
        let number = Double(value)
        if abs(number) >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if abs(number) >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }

    private static func errorSummary(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("failed to fetch") || lower.contains("error sending request") ||
            lower.contains("network") || lower.contains("timed out") {
            return "未能连接 ChatGPT 额度服务。已自动尝试可用代理和直连；请检查网络后重试。"
        }
        if lower.contains("login") || lower.contains("unauthorized") || lower.contains("401") {
            return "当前 Codex 登录状态不可用，请先在 Codex 中重新登录后重试。"
        }
        return "额度服务暂时没有返回可用数据，请稍后重试。"
    }

    static func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds >= 86_400 { return "\(seconds / 86_400)天\((seconds % 86_400) / 3600)小时后重置" }
        if seconds >= 3600 { return "\(seconds / 3600)小时\((seconds % 3600) / 60)分钟后重置" }
        return "\(max(1, seconds / 60))分钟后重置"
    }
}
