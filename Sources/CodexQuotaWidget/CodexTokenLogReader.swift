import Foundation
#if SWIFT_PACKAGE
import QuotaCore
#endif

struct CodexTokenResult {
    let breakdown: TokenBreakdown
    let pace: TokenPace?
}

enum CodexTokenLogReader {
    private struct FileCache {
        var offset: UInt64 = 0
        var remainder = Data()
        var events: [CodexTokenEvent] = []
    }

    private static let cacheLock = NSLock()
    private static var fileCache: [String: FileCache] = [:]
    private static let tokenMarker = Data(#""type":"token_count""#.utf8)

    static func read(now: Date, fileManager: FileManager = .default) -> CodexTokenResult? {
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
                fileCache[path] = cached
                events.append(contentsOf: cached.events)
            }
        }
        fileCache = fileCache.filter { seenPaths.contains($0.key) }
        guard !events.isEmpty else { return nil }

        guard let summary = CodexTokenAggregator.summarize(events: events, now: now) else {
            return nil
        }
        return CodexTokenResult(
            breakdown: summary.breakdown,
            pace: summary.pace
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
                if line.range(of: tokenMarker) != nil,
                   let event = try? CodexTokenEventParser.parse(data: line) {
                    cached.events.append(event)
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
        let events = data.split(separator: 0x0A).compactMap {
            try? CodexTokenEventParser.parse(data: Data($0))
        }
        return FileCache(offset: size, remainder: Data(), events: events)
    }
}
