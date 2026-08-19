import Foundation

/// WorkBuddy 的本地用量扫描器，按 Tokei/usageBar 的口径读取：
///
/// - 数据源：`~/.workbuddy/projects/<project>/<sessionId>.jsonl`
/// - 积分流水：`~/.workbuddy/logs/<date>/*.log` 中的
///   `AcpUsagePublisher credit consumed` 记录
/// - 统计每条包含 `providerData.rawUsage` 的模型调用记录。WorkBuddy 把
///   大多数调用写成 `type == function_call`，最后一条流式结果才可能是
///   `type == message && role == assistant`；两者都属于一次真实调用。
/// - `prompt_tokens` 是包含缓存命中的完整 prompt 总量，和 WorkBuddy
///   用量页的“输入 Token”口径一致；缓存命中单独保留用于命中率和计费。
/// - `credit` 是 WorkBuddy 自带的内部积分；金额则按模型对应的本地
///   Tokei/OpenRouter 价格表，对 Token 做独立的美元成本估算
enum WorkBuddyUsageScanner {
    // Version 4 includes function_call rawUsage records and keeps WorkBuddy's
    // inclusive prompt total in TokenBreakdown.input.
    private static let cacheVersion = 4
    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("workbuddy-scan-cache.json")

    private struct Event {
        let key: String
        let timestamp: Date
        let sessionID: String
        let model: String
        let tokens: TokenBreakdown
        let credits: Double
        let cost: Double
        let creditFromLog: Bool
    }

    private struct CachedEvent: Codable {
        let key: String
        let timestamp: Date
        let sessionID: String
        let model: String
        let input: Double
        let output: Double
        let total: Double
        let cacheRead: Double
        let cacheWrite: Double
        let reasoning: Double
        let credits: Double
        let cost: Double
        let creditFromLog: Bool

        init(_ event: Event) {
            key = event.key
            timestamp = event.timestamp
            sessionID = event.sessionID
            model = event.model
            input = event.tokens.input
            output = event.tokens.output
            total = event.tokens.total
            cacheRead = event.tokens.cacheRead
            cacheWrite = event.tokens.cacheWrite
            reasoning = event.tokens.reasoning
            credits = event.credits
            cost = event.cost
            creditFromLog = event.creditFromLog
        }

