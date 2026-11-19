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
    now: touchBarNow,
    calendar: touchBarCalendar
)
check(touchBarPresentation?.title == "Codex 周额度", "Touch Bar uses an explicit title")
check(touchBarPresentation?.remaining == "79%", "Touch Bar emphasizes remaining quota")
check(touchBarPresentation?.used == "已用 21%", "Touch Bar explains current usage")
check(touchBarPresentation?.reset == "5天12小时后重置", "Touch Bar explains the reset cycle")
check(touchBarPresentation?.pace == "偏慢 0.70×", "Touch Bar uses the same workday speed as the dashboard")

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
      "Workday pace counts only full local weekdays")
check(abs((workdayPace?.deltaPercentagePoints ?? 0) - 10) < 0.001,
      "Workday pace compares quota usage with weekday progress")
let workdayBudget = QuotaPaceCalculator.workdayBudget(
    window: workdayWindow, now: workdayNow, calendar: workdayCalendar
)
check(abs((workdayBudget?.elapsedWorkdays ?? 0) - 2.5) < 0.001,
      "Budget counts elapsed workdays within the actual quota cycle")
check(abs((workdayBudget?.remainingWorkdays ?? 0) - 2.5) < 0.001,
      "Budget excludes weekend from the remaining workdays")
check(abs((workdayBudget?.speedIndex ?? 0) - 1.2) < 0.001,
      "Speed compares average consumption with an even workday budget")
check(abs((workdayBudget?.dailyBudgetPercent ?? 0) - 16) < 0.001,
      "Daily budget divides remaining quota over remaining workdays")
check(WorkdaySpeed.classify(0.79) == .slow, "Speed below the target range is slow")
check(WorkdaySpeed.classify(1.0) == .balanced, "Speed matching the target is balanced")
check(WorkdaySpeed.classify(1.21) == .fast, "Speed above the target range is fast")
check(WorkdaySpeed.classify(0.799) == .balanced && WorkdaySpeed.classify(1.204) == .balanced,
      "Speed labels agree with the displayed two-decimal ratio")
let justStarted = QuotaPaceCalculator.workdayBudget(
    window: workdayWindow, now: workdayStart.addingTimeInterval(3600),
    calendar: workdayCalendar
)
check(justStarted?.speedIndex == nil, "Speed waits for enough elapsed work time")
let weekendBudget = QuotaPaceCalculator.workdayBudget(
    window: workdayWindow,
    now: workdayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 12))!,
    calendar: workdayCalendar
)
check(abs((weekendBudget?.elapsedPercent ?? 0) - 100) < 0.001,
      "Weekend does not advance the quota's workday clock")
check(weekendBudget?.dailyBudgetPercent == nil,
      "Daily budget is unavailable when no workdays remain before reset")
let partialWindow = QuotaWindow(
    kind: .weekly, usedPercent: 40,
    resetAt: workdayCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!,
    durationSeconds: 7 * 24 * 60 * 60, resetMode: .fixedCycle
)
let partialBudget = QuotaPaceCalculator.workdayBudget(
    window: partialWindow,
    now: workdayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!,
    calendar: workdayCalendar
)
check(abs((partialBudget?.elapsedWorkdays ?? 0) - 4) < 0.001,
      "Cycles starting midday retain the partial first workday")
check(abs((partialBudget?.remainingWorkdays ?? 0) - 1) < 0.001,
      "Cycles resetting midday retain the partial final workday")
let calendarWorkweekWednesday = QuotaPaceCalculator.calendarWorkweekElapsedPercent(
    now: workdayNow, calendar: workdayCalendar
)
check(abs(calendarWorkweekWednesday - 50) < 0.001,
      "Calendar workweek uses working hours on Wednesday noon")
