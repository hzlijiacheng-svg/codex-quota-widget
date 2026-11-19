import Foundation
#if SWIFT_PACKAGE
import QuotaCore
#endif

struct CodexTokenResult {
    let breakdown: TokenBreakdown?
    let pace: TokenPace?
    let quotaPoints: [QuotaTrendPoint]
}

enum CodexTokenLogReader {
    private struct FileCache {
        var offset: UInt64 = 0
        var remainder = Data()
        var events: [CodexTokenEvent] = []
        var accountIdentity: String?
        var quotaEvents: [CodexQuotaLogEvent] = []
    }

    private static let cacheLock = NSLock()
    private static var fileCache: [String: FileCache] = [:]
    private static let tokenMarker = Data(#""type":"token_count""#.utf8)

    static func read(now: Date, historyIdentity: String?, window: QuotaWindow?,
                     fileManager: FileManager = .default) -> CodexTokenResult? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            ProcessInfo.processInfo.environment["CODEX_HOME"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("sessions")
            },
            home.appendingPathComponent(".codex/sessions"),
            home.appendingPathComponent(".codex/browser/sessions"),
            home.appendingPathComponent("Library/Application Support/Codex/sessions"),
            home.appendingPathComponent("Library/Application Support/com.openai.codex/sessions")
        ].compactMap { $0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -8, to: now) ?? .distantPast
        var events: [CodexTokenEvent] = []
        var quotaPoints: [QuotaTrendPoint] = []
        var seenPaths = Set<String>()
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                let path = file.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = values?.contentModificationDate, modified < cutoff { continue }
                var cached = fileCache[path] ?? FileCache()
                cached = scan(file: file, cached: cached)
                cached.events.removeAll { $0.timestamp < cutoff }
                cached.quotaEvents.removeAll { $0.point.at < cutoff }
                fileCache[path] = cached
                events.append(contentsOf: cached.events)
                if let historyIdentity, let window, cached.accountIdentity == historyIdentity {
                    quotaPoints.append(contentsOf: cached.quotaEvents.filter { $0.matches(window) }.map(\.point))
                }
            }
        }
        fileCache = fileCache.filter { seenPaths.contains($0.key) }
        let summary = CodexTokenAggregator.summarize(events: events, now: now)
        guard summary != nil || !quotaPoints.isEmpty else { return nil }
        return CodexTokenResult(
            breakdown: summary?.breakdown,
            pace: summary?.pace,
            quotaPoints: QuotaTrendCalculator.compactActualPoints(quotaPoints)
        )
    }

    private static func scan(file: URL, cached original: FileCache) -> FileCache {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return original }
        var cached = original
        if size < cached.offset { cached = FileCache() }
        if cached.offset == 0, cached.events.isEmpty {
            return initialScan(file: file, size: size)
        }
        guard size > cached.offset,
              let handle = try? FileHandle(forReadingFrom: file) else { return cached }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: cached.offset) }
        catch { return cached }

        var buffer = cached.remainder
        while true {
            guard let chunk = try? handle.read(upToCount: 256 * 1024),
                  !chunk.isEmpty else { break }
            buffer.append(chunk)
            var consumed = buffer.startIndex
            while let newline = buffer[consumed...].firstIndex(of: 0x0A) {
                let line = Data(buffer[consumed..<newline])
                if line.range(of: tokenMarker) != nil {
                    if let event = try? CodexTokenEventParser.parse(data: line) { cached.events.append(event) }
                    if cached.accountIdentity != nil, let event = CodexQuotaLogParser.event(line) {
                        cached.quotaEvents.append(event)
                    }
                }
                consumed = buffer.index(after: newline)
            }
            if consumed > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<consumed)
            }
        }
        cached.offset = size
        cached.remainder = buffer
        return cached
    }

    private static func initialScan(file: URL, size: UInt64) -> FileCache {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-F", #""type":"token_count""#, file.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() }
        catch { return FileCache() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return FileCache()
        }
        let identity = readAccountIdentity(file)
        var cached = FileCache(offset: size, remainder: Data(), accountIdentity: identity)
        for line in data.split(separator: 0x0A) {
            let eventData = Data(line)
            if let event = try? CodexTokenEventParser.parse(data: eventData) { cached.events.append(event) }
            if identity != nil, let event = CodexQuotaLogParser.event(eventData) {
                cached.quotaEvents.append(event)
            }
        }
        return cached
    }

    private static func readAccountIdentity(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while line.count < 2 * 1024 * 1024,
              let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: 0x0A) {
                line.append(chunk[..<newline])
                return CodexQuotaLogParser.accountIdentity(line)
            }
            line.append(chunk)
        }
        return nil
    }
}
