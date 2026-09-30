import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() {
        print("PASS \(name)")
    } else {
        failures += 1
        fputs("FAIL \(name)\n", stderr)
    }
}

let codexExecutableCandidates = CodexExecutableLocator.candidates(
    environment: [:],
    homeDirectory: URL(fileURLWithPath: "/Users/tester")
)
check(codexExecutableCandidates.contains(
    "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
), "Codex locator supports the current bundled ChatGPT CLI path")
check(CodexExecutableLocator.firstExecutable(
    environment: ["CODEX_QUOTA_CODEX_PATH": "/custom/codex"],
    homeDirectory: URL(fileURLWithPath: "/Users/tester"),
    isExecutable: { $0 == "/custom/codex" }
) == "/custom/codex", "Codex locator preserves an explicit executable override")

let touchBarPlan = TouchBarPresentationPolicy.select(
    availableSelectors: [
        "presentSystemModalTouchBar:systemTrayItemIdentifier:",
        "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"
    ]
)
check(touchBarPlan == .modalWithControlStrip,
      "Touch Bar prefers the modal API that preserves the control strip")
check(TouchBarPresentationPolicy.select(
    availableSelectors: ["presentSystemModalTouchBar:systemTrayItemIdentifier:"]
) == .modalWithControlStrip,
      "Touch Bar uses the control-strip modal API when available")
check(TouchBarPresentationPolicy.select(
    availableSelectors: ["presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"]
) == .modalWithPlacement,
      "Touch Bar falls back to the placement modal API")
check(TouchBarPresentationPolicy.select(availableSelectors: []) == .unavailable,
      "Touch Bar reports unavailable private API")
check(TouchBarPresentationModePolicy.originalModeToStore(
    currentMode: "fullControlStrip", storedOriginalMode: nil
) == "fullControlStrip", "Touch Bar remembers a user mode it must override")
check(TouchBarPresentationModePolicy.originalModeToStore(
    currentMode: "appWithControlStrip", storedOriginalMode: nil
) == nil, "Touch Bar does not claim ownership of an existing compatible mode")
check(TouchBarPresentationModePolicy.originalModeToStore(
    currentMode: "appWithControlStrip", storedOriginalMode: "fullControlStrip"
) == "fullControlStrip", "Touch Bar preserves the original mode after relaunch")
check(TouchBarPresentationModePolicy.presentationDelays(modeChanged: true) == [1.5, 3.5, 7.0],
      "Touch Bar retries presentation after changing the system mode")
check(TouchBarPresentationModePolicy.presentationDelays(modeChanged: false) == [0.5, 3.0],
      "Touch Bar retries cold-start presentation without a long delay")

let proxyVariables = SystemProxyEnvironment.variables(from: [
    "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7897,
    "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897,
    "ExceptionsList": ["localhost", "*.local"]
])
check(proxyVariables["HTTPS_PROXY"] == "http://127.0.0.1:7897",
      "System proxy is translated for Codex app-server")
check(proxyVariables["NO_PROXY"] == "localhost,*.local",
      "System proxy exceptions are preserved")
let directEnvironment = SystemProxyEnvironment.removingProxyVariables(from: [
    "PATH": "/usr/bin", "HTTPS_PROXY": "http://127.0.0.1:7897", "http_proxy": "proxy"
])
check(directEnvironment["PATH"] == "/usr/bin" && directEnvironment["HTTPS_PROXY"] == nil &&
      directEnvironment["http_proxy"] == nil,
      "Direct Codex retry removes proxy variables")
let proxyCandidates = SystemProxyEnvironment.candidates(
    base: ["PATH": "/usr/bin", "HTTPS_PROXY": "http://env.proxy:8080"],
    systemSettings: [
        "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897
    ]
)
check(proxyCandidates.count == 3 &&
      proxyCandidates[0]["HTTPS_PROXY"] == "http://env.proxy:8080" &&
      proxyCandidates[1]["HTTPS_PROXY"] == "http://127.0.0.1:7897" &&
      proxyCandidates[2]["HTTPS_PROXY"] == nil,
      "Codex tries environment proxy, system proxy, then direct")
let noProxyCandidates = SystemProxyEnvironment.candidates(
    base: ["PATH": "/usr/bin"], systemSettings: [:]
)
check(noProxyCandidates.count == 1 && noProxyCandidates[0]["PATH"] == "/usr/bin",
      "Codex uses direct access without proxy configuration")
check(PopoverDismissalPolicy.shouldClose(isGlobalEvent: true,
                                         isPopoverWindow: false,
                                         isStatusItemWindow: false),
      "A click in another application closes the quota popover")
check(PopoverDismissalPolicy.shouldClose(isGlobalEvent: false,
                                         isPopoverWindow: false,
                                         isStatusItemWindow: false),
      "A click in another local window closes the quota popover")
