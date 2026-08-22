import Foundation

struct QianwenOfficeScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let tokenResponseCount: Int
    let errorCount: Int
    let hasSessionFiles: Bool
    let latestModel: String?
    let unpricedModels: [String]
}

private struct QianwenOfficeEvent {
    let key: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let tokens: TokenBreakdown
}

private struct QianwenOfficeCachedEvent: Codable {
    let key: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let reasoning: Double
    let total: Double

    init(_ event: QianwenOfficeEvent) {
        key = event.key
        timestamp = event.timestamp
        sessionID = event.sessionID
        model = event.model
        input = event.tokens.input
        output = event.tokens.output
        cacheRead = event.tokens.cacheRead
        cacheWrite = event.tokens.cacheWrite
        reasoning = event.tokens.reasoning
        total = event.tokens.total
    }

    var event: QianwenOfficeEvent {
        QianwenOfficeEvent(
            key: key,
            timestamp: timestamp,
            sessionID: sessionID,
            model: model,
            tokens: TokenBreakdown(
                input: input,
                output: output,
                total: total,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                reasoning: reasoning
            )
        )
    }
}

private struct QianwenOfficeFileEntry: Codable {
    let size: Int64
    let modifiedAt: Double
    let events: [QianwenOfficeCachedEvent]
    let errorCount: Int
}

private struct QianwenOfficeScanCache: Codable {
    let version: Int
    let files: [String: QianwenOfficeFileEntry]
}

enum QianwenOfficeUsageScanner {
    private static let cacheVersion = 2
    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("qianwen-office-scan-cache.json")
    private static let maximumRelevantLineBytes = 4 * 1024 * 1024

    static func scan() -> QianwenOfficeScanResult {
        let files = sessionFiles()
        let previous = loadCache()
        var current: [String: QianwenOfficeFileEntry] = [:]
        var cacheDirty = previous == nil

        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let key = url.resolvingSymlinksInPath().standardizedFileURL.path

            if let cached = previous?.files[key],
               cached.size == size,
               cached.modifiedAt == modifiedAt {
                current[key] = cached
            } else {
                current[key] = parseFile(at: url, size: size, modifiedAt: modifiedAt)
                cacheDirty = true
            }
        }

        if let previous, Set(previous.files.keys) != Set(current.keys) {
            cacheDirty = true
        }
        if cacheDirty {
            saveCache(QianwenOfficeScanCache(version: cacheVersion, files: current))
        }

        var uniqueEvents: [String: QianwenOfficeEvent] = [:]
        var errorCount = 0
        for entry in current.values {
            errorCount += entry.errorCount
            for cachedEvent in entry.events {
                let event = cachedEvent.event
                if let existing = uniqueEvents[event.key] {
                    if eventScore(event) > eventScore(existing) {
                        uniqueEvents[event.key] = event
                    }
                } else {
                    uniqueEvents[event.key] = event
                }
            }
        }

        let events = uniqueEvents.values.sorted { $0.timestamp < $1.timestamp }
        var summary = LocalUsageSummary()
        var unpricedModels: Set<String> = []
        for event in events {
            // Keep this as request count rather than session count. The UI can
            // then show the number of provider responses in the badge while
            // the model section still exposes the same response count.
            let cost = estimatedCost(for: event)
            if event.tokens.hasTokens, cost == nil {
                unpricedModels.insert(event.model)
            }
            summary.add(
                date: event.timestamp,
                tokens: event.tokens,
                requests: 1,
                cost: cost ?? 0,
                model: event.model
            )
        }