let calendarWorkweekSunday = QuotaPaceCalculator.calendarWorkweekElapsedPercent(
    now: workdayCalendar.date(from: DateComponents(
        year: 2026, month: 8, day: 30, hour: 12
    ))!,
    calendar: workdayCalendar
)
check(abs(calendarWorkweekSunday - 100) < 0.001,
      "Calendar workweek remains complete during the weekend")
func weekdayDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    workdayCalendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                              hour: hour, minute: minute))!
}
func progressAt(_ date: Date) -> Double {
    QuotaPaceCalculator.workdayBudget(window: workdayWindow, now: date,
                                      calendar: workdayCalendar)?.elapsedPercent ?? -1
}
check(progressAt(weekdayDate(24, 0)) == 0 && abs(progressAt(weekdayDate(24, 6)) - 5) < 0.001,
      "Weekday progress begins at local midnight")
check(abs(progressAt(weekdayDate(24, 12)) - 10) < 0.001 &&
      abs(progressAt(weekdayDate(24, 21)) - 17.5) < 0.001,
      "Weekday progress advances through lunch and the evening")
check(abs(progressAt(weekdayDate(29, 12)) - progressAt(weekdayDate(30, 12))) < 0.001,
      "Weekends do not add working time")
var shanghaiCalendar = workdayCalendar
shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
let shanghaiMonday = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 10, minute: 30))!
let shanghaiReset = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
let shanghaiWindow = QuotaWindow(kind: .weekly, usedPercent: 0, resetAt: shanghaiReset,
                                 durationSeconds: 7 * 86_400, resetMode: .fixedCycle)
let shanghaiBudget = QuotaPaceCalculator.workdayBudget(window: shanghaiWindow,
                                                        now: shanghaiMonday, calendar: shanghaiCalendar)
check(abs((shanghaiBudget?.elapsedWorkdays ?? 0) - 0.4375) < 0.001,
      "Working hours use the supplied local timezone")

let trendWindow = QuotaWindow(kind: .weekly, usedPercent: 20, resetAt: workdayEnd,
                              durationSeconds: workdayEnd.timeIntervalSince(workdayStart),
                              resetMode: .fixedCycle)
let evenBudget = QuotaTrendCalculator.evenBudgetLine(window: trendWindow, calendar: workdayCalendar) ?? []
func baselineValue(_ date: Date) -> Double? {
    QuotaTrendCalculator.remainingPercent(at: date, along: evenBudget)
}
check(evenBudget.first?.at == workdayStart && evenBudget.first?.remainingPercent == 100 &&
      evenBudget.last?.at == workdayEnd && evenBudget.last?.remainingPercent == 0,
      "Even budget covers the entire quota cycle from 100 percent to zero")
check(abs((baselineValue(weekdayDate(25, 0)) ?? -1) - 80) < 0.001 &&
      abs((baselineValue(weekdayDate(25, 6)) ?? -1) - 75) < 0.001,
      "Even budget advances through weekday nights")
check(baselineValue(weekdayDate(29, 0)) == 0 && baselineValue(weekdayDate(30, 12)) == 0,
      "Even budget remains flat throughout the weekend")
let sameCycleDifferentUsage = QuotaTrendCalculator.evenBudgetLine(window: workdayWindow, calendar: workdayCalendar)
check(sameCycleDifferentUsage == evenBudget,
      "Even budget is independent of actual consumption")
let personalStart = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10, minute: 41))!
let personalReset = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10, minute: 41))!
let personalWindow = QuotaWindow(kind: .weekly, usedPercent: 42, resetAt: personalReset,
                                 durationSeconds: personalReset.timeIntervalSince(personalStart),
                                 resetMode: .fixedCycle)