        var event: Event {
            Event(
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
                    reasoning: reasoning,
                    inputIncludesCache: true
                ),
                credits: credits,
                cost: cost,
                creditFromLog: creditFromLog
            )
        }
    }

    private struct FileEntry: Codable {
        let size: Int64
        let modifiedAt: Double
        let events: [CachedEvent]
        let sessionModels: [String: String]
    }

    private struct ScanCache: Codable {
        let version: Int
        let files: [String: FileEntry]
    }

    struct Result {
        let summary: LocalUsageSummary
        let responseCount: Int
        let hasLogFiles: Bool
        let latestModel: String?
    }

    static func scan() -> Result {
        let files = logFiles()
        let previous = loadCache()
        var current: [String: FileEntry] = [:]
        var cacheDirty = previous == nil

        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let key = url.resolvingSymlinksInPath().standardizedFileURL.path

            if let cached = previous?.files[key], cached.size == size, cached.modifiedAt == modifiedAt {
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
            saveCache(ScanCache(version: cacheVersion, files: current))
        }

        let sessionModels = current.values.reduce(into: [String: String]()) { result, entry in
            for (sessionID, model) in entry.sessionModels where !model.isEmpty {
                result[sessionID] = model
            }
        }
        let rawEvents = current.values.flatMap { $0.events.map(\.event) }
        var mergedEvents: [String: Event] = [:]
        for event in rawEvents {
            if let existing = mergedEvents[event.key] {
                mergedEvents[event.key] = merge(existing, event)
            } else {
                mergedEvents[event.key] = event
            }
        }
        let events = mergedEvents.values
            .map { event -> Event in
                let model = event.model == "未知"
                    ? (sessionModels[event.sessionID] ?? event.model)
                    : event.model
                let cost = event.tokens.hasTokens
                    ? estimatedCost(model: model, tokens: event.tokens)
                    : event.cost
                return Event(
                    key: event.key,
                    timestamp: event.timestamp,
                    sessionID: event.sessionID,
                    model: model,
                    tokens: event.tokens,
                    credits: event.credits,
                    cost: cost,
                    creditFromLog: event.creditFromLog
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
        var summary = LocalUsageSummary()
        for event in events {
            summary.add(
                date: event.timestamp,
                tokens: event.tokens,
                // A single user request can produce many stream events. The
                // log-only entries are therefore used for credits but are
                // not counted as additional requests.
                requests: event.creditFromLog && !event.tokens.hasTokens ? 0 : 1,
                credits: event.credits,
                cost: event.cost,
                model: event.model,
                sessionID: event.sessionID
            )
        }

        return Result(
            summary: summary,
            responseCount: events.count,
            hasLogFiles: !files.isEmpty,
            latestModel: events.last?.model
        )
    }

    private static func merge(_ left: Event, _ right: Event) -> Event {
        let tokenEvent = left.tokens.hasTokens ? left : right
        let creditEvent: Event
        if left.creditFromLog {
            creditEvent = left
        } else if right.creditFromLog {
            creditEvent = right
        } else {
            creditEvent = left
        }
        let model = left.model != "未知" ? left.model : right.model
        return Event(
            key: left.key,
            timestamp: tokenEvent.timestamp,
            sessionID: left.sessionID,
            model: model,
            tokens: tokenEvent.tokens,
            credits: creditEvent.credits,
            cost: tokenEvent.cost,
            creditFromLog: left.creditFromLog || right.creditFromLog
        )
    }

    private static func logFiles() -> [URL] {
        var files: [URL] = []
        var seen: Set<String> = []

        func appendFiles(in root: URL, extensions: Set<String>) {
            guard FileManager.default.fileExists(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(
                      at: root,
                      includingPropertiesForKeys: [.isRegularFileKey],
                      options: [.skipsPackageDescendants]
                  ) else { return }
            for case let url as URL in enumerator {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                let normalized = url.resolvingSymlinksInPath().standardizedFileURL
                guard seen.insert(normalized.path).inserted else { continue }
                files.append(normalized)
            }
        }

        appendFiles(in: AppPaths.workBuddyProjects, extensions: ["jsonl"])
        appendFiles(in: AppPaths.workBuddyLogs, extensions: ["log"])
        return files.sorted { $0.path < $1.path }
    }

    private static func parseFile(at url: URL, size: Int64, modifiedAt: Double) -> FileEntry {
        if url.pathExtension.lowercased() == "log" {
            return parseCreditLogFile(at: url, size: size, modifiedAt: modifiedAt)
        }

        var events: [CachedEvent] = []
        var sessionModels: [String: String] = [:]
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else {
            return FileEntry(size: size, modifiedAt: modifiedAt, events: [], sessionModels: [:])
        }

        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            guard let object = LocalData.parseJSON(string: String(line)) as? [String: Any] else {
                continue
            }
            if let sessionID = nonemptyString(object["sessionId"]),
               let providerData = object["providerData"] as? [String: Any] {
                let model = providerModel(in: providerData)
                if model != "未知" {
                    sessionModels[sessionID] = model
                }
            }
            if let event = parseEvent(object, lineNumber: index + 1) {
                events.append(CachedEvent(event))
            }
        }
        return FileEntry(size: size, modifiedAt: modifiedAt, events: events, sessionModels: sessionModels)
    }

    private static func parseEvent(_ object: [String: Any], lineNumber: Int) -> Event? {
        guard let sessionID = nonemptyString(object["sessionId"]),
              let providerData = object["providerData"] as? [String: Any],
              let rawUsage = providerData["rawUsage"] as? [String: Any],
              let timestamp = LocalData.date(object["timestamp"]) else { return nil }

        let prompt = max(LocalData.number(rawUsage["prompt_tokens"]) ?? 0, 0)
        let completion = max(LocalData.number(rawUsage["completion_tokens"]) ?? 0, 0)
        guard prompt + completion > 0 else { return nil }

        // Tokei confirms that current WorkBuddy records use prompt_tokens as
        // the inclusive prompt total. Keep a compatibility fallback for old
        // records that stored only uncached input while total_tokens exposed
        // the full prompt plus completion total.
        let rawCachedHit = max(
            max(LocalData.number(rawUsage["prompt_cache_hit_tokens"]) ?? 0, 0),
            0
        )
        let rawCacheWrite = max(
            LocalData.number(rawUsage["prompt_cache_write_tokens"])
                ?? LocalData.number(rawUsage["cache_creation_input_tokens"])
                ?? LocalData.number(rawUsage["cache_write_input_tokens"])
                ?? 0,
            0
        )
        let cachedHit = min(rawCachedHit, prompt)
        let totalTokens = LocalData.number(rawUsage["total_tokens"])
        let promptIncludesCache = totalTokens.map {
            abs($0 - (prompt + completion)) < 0.5
        } ?? true
        let cacheWrite = promptIncludesCache
            ? min(rawCacheWrite, max(prompt - cachedHit, 0))
            : max(rawCacheWrite, 0)
        let promptTotal = promptIncludesCache
            ? prompt
            : prompt + cachedHit + cacheWrite
        let thinking = min(
            max(LocalData.number(rawUsage["completion_thinking_tokens"]) ?? 0, 0),
            completion
        )
        let tokens = TokenBreakdown(
            input: promptTotal,
            output: completion,
            total: max(totalTokens ?? 0, promptTotal + completion),
            cacheRead: cachedHit,
            cacheWrite: cacheWrite,
            reasoning: thinking,
            inputIncludesCache: true
        )
        let credits = max(LocalData.number(rawUsage["credit"]) ?? 0, 0)
        let model = providerModel(in: providerData)
        let messageID = nonemptyString(providerData["messageId"])
            ?? nonemptyString(object["id"])
        let key = messageID.map { "\(sessionID)|message|\($0)" }
            ?? "\(sessionID)|line|\(lineNumber)"

        return Event(
            key: key,
            timestamp: timestamp,
            sessionID: sessionID,
            model: model,
            tokens: tokens,
            credits: credits,
            cost: estimatedCost(model: model, tokens: tokens),
            creditFromLog: false
        )
    }

    private static let logDateFormatters: [DateFormatter] = [
        "M/d/yyyy, h:mm:ss a.SSS",
        "M/d/yyyy, h:mm:ss a"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    private static func parseCreditLogFile(at url: URL, size: Int64, modifiedAt: Double) -> FileEntry {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else {
            return FileEntry(size: size, modifiedAt: modifiedAt, events: [], sessionModels: [:])
        }

        var events: [CachedEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let value = String(line)
            guard value.contains("[AcpUsagePublisher]"),
                  value.contains("credit consumed"),
                  let sessionID = logToken("sessionId", in: value),
                  let messageID = logToken("messageId", in: value),
                  let creditString = logToken("credit", in: value),
                  let credit = Double(creditString),
                  credit > 0,
                  let timestamp = logTimestamp(in: value) else { continue }

            let event = Event(
                key: "\(sessionID)|message|\(messageID)",
                timestamp: timestamp,
                sessionID: sessionID,
                model: "未知",
                tokens: TokenBreakdown(),
                credits: credit,
                cost: 0,
                creditFromLog: true
            )
            events.append(CachedEvent(event))
        }
        return FileEntry(size: size, modifiedAt: modifiedAt, events: events, sessionModels: [:])
    }

    private static func logToken(_ name: String, in line: String) -> String? {
        let prefix = "\(name)="
        guard let token = line.split(whereSeparator: \.isWhitespace).first(where: {
            $0.hasPrefix(prefix)
        }) else { return nil }
        let value = String(token.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private static func logTimestamp(in line: String) -> Date? {
        guard let open = line.firstIndex(of: "["),
              let close = line.firstIndex(of: "]"),
              open < close else { return nil }
        let value = String(line[line.index(after: open)..<close])
        return logDateFormatters.lazy.compactMap { $0.date(from: value) }.first
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = LocalData.string(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// WorkBuddy writes both a friendly model name and a provider-local ID.
    /// Tokei uses the friendly request name first; keep the same precedence so
    /// the shared price table can resolve Kimi-K3/Hy3 consistently.
    private static func providerModel(in providerData: [String: Any]) -> String {
        nonemptyString(providerData["requestModelName"])
            ?? nonemptyString(providerData["requestModelId"])
            ?? nonemptyString(providerData["model"])
            ?? "未知"
    }

    private static func estimatedCost(model: String, tokens: TokenBreakdown) -> Double {
        guard tokens.hasTokens else { return 0 }
        return CodexPricing.estimatedCost(
            model: model,
            inputTokens: tokens.input,
            cachedInputTokens: tokens.cacheRead,
            outputTokens: tokens.output,
            cacheWriteTokens: tokens.cacheWrite
        ) ?? 0
    }

    private static func loadCache() -> ScanCache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ScanCache.self, from: data),
              cache.version == cacheVersion else { return nil }
        return cache
    }

    private static func saveCache(_ cache: ScanCache) {
        try? FileManager.default.createDirectory(
            at: AppPaths.appSupport,
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