        return QianwenOfficeScanResult(
            summary: summary,
            responseCount: events.count,
            tokenResponseCount: events.filter { $0.tokens.hasTokens }.count,
            errorCount: errorCount,
            hasSessionFiles: !files.isEmpty,
            latestModel: events.last?.model,
            unpricedModels: unpricedModels.sorted()
        )
    }

    private static func estimatedCost(for event: QianwenOfficeEvent) -> Double? {
        guard event.tokens.hasTokens else { return nil }

        // Qianwen's provider record stores uncached input and cache reads in
        // separate fields. CodexPricing expects total input, so combine them
        // only for the estimator; cache reads are then charged at cache price
        // and are not counted again as normal input.
        let totalInput = event.tokens.input + event.tokens.cacheRead + event.tokens.cacheWrite
        return CodexPricing.estimatedCost(
            model: event.model,
            inputTokens: totalInput,
            cachedInputTokens: event.tokens.cacheRead,
            outputTokens: event.tokens.output,
            cacheWriteTokens: event.tokens.cacheWrite
        )
    }

    private static func eventScore(_ event: QianwenOfficeEvent) -> (Int, Double) {
        (event.tokens.hasTokens ? 1 : 0, event.timestamp.timeIntervalSince1970)
    }

    private static func sessionFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: AppPaths.qianwenAgentRoot.path),
              let enumerator = FileManager.default.enumerator(
                at: AppPaths.qianwenAgentRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
              ) else {
            return []
        }

        var files: [URL] = []
        var seen: Set<String> = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "thread-events.jsonl" else { continue }
            let normalized = url.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(normalized.path).inserted else { continue }
            files.append(normalized)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func sessionID(for url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent
    }

    private static func parseFile(at url: URL, size: Int64, modifiedAt: Double) -> QianwenOfficeFileEntry {
        let fallbackSessionID = sessionID(for: url)
        let fallbackDate = Date(timeIntervalSince1970: modifiedAt)
        var events: [QianwenOfficeCachedEvent] = []
        var errorCount = 0

        forEachLine(at: url) { line in
            guard !line.isEmpty else { return }
            guard let object = LocalData.parseJSON(data: line) as? [String: Any] else {
                errorCount += 1
                return
            }
            guard LocalData.string(object["type"]) == "canonical_item",
                  LocalData.string(object["turnId"] ?? object["turn_id"])?.hasPrefix("workbench_") == true,
                  let payload = object["payload"] as? [String: Any],
                  let item = payload["item"] as? [String: Any],
                  LocalData.string(item["kind"]) == "usage",
                  LocalData.string(item["usageSource"] ?? item["usage_source"]) == "provider",
                  let usage = item["usage"] as? [String: Any] else {
                return
            }

            let input = nonNegativeNumber(usage["input_tokens"])
            let output = nonNegativeNumber(usage["output_tokens"])
            let cacheRead = nonNegativeNumber(usage["cache_read_input_tokens"])
            let cacheWrite = firstNonZeroNumber(
                usage["cache_write_input_tokens"],
                usage["cache_creation_input_tokens"]
            )
            let reasoning = nonNegativeNumber(usage["reasoning_tokens"])
            let componentTotal = input + output + cacheRead + cacheWrite + reasoning
            let reportedTotal = nonNegativeNumber(usage["total_tokens"])
            let total = componentTotal > 0 ? componentTotal : reportedTotal

            let timestamp = LocalData.date(
                object["timestamp"]
                    ?? object["ts"]
                    ?? item["timestamp"]
                    ?? item["createdAt"]
                    ?? item["created_at"]
            ) ?? fallbackDate
            let sessionID = LocalData.string(object["threadId"] ?? object["thread_id"])
                ?? fallbackSessionID
            let itemID = LocalData.string(item["id"])
                ?? LocalData.string(object["eventId"] ?? object["event_id"])
                ?? "line-\(events.count)"
            let model = LocalData.string(item["model"])
                ?? LocalData.string(usage["model"])
                ?? "未知"
            let event = QianwenOfficeEvent(
                key: "\(sessionID)|\(itemID)",
                timestamp: timestamp,
                sessionID: sessionID,
                model: model,
                tokens: TokenBreakdown(
                    input: input,
                    output: output,
                    total: total,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    reasoning: reasoning
                )
            )
            events.append(QianwenOfficeCachedEvent(event))
        }

        return QianwenOfficeFileEntry(
            size: size,
            modifiedAt: modifiedAt,
            events: events,
            errorCount: errorCount
        )
    }

    private static func nonNegativeNumber(_ value: Any?) -> Double {
        guard let number = LocalData.number(value), number.isFinite else { return 0 }
        return max(number, 0)
    }

    private static func firstNonZeroNumber(_ first: Any?, _ second: Any?) -> Double {
        let firstValue = nonNegativeNumber(first)
        return firstValue > 0 ? firstValue : nonNegativeNumber(second)
    }

    private static func loadCache() -> QianwenOfficeScanCache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(QianwenOfficeScanCache.self, from: data),
              cache.version == cacheVersion else {
            return nil
        }
        return cache
    }

    private static func saveCache(_ cache: QianwenOfficeScanCache) {
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(cache).write(to: cacheURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch {
            // The optional cache must never prevent local usage from loading.
        }
    }

    private static func forEachLine(at url: URL, body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk: Data
            do {
                guard let next = try handle.read(upToCount: 64 * 1024), !next.isEmpty else { break }
                chunk = next
            } catch {
                break
            }
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while lineStart < buffer.endIndex,
                  let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                if newline - lineStart <= maximumRelevantLineBytes {
                    body(Data(buffer[lineStart..<newline]))
                }
                lineStart = newline + 1
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
            if buffer.count > maximumRelevantLineBytes {
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty, buffer.count <= maximumRelevantLineBytes {
            body(buffer)
        }
    }
}