check(!PopoverDismissalPolicy.shouldClose(isGlobalEvent: false,
                                          isPopoverWindow: true,
                                          isStatusItemWindow: false),
      "A click inside the quota popover keeps it open")
check(!PopoverDismissalPolicy.shouldClose(isGlobalEvent: false,
                                          isPopoverWindow: false,
                                          isStatusItemWindow: true),
      "The status item click is left to the toggle action")

var touchBarCalendar = Calendar(identifier: .gregorian)
touchBarCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let touchBarNow = touchBarCalendar.date(from: DateComponents(
    year: 2026, month: 8, day: 25, hour: 12
))!
let touchBarReset = touchBarCalendar.date(from: DateComponents(
    year: 2026, month: 8, day: 31, hour: 0
))!
let touchBarWeekly = QuotaWindow(
    kind: .weekly,
    usedPercent: 21,
    resetAt: touchBarReset,
    durationSeconds: 7 * 86_400,
    resetMode: .fixedCycle
)
let touchBarPresentation = TouchBarQuotaPresenter.make(
    snapshot: ProviderSnapshot(
        provider: .codex,
        planName: "prolite",
        windows: [touchBarWeekly],
        updatedAt: touchBarNow,
        sourceDescription: "test"
    ),
    now: touchBarNow
)
check(touchBarPresentation?.title == "Codex 周额度", "Touch Bar uses an explicit title")
check(touchBarPresentation?.remaining == "79%", "Touch Bar emphasizes remaining quota")
check(touchBarPresentation?.used == "已用 21%", "Touch Bar explains current usage")
check(touchBarPresentation?.reset == "5天12小时后重置", "Touch Bar explains the reset cycle")
check(touchBarPresentation?.pace == "周期匹配", "Touch Bar compares quota with its own cycle")

var workdayCalendar = Calendar(identifier: .gregorian)
workdayCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let workdayStart = workdayCalendar.date(from: DateComponents(
    year: 2026, month: 8, day: 24, hour: 0
))!
let workdayEnd = workdayCalendar.date(from: DateComponents(
    year: 2026, month: 8, day: 31, hour: 0
))!
let workdayNow = workdayCalendar.date(from: DateComponents(
    year: 2026, month: 8, day: 26, hour: 12
))!
let workdayWindow = QuotaWindow(
    kind: .weekly,
    usedPercent: 60,
    resetAt: workdayEnd,
    durationSeconds: workdayEnd.timeIntervalSince(workdayStart),
    resetMode: .fixedCycle
)
let workdayPace = QuotaPaceCalculator.calculateWorkday(
    window: workdayWindow, now: workdayNow, calendar: workdayCalendar
)
check(abs((workdayPace?.elapsedPercent ?? 0) - 50) < 0.001,
      "Workday pace excludes Saturday and Sunday")
check(abs((workdayPace?.deltaPercentagePoints ?? 0) - 10) < 0.001,
      "Workday pace compares quota usage with weekday progress")
let calendarWorkweekWednesday = QuotaPaceCalculator.calendarWorkweekElapsedPercent(
    now: workdayNow, calendar: workdayCalendar
)
check(abs(calendarWorkweekWednesday - 50) < 0.001,
      "Calendar workweek is halfway through on Wednesday noon")
let calendarWorkweekSunday = QuotaPaceCalculator.calendarWorkweekElapsedPercent(
    now: workdayCalendar.date(from: DateComponents(
        year: 2026, month: 8, day: 30, hour: 12
    ))!,
    calendar: workdayCalendar
)
check(abs(calendarWorkweekSunday - 100) < 0.001,
      "Calendar workweek remains complete during the weekend")
check(DashboardCopy.tokenHeadline(TokenPace(
    todayTokens: 55_600_000,
    baselineTokens: 357_700_000,
    deltaTokens: -302_100_000,
    deltaPercent: -84,
    sampleDays: 5
)) == "今天比近期同时段少用 302.1M Token（-84%）",
      "Dashboard token pace states the absolute difference first")
check(DashboardCopy.cycleComparison(deltaPercentagePoints: 2.4)
      == "额度比周期进度快 2% · 建议稍微省一点",
      "Dashboard compares quota with its matching cycle")
check(DashboardCopy.cycleComparison(deltaPercentagePoints: 12)
      == "额度比周期进度快 12% · 建议大幅节省",
      "Dashboard warns when cycle overuse is large")
check(DashboardCopy.cycleComparison(deltaPercentagePoints: -4)
      == "额度比周期进度慢 4% · 目前小额富余",
      "Dashboard identifies a small cycle surplus")
check(DashboardCopy.cycleComparison(deltaPercentagePoints: -12)
      == "额度比周期进度慢 12% · 目前大额富余",
      "Dashboard identifies a large cycle surplus")
check(DashboardCopy.cycleComparison(deltaPercentagePoints: 0.8)
      == "额度与周期进度基本匹配",
      "Dashboard avoids advice for rounding noise")

