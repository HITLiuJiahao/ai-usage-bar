import Foundation

struct QwenWorkScanResult {
    let summary: LocalUsageSummary
    let activeMinutesByWindow: [String: Double]
    let responseCount: Int
    let tokenResponseCount: Int
    let errorCount: Int
    let hasLogFiles: Bool
    let latestModel: String?

    func activeMinutes(for window: UsageWindow) -> Double {
        activeMinutesByWindow[window.rawValue] ?? 0
    }
}

private struct QwenWorkEvent {
    let key: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let tokens: TokenBreakdown?
    let cost: Double
}

private struct QwenWorkCachedEvent: Codable {
    let key: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let hasTokens: Bool
    let cost: Double

    init(_ event: QwenWorkEvent) {
        self.key = event.key
        self.timestamp = event.timestamp
        self.sessionID = event.sessionID
        self.model = event.model
        self.input = event.tokens?.input ?? 0
        self.output = event.tokens?.output ?? 0
        self.cacheRead = event.tokens?.cacheRead ?? 0
        self.cacheWrite = event.tokens?.cacheWrite ?? 0
        self.hasTokens = event.tokens?.hasTokens ?? false
        self.cost = event.cost
    }

    var event: QwenWorkEvent {
        QwenWorkEvent(
            key: key,
            timestamp: timestamp,
            sessionID: sessionID,
            model: model,
            tokens: hasTokens
                ? TokenBreakdown(
                    input: input,
                    output: output,
                    total: input + output + cacheRead + cacheWrite,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite
                )
                : nil,
            cost: cost
        )
    }
}

private struct QwenWorkFileEntry: Codable {
    let size: Int64
    let modifiedAt: Double
    let events: [QwenWorkCachedEvent]
    let errorCount: Int
}

private struct QwenWorkScanCache: Codable {
    let version: Int
    let files: [String: QwenWorkFileEntry]
}

enum QwenWorkUsageScanner {
    private static let cacheVersion = 3
    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("qwenwork-scan-cache.json")
    private static let responseMarker = Data("\"model.response.completed\"".utf8)
    private static let failureMarker = Data("\"model.request.attempt_failed\"".utf8)
    private static let configMarker = Data("\"session.config.loaded\"".utf8)
    private static let assistantMarker = Data("\"assistant\"".utf8)
    private static let runtimeConfigMarker = Data("\"runtime-config\"".utf8)
    private static let errorMarker = Data("\"error\"".utf8)
    private static let maximumRelevantLineBytes = 2 * 1024 * 1024

    static func scan() -> QwenWorkScanResult {
        let files = logFiles()
        let previous = loadCache()
        var current: [String: QwenWorkFileEntry] = [:]
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
            saveCache(QwenWorkScanCache(version: cacheVersion, files: current))
        }

        var uniqueEvents: [String: QwenWorkEvent] = [:]
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
        var tokenResponseCount = 0
        for event in events {
            if event.tokens?.hasTokens == true {
                tokenResponseCount += 1
            }
            summary.add(
                date: event.timestamp,
                tokens: event.tokens,
                requests: 1,
                cost: event.cost,
                model: event.model,
                sessionID: event.sessionID
            )
        }
        let latestModel = events.last?.model

        let activeMinutesByWindow = UsageWindow.activeWindows.reduce(into: [String: Double]()) { result, window in
            result[window.rawValue] = activeMinutes(events: events, window: window)
        }