let personalBudget = QuotaTrendCalculator.evenBudgetLine(window: personalWindow, calendar: shanghaiCalendar) ?? []
func november(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    shanghaiCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
func personalBaseline(_ date: Date) -> Double {
    QuotaTrendCalculator.remainingPercent(at: date, along: personalBudget) ?? -1
}
check(abs(personalBaseline(november(17, 0)) - 88.902778) < 0.001 &&
      abs(personalBaseline(november(19, 16)) - 35.569444) < 0.001,
      "A local mid-day cycle advances through the night and preserves partial weekdays")
check(abs(personalBaseline(november(21, 0)) - 8.902778) < 0.001 &&
      personalBaseline(november(21, 0)) == personalBaseline(november(23, 0)) &&
      personalBaseline(personalReset) == 0,
      "The budget is level all weekend and resumes Monday at midnight")
let weekendReadings = [QuotaTrendPoint(at: november(21, 0), remainingPercent: 24),
                       QuotaTrendPoint(at: november(22, 22), remainingPercent: 17)]
let weekendDifferences = QuotaTrendCalculator.budgetBands(actual: weekendReadings, baseline: personalBudget)
check(weekendDifferences.first?.start.actual == 24 && weekendDifferences.last?.end.actual == 17 &&
      weekendDifferences.first?.start.budget == weekendDifferences.last?.end.budget &&
      abs((weekendDifferences.first?.start.difference ?? 0) -
          (weekendDifferences.last?.end.difference ?? 0) - 7) < 0.001,
      "Weekend usage changes both actual and difference by seven points while the budget stays flat")
let ribbonStart = weekdayDate(24, 9, 30)
let ribbonClose = weekdayDate(24, 18, 30)
let ribbonEnd = weekdayDate(25, 9, 30)
let ribbonBaseline = [
    QuotaTrendPoint(at: ribbonStart, remainingPercent: 100),
    QuotaTrendPoint(at: ribbonClose, remainingPercent: 80),
    QuotaTrendPoint(at: ribbonEnd, remainingPercent: 80),
    QuotaTrendPoint(at: weekdayDate(25, 18, 30), remainingPercent: 60)
]
let ribbonActual = [QuotaTrendPoint(at: ribbonStart, remainingPercent: 90),
                    QuotaTrendPoint(at: ribbonEnd, remainingPercent: 90)]
let ribbons = QuotaTrendCalculator.budgetBands(actual: ribbonActual, baseline: ribbonBaseline)
check(ribbons.map(\.isSurplus) == [false, true, true] &&
      ribbons.first?.end.at == weekdayDate(24, 14) && ribbons.last?.end.at == ribbonEnd,
      "Budget shading splits at the real crossing and stops at the last reading")
check(ribbons.last?.start.at == ribbonClose && ribbons.last?.start.budget == 80 &&
      ribbons.last?.end.budget == 80,
      "The difference band follows a flat budget segment")
let weekendOnly = QuotaWindow(kind: .weekly, usedPercent: 10, resetAt: weekdayDate(30, 12),
                              durationSeconds: 24 * 3600, resetMode: .fixedCycle)
check(QuotaTrendCalculator.evenBudgetLine(window: weekendOnly, calendar: workdayCalendar) == nil,
      "No even budget is invented for a cycle without working time")
let projection = QuotaTrendCalculator.forecast(window: trendWindow, now: workdayNow,
                                               calendar: workdayCalendar)
check(abs((projection?.remainingAtReset ?? -1) - 60) < 0.001,
      "Trend projects the current cycle average across remaining working hours")
let fasterWindow = QuotaWindow(kind: .weekly, usedPercent: 40, resetAt: workdayEnd,
                               durationSeconds: trendWindow.durationSeconds, resetMode: .fixedCycle)
let fasterProjection = QuotaTrendCalculator.forecast(window: fasterWindow, now: workdayNow,
                                                     calendar: workdayCalendar)
check(abs((fasterProjection?.remainingAtReset ?? -1) - 20) < 0.001,
      "The reset forecast continues to respond to actual consumption")
let exhaustedProjection = QuotaTrendCalculator.forecast(window: workdayWindow, now: workdayNow,
                                                        calendar: workdayCalendar)
check(exhaustedProjection?.remainingAtReset == 0 && exhaustedProjection?.exhaustionAt != nil &&
      exhaustedProjection!.exhaustionAt! < workdayEnd,
      "Forecast identifies quota exhaustion before reset")
check(abs((exhaustedProjection?.exhaustionAt?.timeIntervalSince(weekdayDate(28, 4)) ?? 60)) < 1,
      "Exhaustion can occur at night on a weekday")
check(QuotaTrendCalculator.forecast(window: trendWindow, now: weekdayDate(24, 1),
                                    calendar: workdayCalendar) == nil,
      "Forecast waits for meaningful working-time progress")
check(QuotaTrendCalculator.forecast(window: trendWindow, now: weekdayDate(29, 12),
                                    calendar: workdayCalendar) == nil,
      "Forecast is unavailable when no working hours remain")
let repeatedQuotaPoints = [
    QuotaTrendPoint(at: workdayNow, remainingPercent: 80),
    QuotaTrendPoint(at: workdayNow.addingTimeInterval(1), remainingPercent: 80),
    QuotaTrendPoint(at: workdayNow.addingTimeInterval(2), remainingPercent: 80),
    QuotaTrendPoint(at: workdayNow.addingTimeInterval(3), remainingPercent: 79),
    QuotaTrendPoint(at: workdayNow.addingTimeInterval(4), remainingPercent: 79)
]
check(QuotaTrendCalculator.nearestReading(to: workdayNow.addingTimeInterval(1.2), in: repeatedQuotaPoints)
      == repeatedQuotaPoints[1], "The cursor selects a real reading even on an unchanged plateau")
check(QuotaTrendCalculator.nearestReading(to: workdayNow.addingTimeInterval(2.5), in: repeatedQuotaPoints)
      == repeatedQuotaPoints[2], "An equidistant cursor selects the earlier reading")
check(QuotaTrendCalculator.nearestReading(to: workdayNow.addingTimeInterval(-100), in: repeatedQuotaPoints)
      == repeatedQuotaPoints.first && QuotaTrendCalculator.nearestReading(to: workdayNow, in: []) == nil,
      "Cursor lookup handles endpoints and missing history")
let compactQuotaPoints = QuotaTrendCalculator.compactActualPoints(repeatedQuotaPoints)
check(compactQuotaPoints.map(\.at) == [repeatedQuotaPoints[0].at, repeatedQuotaPoints[2].at,
                                       repeatedQuotaPoints[3].at, repeatedQuotaPoints[4].at],
      "Repeated readings keep the start and end of each actual quota level")

let historyDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("quota-history-test-\(UUID().uuidString)", isDirectory: true)
let historyURL = historyDirectory.appendingPathComponent("history.json")
let history = QuotaHistory(url: historyURL)
history.record(provider: .codex, identity: "account-a", window: trendWindow, at: workdayNow)
history.record(provider: .codex, identity: nil, window: trendWindow, at: workdayNow)
let restoredHistory = QuotaHistory(url: historyURL)
check(restoredHistory.points(provider: .codex, identity: "account-a", window: trendWindow,
                             at: workdayNow).count == 1,
      "Quota history survives app restart when account identity is known")
check(restoredHistory.points(provider: .codex, identity: nil, window: trendWindow,
                             at: workdayNow).isEmpty,
      "History with unknown identity is kept only in memory")
check(restoredHistory.points(provider: .codex, identity: "account-b", window: trendWindow,
                             at: workdayNow).isEmpty,
      "Quota history does not mix accounts")
let anotherCycle = QuotaWindow(kind: .weekly, usedPercent: 20,
                               resetAt: workdayEnd.addingTimeInterval(7 * 86_400),
                               durationSeconds: 7 * 86_400, resetMode: .fixedCycle)
check(restoredHistory.points(provider: .codex, identity: "account-a", window: anotherCycle,
                             at: workdayEnd).isEmpty,
      "Quota history does not mix reset cycles")
check(restoredHistory.points(provider: .codex, identity: "account-a", window: trendWindow,
                             at: workdayNow.addingTimeInterval(-1)).isEmpty,
      "Quota history does not display samples from the future")
let importedPoint = QuotaTrendPoint(at: workdayNow.addingTimeInterval(-3600), remainingPercent: 88)
history.importPoints([importedPoint, importedPoint], provider: .codex, identity: "account-a",
                     window: trendWindow, now: workdayNow)
let importedHistory = QuotaHistory(url: historyURL)
check(importedHistory.points(provider: .codex, identity: "account-a", window: trendWindow,
                             at: workdayNow).count == 2,
      "Import persists historical quota samples without duplicates")
history.importPoints([importedPoint], provider: .codex, identity: nil,
                     window: trendWindow, now: workdayNow)
check(QuotaHistory(url: historyURL).points(provider: .codex, identity: nil, window: trendWindow,
                                          at: workdayNow).isEmpty,
      "History without an account identity is never imported to disk")
try? FileManager.default.removeItem(at: historyDirectory)
let metadata = Data(#"{"type":"session_meta","payload":{"creator_account_id":"account-a"}}"#.utf8)
let otherMetadata = Data(#"{"type":"session_meta","payload":{"creator_account_id":"account-b"}}"#.utf8)
let accountHash = HistoryIdentity.hash(["codex", "account-a"])
check(CodexQuotaLogParser.accountIdentity(metadata) == accountHash &&
      CodexQuotaLogParser.accountIdentity(otherMetadata) != accountHash,
      "Session quota history is associated with the correct account")
let sampleTimestamp = Int(workdayNow.timeIntervalSince1970)
let resetTimestamp = Int(workdayEnd.timeIntervalSince1970)
let quotaEvent = Data("""
{"timestamp":"2026-08-26T12:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":35,"window_minutes":10080,"resets_at":\(resetTimestamp)}}}}
""".utf8)
let logPoint = CodexQuotaLogParser.point(quotaEvent, matching: trendWindow)
check(logPoint?.at.timeIntervalSince1970 == Double(sampleTimestamp) && logPoint?.remainingPercent == 65,
      "A matching Codex quota event yields its actual remaining percentage")
check(CodexQuotaLogParser.point(quotaEvent, matching: anotherCycle) == nil,
      "Events from a different quota cycle are ignored")
let otherLimitEvent = Data(String(data: quotaEvent, encoding: .utf8)!.replacingOccurrences(of: "\"codex\"", with: "\"other\"").utf8)
check(CodexQuotaLogParser.point(otherLimitEvent, matching: trendWindow) == nil,
      "Events for another limit are ignored")
let gatewayDayReset = weekdayDate(27, 0)
let dailyGateway = GatewayQuota(name: "test", period: "day", alignment: "calendar",
                                used: 40, limit: 100, input: nil, output: nil, cached: nil,
                                resetAt: gatewayDayReset)
let dailyGatewayWindow = dailyGateway.dailyWorkdayWindow(at: workdayNow, calendar: workdayCalendar)
check(dailyGatewayWindow?.durationSeconds == 86_400 && dailyGatewayWindow?.remainingPercent == 60,
      "Calendar-aligned gateway daily quota can use the same trend model")
let dailyEvenBudget = dailyGatewayWindow.flatMap {
    QuotaTrendCalculator.evenBudgetLine(window: $0, calendar: workdayCalendar)
} ?? []
check(dailyEvenBudget.first?.at == weekdayDate(26, 0) && dailyEvenBudget.first?.remainingPercent == 100 &&
      QuotaTrendCalculator.remainingPercent(at: weekdayDate(26, 21), along: dailyEvenBudget) == 12.5 &&
      dailyEvenBudget.last?.remainingPercent == 0,
      "Daily gateway budget advances until the following local midnight")
let unalignedGateway = GatewayQuota(name: "test", period: "day", alignment: nil,
                                    used: 40, limit: 100, input: nil, output: nil, cached: nil,
                                    resetAt: gatewayDayReset)
check(unalignedGateway.dailyWorkdayWindow(at: workdayNow, calendar: workdayCalendar) == nil,
      "Gateway trend does not assume an unverified daily cycle")
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

let gatewayRule: [String: Any] = [
    "ruleName": "configured rule", "ruleStatus": "enabled", "quotaDimension": "token",
    "periodType": "day", "windowAlignment": "calendar",
    "currentCycleResetAt": "2026-11-12T00:00:00+08:00"
]
do {
    let gateway = try GatewayQuotaParser.parse(
        rule: gatewayRule,
        usage: ["totalQuota": 350_000_000, "usedAmount": 70_000_000,
                "inputAmount": 60_000_000, "outputAmount": 10_000_000]
    )
    check(gateway.period == "day", "Gateway preserves the actual daily period")
    check(gateway.remaining == 280_000_000 && abs(gateway.remainingPercent - 80) < 0.001,
          "Gateway computes remaining quota from the server's total and used amounts")
    check(gateway.resetAt != nil, "Gateway parses the server-provided reset time")
    check(gateway.cached == nil, "Missing gateway token breakdown remains unknown")
    do {
        _ = try GatewayQuotaParser.parse(rule: gatewayRule, usage: ["totalQuota": 350_000_000])
        check(false, "Gateway must reject a response with no used amount")
    } catch {
        check(true, "Gateway rejects a response with no used amount")
    }
} catch {
    failures += 1
    fputs("FAIL Gateway parser: \(error)\n", stderr)
}

do {
    let request = try APIGRequestSigner.request(
        endpoint: "apig.cn-hangzhou.aliyuncs.com", accessKeyID: "test-id",
        accessKeySecret: "test-secret", securityToken: nil,
        action: "GetGatewayQuotaRule", path: "/v1/gateways/gw-test/quota-rules/qr-test",
        query: ["withSubjects": "true"], date: "2026-11-11T06:00:00Z",
        nonce: "0123456789abcdef0123456789abcdef"
    )
    let expected = "ACS3-HMAC-SHA256 Credential=test-id,SignedHeaders=host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-signature-nonce;x-acs-version,Signature=65518a9d60131189ae79bd3df835cada1772bbc57a3c75e8f7e43895fd704e66"
    check(request.value(forHTTPHeaderField: "Authorization") == expected,
          "Gateway request signature matches the independently generated ACS3 vector")
    check(request.url?.scheme == "https", "Gateway requests use HTTPS")
    do {
        _ = try APIGRequestSigner.request(
            endpoint: "example.invalid", accessKeyID: "test-id", accessKeySecret: "test-secret",
            securityToken: nil, action: "GetGatewayQuotaRule",
            path: "/v1/gateways/gw-test/quota-rules/qr-test", date: "2026-11-11T06:00:00Z", nonce: "test"
        )
        check(false, "Gateway signer must reject an unapproved host")
    } catch {
        check(true, "Gateway signer rejects an unapproved host")
    }
    do {
        _ = try APIGRequestSigner.request(
            endpoint: "apig.cn-hangzhou.aliyuncs.com", accessKeyID: "test-id", accessKeySecret: "test-secret",
            securityToken: nil, action: "GetGatewayQuotaRule",
            path: "/v1/gateways/gw-test/quota-rules/qr-test/subjects/cs-test/usage",
            date: "2026-11-11T06:00:00Z", nonce: "test"
        )
        check(false, "Gateway signer must reject an action and path mismatch")
    } catch {
        check(true, "Gateway signer rejects an action and path mismatch")
    }
} catch {
    failures += 1
    fputs("FAIL Gateway signature: \(error)\n", stderr)
}

if failures > 0 {
    exit(EXIT_FAILURE)
}