let tokenPace = TokenPaceCalculator.calculate(
    todayTokens: 12_800_000,
    comparisonTokens: [10_000_000, 11_000_000, 10_500_000, 10_900_000,
                       10_300_000, 10_700_000, 10_800_000]
)
check(tokenPace?.baselineTokens == 10_600_000, "Token pace baseline")
check(tokenPace?.deltaTokens == 2_200_000, "Token pace absolute delta")
check(tokenPace?.deltaPercent.rounded() == 21, "Token pace relative delta")
check(TokenPaceCalculator.calculate(todayTokens: 1_000, comparisonTokens: [900, 1_100]) == nil,
      "Token pace requires three days")

let now = Date(timeIntervalSince1970: 1_000_000)
let fixedWindow = QuotaWindow(
    kind: .weekly,
    usedPercent: 70,
    resetAt: now.addingTimeInterval(320),
    durationSeconds: 1_000,
    resetMode: .fixedCycle
)
let quotaPace = QuotaPaceCalculator.calculate(window: fixedWindow, now: now)
check(abs((quotaPace?.elapsedPercent ?? 0) - 68) < 0.001, "Quota elapsed percent")
check(abs((quotaPace?.deltaPercentagePoints ?? 0) - 2) < 0.001,
      "Quota pace uses percentage points")

let rollingWindow = QuotaWindow(
    kind: .session,
    usedPercent: 20,
    resetAt: now.addingTimeInterval(600),
    durationSeconds: 18_000,
    resetMode: .rollingRecovery
)
check(QuotaPaceCalculator.calculate(window: rollingWindow, now: now) == nil,
      "Rolling window does not invent pace")

let codexTokenLine = Data(#"{"timestamp":"2026-08-25T01:28:37.639Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":129047,"cached_input_tokens":117632,"output_tokens":262,"reasoning_output_tokens":23,"total_tokens":129309}}}}"#.utf8)
do {
    let event = try CodexTokenEventParser.parse(data: codexTokenLine)
    check(event.timestamp.timeIntervalSince1970 > 0,
          "Codex token parser accepts fractional ISO8601 timestamp")
    check(event.breakdown.input == 11_415, "Codex token parser separates uncached input")
    check(event.breakdown.cachedInput == 117_632, "Codex token parser keeps cached input")
    check(event.breakdown.output == 262, "Codex token parser does not double count reasoning")
    check(event.total == 129_309, "Codex token parser respects provider total")
} catch {
    failures += 1
    fputs("FAIL Codex token parser: \(error)\n", stderr)
}

var utcCalendar = Calendar(identifier: .gregorian)
utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
func utcDate(_ day: Int, _ hour: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
}
let tokenSummary = CodexTokenAggregator.summarize(
    events: [
        CodexTokenEvent(timestamp: utcDate(25, 8), breakdown: TokenBreakdown(input: 600, cachedInput: 300, output: 100), total: 1_000),
        CodexTokenEvent(timestamp: utcDate(25, 9), breakdown: TokenBreakdown(input: 300, cachedInput: 100, output: 100), total: 500),
        CodexTokenEvent(timestamp: utcDate(24, 9), breakdown: TokenBreakdown(), total: 1_000),
        CodexTokenEvent(timestamp: utcDate(23, 9), breakdown: TokenBreakdown(), total: 1_200),
        CodexTokenEvent(timestamp: utcDate(22, 9), breakdown: TokenBreakdown(), total: 800),
        CodexTokenEvent(timestamp: utcDate(24, 11), breakdown: TokenBreakdown(), total: 9_000)
    ],
    now: utcDate(25, 10),
    calendar: utcCalendar
)
check(tokenSummary?.breakdown.total == 1_500, "Codex token summary totals today's events")
check(tokenSummary?.pace?.baselineTokens == 1_000,
      "Codex token pace compares the same time of day")
check(tokenSummary?.pace?.deltaTokens == 500, "Codex token pace explains absolute overuse")

let glmData = Data(#"""
{
  "code": 200,
  "data": {"level":"pro","limits":[
    {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":36,"nextResetTime":1780602733798},
    {"type":"CREDIT_LIMIT","unit":6,"number":1,"percentage":24,"nextResetTime":1780970446997}
  ]},
  "success": true
}
"""#.utf8)
do {
    let snapshot = try GLMQuotaParser.parse(
        data: glmData,
        now: Date(timeIntervalSince1970: 1_780_000_000)
    )
    check(snapshot.planName == "PRO", "GLM plan name")
    check(snapshot.windows.map(\.kind) == [.session, .weekly], "GLM window classification")
    check(snapshot.windows.map(\.remainingPercent) == [64, 76], "GLM remaining percent")
} catch {
    failures += 1
    fputs("FAIL GLM parser: \(error)\n", stderr)
}

if failures > 0 {
    exit(EXIT_FAILURE)
}
