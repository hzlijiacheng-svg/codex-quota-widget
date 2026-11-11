import AppKit
#if SWIFT_PACKAGE
import QuotaCore
#endif

final class DashboardViewController: NSViewController {
    let store: QuotaStore
    var onRefresh: (() -> Void)?
    private let content = NSStackView()
    private var selectedProvider: ProviderID = .codex
    private var errorDetail: String?
    private let contentWidth: CGFloat = 392

    init(store: QuotaStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 440, height: 600)
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
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 18, right: 24)
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
        addHeader()
        addProviderCards()
        addFreshness()
        if selectedProvider == .codex { addCodex() } else { addGateway() }
        addFooter()
        let height = max(300, min(700, ceil(content.fittingSize.height)))
        preferredContentSize = NSSize(width: 440, height: height)
    }

    private func addHeader() {
        let row = horizontalRow()
        let title = label("额度与节奏", size: 21, weight: .semibold)
        let subtitle = label("使用概览", size: 12, color: .secondaryLabelColor)
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 3
        heading.widthAnchor.constraint(equalToConstant: 290).isActive = true
        let refresh = NSButton(title: "刷新", target: self, action: #selector(refresh))
        refresh.bezelStyle = .rounded
        refresh.controlSize = .regular
        refresh.toolTip = "刷新 Codex 和企业网关额度"
        row.addArrangedSubview(heading)
        row.addArrangedSubview(refresh)
        content.addArrangedSubview(row)
    }

    private func addProviderCards() {
        let row = horizontalRow()
        row.distribution = .fillEqually
        row.spacing = 10
        row.addArrangedSubview(providerButton(.codex))
        row.addArrangedSubview(providerButton(.zcode))
        content.addArrangedSubview(row)
    }

    private func providerButton(_ provider: ProviderID) -> NSButton {
        let selected = selectedProvider == provider
        let accent: NSColor = provider == .codex ? DashboardPalette.codex : DashboardPalette.gateway
        let snapshot = store.snapshots[provider]
        let hasError = store.errors[provider] != nil
        let percentage: Double? = provider == .codex
            ? snapshot?.windows.first(where: { $0.kind == .weekly })?.remainingPercent
            : snapshot?.gatewayQuota?.remainingPercent
        let value = percentage.map { "\(Int($0.rounded()))%" } ?? "—"
        let caption = hasError ? "更新失败" : (provider == .codex ? "周额度剩余" : "网关额度剩余")
        let text = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        text.append(NSAttributedString(string: "\(provider.displayName)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ]))
        text.append(NSAttributedString(string: "\(value)  ", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 21, weight: .semibold),
            .foregroundColor: hasError ? DashboardPalette.warning : NSColor.labelColor,
            .paragraphStyle: paragraph
        ]))
        text.append(NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.75),
            .paragraphStyle: paragraph
        ]))
        let button = NSButton(title: "", target: self, action: #selector(selectProvider(_:)))
        button.tag = provider == .codex ? 0 : 1
        button.isBordered = false
        button.attributedTitle = text
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = (selected ? accent.withAlphaComponent(0.14)
                                                  : NSColor.labelColor.withAlphaComponent(0.045)).cgColor
        button.layer?.borderWidth = selected ? 1 : 0
        button.layer?.borderColor = accent.withAlphaComponent(0.4).cgColor
        button.heightAnchor.constraint(equalToConstant: 70).isActive = true
        button.setAccessibilityLabel("\(provider.displayName)，\(caption) \(value)\(selected ? "，已选择" : "")")
        return button
    }

    private func addFreshness() {
        let snapshot = store.snapshots[selectedProvider]
        if let error = store.errors[selectedProvider] {
            errorDetail = error
            let text: String
            if let snapshot {
                let time = DateFormatter.localizedString(from: snapshot.updatedAt, dateStyle: .short, timeStyle: .short)
                text = "更新失败 · 显示 \(time) 的数据"
            } else {
                text = "暂时无法读取，点击下方查看原因"
            }
            content.addArrangedSubview(label(text, size: 12, color: DashboardPalette.warning))
        } else if let snapshot {
            errorDetail = nil
            let time = DateFormatter.localizedString(from: snapshot.updatedAt, dateStyle: .none, timeStyle: .short)
            content.addArrangedSubview(label("更新于 \(time) · 每 5 分钟自动刷新", size: 11,
                                             color: .secondaryLabelColor))
        } else {
            errorDetail = nil
            content.addArrangedSubview(label("正在读取额度…", size: 12, color: .secondaryLabelColor))
        }
    }

    private func addCodex() {
        guard let snapshot = store.snapshots[.codex] else {
            addEmptyState()
            return
        }
        guard let weekly = snapshot.windows.first(where: { $0.kind == .weekly }) else {
            content.addArrangedSubview(label("Codex 没有返回周额度", size: 14, color: .secondaryLabelColor))
            return
        }
        addQuotaHeading(title: "Codex 周额度", remaining: weekly.remainingPercent,
                        detail: "已用 \(Self.percent(weekly.usedPercent))%",
                        reset: weekly.resetAt, tint: DashboardPalette.codex)
        if let session = snapshot.windows.first(where: { $0.kind == .session }) {
            let reset = session.resetAt.map { Self.countdown(to: $0) } ?? "重置时间未知"
            content.addArrangedSubview(label("5 小时额度  剩余 \(Self.percent(session.remainingPercent))%  ·  \(reset)",
                                             size: 12, color: .secondaryLabelColor))
        }
        addDivider()
        let paceTime = store.errors[.codex] == nil ? Date() : snapshot.updatedAt
        addWorkdaySpeed(weekly, at: paceTime)
        addDivider()
        addTokenPace(snapshot)
    }

    private func addWorkdaySpeed(_ weekly: QuotaWindow, at now: Date) {
        content.addArrangedSubview(label("本周期平均速度", size: 14, weight: .semibold))
        guard let budget = QuotaPaceCalculator.workdayBudget(window: weekly, now: now) else {
            content.addArrangedSubview(label("周期信息不完整，暂时无法计算", size: 13,
                                             color: .secondaryLabelColor))
            return
        }
        let speedRow = horizontalRow()
        if let speed = budget.speedIndex {
            let band = WorkdaySpeed.classify(speed)
            let tint: NSColor = band == .fast ? DashboardPalette.warning :
                (band == .slow ? DashboardPalette.gateway : DashboardPalette.balanced)
            let value = label("\(String(format: "%.2f", speed))×", size: 26, weight: .semibold, color: tint)
            value.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
            let description = label("\(band.title) · 1.00× 为均匀节奏", size: 13,
                                    weight: .medium, color: tint)
            speedRow.addArrangedSubview(value)
            speedRow.addArrangedSubview(description)
        } else {
            speedRow.addArrangedSubview(label("速度待观察", size: 18, weight: .medium,
                                               color: .secondaryLabelColor))
        }
        content.addArrangedSubview(speedRow)
        content.addArrangedSubview(metricRow("工作日已过", percent: budget.elapsedPercent, tint: DashboardPalette.gateway))
        content.addArrangedSubview(metricRow("额度已用", percent: budget.usedPercent, tint: DashboardPalette.codex))
        if let daily = budget.dailyBudgetPercent {
            let days = budget.remainingWorkdays < 0.05 ? "不足 0.1" : String(format: "%.1f", budget.remainingWorkdays)
            content.addArrangedSubview(label("剩余 \(days) 个工作日 · 平均每天可用 \(String(format: "%.1f", daily))%",
                                             size: 12, weight: .medium))
        } else {
            content.addArrangedSubview(label("本周期剩余工作日为 0", size: 12, color: .secondaryLabelColor))
        }
        content.addArrangedSubview(label("按本额度周期计算 · 周一至周五全天", size: 11,
                                         color: .secondaryLabelColor))
    }

    private func addTokenPace(_ snapshot: ProviderSnapshot) {
        content.addArrangedSubview(label("今日 Token", size: 14, weight: .semibold))
        if let pace = snapshot.tokenPace {
            let sign = pace.deltaPercent >= 0 ? "+" : ""
            content.addArrangedSubview(label("\(Self.tokens(pace.todayTokens))  ·  较近期同时段 \(sign)\(Int(pace.deltaPercent.rounded()))%",
                                             size: 13, weight: .medium))
            content.addArrangedSubview(label("参考最近 \(pace.sampleDays) 天同时段平均值", size: 11,
                                             color: .secondaryLabelColor))
        } else if let breakdown = snapshot.tokenBreakdown {
            content.addArrangedSubview(label("\(Self.tokens(breakdown.total))  ·  历史样本不足", size: 13))
        } else {
            content.addArrangedSubview(label(store.isLoadingTokens ? "正在扫描本机日志…" : "暂无可核验的明细",
                                             size: 13, color: .secondaryLabelColor))
        }
        if let tokens = snapshot.tokenBreakdown {
            content.addArrangedSubview(label("输入 \(Self.tokens(tokens.input))  ·  缓存 \(Self.tokens(tokens.cachedInput))  ·  输出 \(Self.tokens(tokens.output))",
                                             size: 11, color: .secondaryLabelColor))
        }
    }

    private func addGateway() {
        guard let snapshot = store.snapshots[.zcode], let quota = snapshot.gatewayQuota else {
            addEmptyState()
            return
        }
        let title: String
        switch quota.period {
        case "day": title = "企业网关日额度"
        case "week": title = "企业网关周额度"
        case "month": title = "企业网关月额度"
        default: title = "企业网关额度"
        }
        addQuotaHeading(title: title, remaining: quota.remainingPercent,
                        detail: "已用 \(Self.tokens(quota.used)) / \(Self.tokens(quota.limit)) Token",
                        reset: quota.resetAt, tint: DashboardPalette.gateway)
        addDivider()
        let paceTime = store.errors[.zcode] == nil ? Date() : snapshot.updatedAt
        addGatewaySpeed(quota, at: paceTime)
        addDivider()
        content.addArrangedSubview(label("网关用量", size: 14, weight: .semibold))
        content.addArrangedSubview(label("剩余 \(Self.tokens(quota.remaining)) Token", size: 18, weight: .semibold))
        let parts: [(String, Int64?)] = [("输入", quota.input), ("输出", quota.output), ("缓存", quota.cached)]
        let values = parts.compactMap { title, value in value.map { "\(title) \(Self.tokens($0))" } }
        if !values.isEmpty {
            content.addArrangedSubview(label(values.joined(separator: "  ·  "), size: 12,
                                             color: .secondaryLabelColor))
        }
        content.addArrangedSubview(label("数据范围：已配置的网关消费者及规则", size: 11,
                                         color: .secondaryLabelColor))
    }

    private func addGatewaySpeed(_ quota: GatewayQuota, at now: Date) {
        content.addArrangedSubview(label("当日平均速度", size: 14, weight: .semibold))
        guard quota.period == "day", quota.alignment == "calendar", let reset = quota.resetAt,
              Calendar.current.startOfDay(for: reset) == reset,
              now >= reset.addingTimeInterval(-86_400), now < reset else {
            content.addArrangedSubview(label("当前周期无法计算日速度", size: 12, color: .secondaryLabelColor))
            return
        }
        let window = QuotaWindow(kind: .session, usedPercent: 100 - quota.remainingPercent,
                                 resetAt: reset, durationSeconds: 86_400, resetMode: .fixedCycle)
        guard let budget = QuotaPaceCalculator.workdayBudget(window: window, now: now) else {
            content.addArrangedSubview(label("周末不计算工作日速度", size: 12, color: .secondaryLabelColor))
            return
        }
        if let speed = budget.speedIndex {
            let band = WorkdaySpeed.classify(speed)
            let tint: NSColor = band == .fast ? DashboardPalette.warning :
                (band == .slow ? DashboardPalette.gateway : DashboardPalette.balanced)
            content.addArrangedSubview(label("\(String(format: "%.2f", speed))×  \(band.title) · 1.00× 为均匀节奏",
                                             size: 18, weight: .semibold, color: tint))
        } else {
            content.addArrangedSubview(label("速度待观察", size: 14, color: .secondaryLabelColor))
        }
        content.addArrangedSubview(label("当日已过 \(Self.percent(budget.elapsedPercent))% · 额度已用 \(Self.percent(budget.usedPercent))%",
                                         size: 12, color: .secondaryLabelColor))
    }

    private func addQuotaHeading(title: String, remaining: Double, detail: String,
                                 reset: Date?, tint: NSColor) {
        content.addArrangedSubview(label(title, size: 14, weight: .semibold))
        let row = horizontalRow()
        let value = label("\(Self.percent(remaining))%", size: 28, weight: .semibold, color: tint)
        value.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        row.addArrangedSubview(value)
        row.addArrangedSubview(label("剩余", size: 13, color: .secondaryLabelColor))
        content.addArrangedSubview(row)
        let bar = LevelBar()
        bar.percent = remaining
        bar.tint = tint
        bar.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        content.addArrangedSubview(bar)
        let resetText = reset.map { Self.countdown(to: $0) } ?? "重置时间未知"
        content.addArrangedSubview(label("\(detail)  ·  \(resetText)", size: 12,
                                         color: .secondaryLabelColor))
    }

    private func metricRow(_ title: String, percent: Double, tint: NSColor) -> NSStackView {
        let row = horizontalRow()
        row.spacing = 8
        let name = label(title, size: 12, color: .secondaryLabelColor)
        name.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let bar = LevelBar()
        bar.percent = percent
        bar.tint = tint
        bar.widthAnchor.constraint(equalToConstant: 200).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let value = label("\(Self.percent(percent))%", size: 12, weight: .medium)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        row.addArrangedSubview(name)
        row.addArrangedSubview(bar)
        row.addArrangedSubview(value)
        return row
    }

    private func addEmptyState() {
        if store.errors[selectedProvider] != nil {
            content.addArrangedSubview(label("暂时无法读取额度", size: 16, weight: .semibold))
            let detail = NSButton(title: "查看原因…", target: self, action: #selector(showErrorDetail))
            content.addArrangedSubview(detail)
        } else {
            content.addArrangedSubview(label("正在读取额度…", size: 14, color: .secondaryLabelColor))
        }
    }

    private func addFooter() {
        addDivider()
        let row = horizontalRow()
        row.spacing = 12
        let method = NSButton(title: "统计说明…", target: self, action: #selector(showMethod))
        let logs = NSButton(title: "打开 Codex 日志", target: self, action: #selector(openLogs))
        method.controlSize = .small
        logs.controlSize = .small
        row.addArrangedSubview(method)
        row.addArrangedSubview(logs)
        if errorDetail != nil && store.snapshots[selectedProvider] != nil {
            let detail = NSButton(title: "查看更新错误…", target: self, action: #selector(showErrorDetail))
            detail.controlSize = .small
            row.addArrangedSubview(detail)
        }
        content.addArrangedSubview(row)
    }

    private func horizontalRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return row
    }

    private func addDivider() {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
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

    @objc private func selectProvider(_ sender: NSButton) {
        selectedProvider = sender.tag == 0 ? .codex : .zcode
        rebuild()
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
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"))
    }
    @objc private func showMethod() {
        let alert = NSAlert()
        alert.messageText = "统计说明"
        alert.informativeText = "工作日速度 = 本周期额度已用比例 ÷ 本周期工作日已过比例。1.00× 为均匀节奏；低于 0.80× 显示偏慢，高于 1.20× 显示偏快。周期初期工作日进度不足 5% 时暂不判断。Codex 剩余每日可用比例 = 剩余额度 ÷ 重置前剩余工作日。工作日按周一至周五全天计算，暂不识别法定节假日和调休。\n\nCodex 额度来自本机 app-server，Token 对比来自本机会话日志。ZCode 数据来自企业网关中配置的消费者和额度规则；网关为日周期时，可计算工作日当天的速度。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private static func tokens(_ value: Int64) -> String { DashboardCopy.compactTokens(value) }
    private static func percent(_ value: Double) -> String { "\(Int(value.rounded()))" }

    static func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds == 0 { return "等待重置" }
        if seconds >= 86_400 { return "\(seconds / 86_400)天\((seconds % 86_400) / 3600)小时后重置" }
        if seconds >= 3600 { return "\(seconds / 3600)小时\((seconds % 3600) / 60)分钟后重置" }
        return "\(max(1, seconds / 60))分钟后重置"
    }
}