        return QwenWorkScanResult(
            summary: summary,
            activeMinutesByWindow: activeMinutesByWindow,
            responseCount: events.count,
            tokenResponseCount: tokenResponseCount,
            errorCount: errorCount,
            hasLogFiles: !files.isEmpty,
            latestModel: latestModel
        )
    }

    private static func eventScore(_ event: QwenWorkEvent) -> (Int, Double) {
        let tokenScore = event.tokens?.total ?? 0
        return (tokenScore > 0 ? 1 : 0, event.timestamp.timeIntervalSince1970)
    }

    private static func logFiles() -> [URL] {
        var files: [URL] = []
        var seen: Set<String> = []
        for root in AppPaths.qwenWorkLogRoots {
            guard FileManager.default.fileExists(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsPackageDescendants]
                  ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                let normalized = url.resolvingSymlinksInPath().standardizedFileURL
                guard seen.insert(normalized.path).inserted else { continue }
                files.append(normalized)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func sessionID(for url: URL) -> String {
        let segmentsIndex = url.pathComponents.lastIndex(of: "segments")
        if let segmentsIndex, segmentsIndex > 0 {
            return url.pathComponents[segmentsIndex - 1]
        }
        return url.deletingLastPathComponent().lastPathComponent
    }

    private static func sessionID(in object: [String: Any], fallback: String) -> String {
        let keys = ["sessionId", "session_id", "sessionID"]
        for key in keys {
            if let value = LocalData.string(object[key]), !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private static func parseFile(at url: URL, size: Int64, modifiedAt: Double) -> QwenWorkFileEntry {
        let fileSessionID = sessionID(for: url)
        let fallbackDate = Date(timeIntervalSince1970: modifiedAt)
        var currentModel: String?
        var events: [QwenWorkCachedEvent] = []
        var errorCount = 0
        var lineNumber = 0

        forEachLine(at: url) { line in
            lineNumber += 1
            guard line.range(of: responseMarker) != nil
                || line.range(of: failureMarker) != nil
                || line.range(of: configMarker) != nil
                || line.range(of: assistantMarker) != nil
                || line.range(of: runtimeConfigMarker) != nil
                || line.range(of: errorMarker) != nil else { return }
            guard let object = LocalData.parseJSON(data: line) as? [String: Any],
                  let type = LocalData.string(object["type"]) else { return }

            let data = object["data"] as? [String: Any] ?? [:]
            if type == "session.config.loaded" {
                currentModel = LocalData.string(data["model"]) ?? currentModel
                return
            }
            if type == "model.request.attempt_failed" {
                errorCount += 1
                return
            }
            if type == "runtime-config" {
                currentModel = LocalData.string(object["model"])
                    ?? LocalData.string(data["model"])
                    ?? currentModel
                return
            }
            if type == "error" {
                errorCount += 1
                return
            }

            let message = object["message"] as? [String: Any]
            let isLegacyResponse = type == "model.response.completed"
            let isAssistantResponse = type == "assistant"
                || (message?["role"] as? String == "assistant"
                    && ["message", "response", "assistant"].contains(type))
            guard isLegacyResponse || isAssistantResponse else { return }

            let timestamp = LocalData.date(
                object["timestamp"]
                    ?? object["ts"]
                    ?? object["created_at"]
                    ?? message?["timestamp"]
            ) ?? fallbackDate
            let model = LocalData.string(object["model"])
                ?? LocalData.string(message?["model"])
                ?? LocalData.string(data["model"])
                ?? currentModel
                ?? "qmodel_latest"
            let eventSessionID = sessionID(in: object, fallback: fileSessionID)
            let requestID = LocalData.string(object["request_id"])
            let requestIndex = LocalData.string(data["request_index"])
            let turnID = LocalData.string(object["turn_id"])
            // A single model turn is written as several assistant records
            // (thinking, tool_use, and the final message). QwenWork reuses
            // message.id for those records; object.uuid is a per-record id.
            // Prefer message.id so the turn is counted once.
            let eventID = LocalData.string(message?["id"])
                ?? LocalData.string(object["request_id"])
                ?? LocalData.string(object["uuid"])
                ?? requestID
            let key: String
            if let eventID, !eventID.isEmpty {
                key = "\(eventSessionID)|event|\(eventID)"
            } else if let requestIndex, !requestIndex.isEmpty {
                key = "\(eventSessionID)|index|\(requestIndex)|\(turnID ?? "")"
            } else {
                key = "\(eventSessionID)|line|\(lineNumber)"
            }

            let tokens = tokenBreakdown(object: object, message: message, data: data)
            let event = QwenWorkEvent(
                key: key,
                timestamp: timestamp,
                sessionID: eventSessionID,
                model: model,
                tokens: tokens,
                cost: 0
            )
            events.append(QwenWorkCachedEvent(event))
        }

        return QwenWorkFileEntry(
            size: size,
            modifiedAt: modifiedAt,
            events: events,
            errorCount: errorCount
        )
    }

    /// QwenWork transcripts sometimes carry usageMetadata, but many releases
    /// omit it. Parse only explicit token containers; request/model counts do
    /// not turn message text into a synthetic token or price estimate.
    private static func tokenBreakdown(
        object: [String: Any],
        message: [String: Any]?,
        data: [String: Any]
    ) -> TokenBreakdown? {
        var containers: [[String: Any]] = [object, data]
        if let message { containers.insert(message, at: 0) }

        let usageKeys = ["usageMetadata", "usage", "tokenUsage", "token_usage", "rawUsage", "raw_usage"]
        for container in containers {
            for key in usageKeys {
                guard let usage = container[key] as? [String: Any] else { continue }
                if let tokens = parseTokenUsage(usage) { return tokens }
            }
        }

        for container in containers {
            if let tokens = parseTokenUsage(container) { return tokens }
        }
        return nil
    }

    private static func parseTokenUsage(_ value: [String: Any]) -> TokenBreakdown? {
        let hasTokenSignal = LocalData.firstNumber(
            in: value,
            keys: [
                "inputTokens", "inputToken", "input_tokens",
                "prompt", "promptTokens", "promptTokenCount",
                "outputTokens", "outputToken", "output_tokens",
                "completionTokens", "completionToken", "candidatesTokenCount",
                "totalTokens", "totalToken", "totalTokenCount",
                "cacheReadInputTokens", "cacheReadToken", "cache_read_input_tokens",
                "cachedContentTokenCount", "cachedTokens",
                "cacheCreationInputTokens", "cacheCreationToken", "cache_creation_input_tokens",
                "cacheWriteTokens", "cacheWriteToken",
                "reasoningTokens", "reasoningOutputTokens", "thinkingTokens", "thoughts"
            ]
        )
        guard hasTokenSignal != nil else { return nil }

        let prompt = LocalData.firstNumber(
            in: value,
            keys: ["prompt", "promptTokens", "promptTokenCount"]
        )
        let directInput = LocalData.firstNumber(
            in: value,
            keys: ["inputTokens", "inputToken", "input_tokens"]
        )
        let output = LocalData.firstNumber(
            in: value,
            keys: [
                "outputTokens", "outputToken", "output_tokens",
                "completionTokens", "completionToken", "candidatesTokenCount",
                "completion"
            ]
        )
        let explicitTotal = LocalData.firstNumber(
            in: value,
            keys: ["totalTokens", "totalToken", "totalTokenCount", "total"]
        )
        let cacheRead = LocalData.firstNumber(
            in: value,
            keys: [
                "cacheReadInputTokens", "cacheReadToken", "cache_read_input_tokens",
                "cachedContentTokenCount", "cachedTokens", "cached"
            ]
        ) ?? 0
        let cacheWrite = LocalData.firstNumber(
            in: value,
            keys: [
                "cacheCreationInputTokens", "cacheCreationToken", "cache_creation_input_tokens",
                "cacheWriteTokens", "cacheWriteToken", "cachewritetokens"
            ]
        ) ?? 0
        let reasoning = LocalData.firstNumber(
            in: value,
            keys: ["reasoningTokens", "reasoningOutputTokens", "thinkingTokens", "thoughts"]
        ) ?? 0

        let normalizedCacheRead = max(cacheRead, 0)
        let input: Double
        if let prompt {
            // Qwen's prompt count includes cached content. Keep the card's
            // input field non-cached so its cache-hit ratio and cost agree
            // with the Tokei presentation.
            input = max(prompt - normalizedCacheRead, 0)
        } else {
            input = max(directInput ?? 0, 0)
        }
        let normalizedOutput: Double
        if let output {
            normalizedOutput = max(output, 0)
        } else if let explicitTotal, let prompt {
            normalizedOutput = max(explicitTotal - prompt, 0)
        } else {
            normalizedOutput = 0
        }
        let total = max(
            explicitTotal ?? (input + normalizedCacheRead + normalizedOutput + max(cacheWrite, 0)),
            0
        )
        let tokens = TokenBreakdown(
            input: input,
            output: normalizedOutput,
            total: total,
            cacheRead: normalizedCacheRead,
            cacheWrite: max(cacheWrite, 0),
            reasoning: max(reasoning, 0),
            inputIncludesCache: false
        )
        return tokens.hasTokens ? tokens : nil
    }

    private static func activeMinutes(events: [QwenWorkEvent], window: UsageWindow) -> Double {
        var timestampsBySession: [String: [Date]] = [:]
        for event in events where isInWindow(event.timestamp, window: window) {
            timestampsBySession[event.sessionID, default: []].append(event.timestamp)
        }

        var activeSeconds: Double = 0
        for timestamps in timestampsBySession.values {
            let sorted = timestamps.sorted()
            for pair in zip(sorted, sorted.dropFirst()) {
                let gap = pair.1.timeIntervalSince(pair.0)
                if gap > 0 {
                    activeSeconds += min(gap, 5 * 60)
                }
            }
        }
        return (activeSeconds / 60).rounded()
    }

    private static func isInWindow(_ date: Date, window: UsageWindow) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        let week = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        let month = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? startOfDay
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: month) ?? month
        let year = calendar.date(
            from: calendar.dateComponents([.year], from: now)
        ) ?? month

        switch window {
        case .today: return date >= startOfDay && date < tomorrow
        case .yesterday: return date >= yesterday && date < startOfDay
        case .weekly: return date >= week && date < tomorrow
        case .lastWeek: return date >= lastWeek && date < week
        case .monthly: return date >= month && date < tomorrow
        case .lastMonth: return date >= lastMonth && date < month
        case .yearly: return date >= year && date < tomorrow
        case .fiveHours, .daily, .billing: return false
        }
    }

    private static func loadCache() -> QwenWorkScanCache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(QwenWorkScanCache.self, from: data),
              cache.version == cacheVersion else { return nil }
        return cache
    }

    static func localAccountName() -> String? {
        guard let status = LocalData.loadJSON(at: AppPaths.qwenStatusSnapshot) else { return nil }
        return LocalData.firstString(
            in: status,
            keys: Set(["username", "name", "email", "nickname"])
        )
    }

    private static func saveCache(_ cache: QwenWorkScanCache) {
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
        if !buffer.isEmpty, buffer.count <= maximumRelevantLineBytes { body(buffer) }
    }
}

private extension UsageWindow {
    static let activeWindows: [UsageWindow] = [.today, .yesterday, .weekly, .lastWeek, .monthly, .lastMonth, .yearly]
}

enum QwenWorkUsageMetrics {
    static func make(
        summary: LocalUsageSummary,
        scan: QwenWorkScanResult
    ) -> [UsageMetric] {
        let buckets: [(UsageWindow, UsageBucket)] = [
            (.today, summary.today),
            (.yesterday, summary.yesterday),
            (.weekly, summary.thisWeek),
            (.lastWeek, summary.lastWeek),
            (.monthly, summary.month),
            (.lastMonth, summary.lastMonth),
            (.yearly, summary.year)
        ]
        var metrics: [UsageMetric] = []
        for (window, bucket) in buckets {
            if bucket.tokens.hasTokens {
                metrics.append(UsageMetric(
                    key: "qwenwork-tokens-\(window.rawValue)",
                    title: "Token",
                    kind: .tokens,
                    window: window,
                    used: bucket.tokens.total,
                    limit: nil,
                    remaining: nil,
                    unit: "tokens",
                    source: .local,
                    resetAt: nil,
                    note: "按 QwenWorkCN 会话 JSONL 的 usage / usageMetadata 汇总",
                    inputTokens: bucket.tokens.input,
                    outputTokens: bucket.tokens.output,
                    cacheReadTokens: bucket.tokens.cacheRead,
                    cacheWriteTokens: bucket.tokens.cacheWrite,
                    reasoningTokens: bucket.tokens.reasoning
                ))
            }
            if bucket.requests > 0 {
                metrics.append(UsageMetric(
                    key: "qwenwork-requests-\(window.rawValue)",
                    title: "请求次数",
                    kind: .requests,
                    window: window,
                    used: bucket.requests,
                    limit: nil,
                    remaining: nil,
                    unit: "次",
                    source: .local,
                    resetAt: nil,
                    note: "按去重后的 assistant 响应记录计数，兼容旧版 response 事件"
                ))
            }
            if !bucket.sessions.isEmpty {
                metrics.append(UsageMetric(
                    key: "qwenwork-sessions-\(window.rawValue)",
                    title: "会话数",
                    kind: .requests,
                    window: window,
                    used: Double(bucket.sessions.count),
                    limit: nil,
                    remaining: nil,
                    unit: "个",
                    source: .local,
                    resetAt: nil,
                    note: "按 JSONL 中的 sessionId 与会话文件去重"
                ))
            }
            let active = scan.activeMinutes(for: window)
            if active > 0 {
                metrics.append(UsageMetric(
                    key: "qwenwork-active-\(window.rawValue)",
                    title: "活跃时长",
                    kind: .duration,
                    window: window,
                    used: active,
                    limit: nil,
                    remaining: nil,
                    unit: "分钟",
                    source: .local,
                    resetAt: nil,
                    note: "相邻请求间隔最多按 5 分钟累计"
                ))
            }
        }
        return metrics
    }
}
