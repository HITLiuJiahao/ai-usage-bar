import Foundation

struct DeepSeekHarnessScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let tokenResponseCount: Int
    let errorCount: Int
    let hasLogFiles: Bool
    let decoderAvailable: Bool
    let latestModel: String?
}

private struct DeepSeekHarnessEvent {
    let key: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let tokens: TokenBreakdown?
    let cost: Double
}

private struct DeepSeekHarnessCachedEvent: Codable {
    let key: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let reasoning: Double
    let hasTokens: Bool
    let cost: Double

    init(_ event: DeepSeekHarnessEvent) {
        self.key = event.key
        self.timestamp = event.timestamp
        self.sessionID = event.sessionID
        self.model = event.model
        self.input = event.tokens?.input ?? 0
        self.output = event.tokens?.output ?? 0
        self.cacheRead = event.tokens?.cacheRead ?? 0
        self.cacheWrite = event.tokens?.cacheWrite ?? 0
        self.reasoning = event.tokens?.reasoning ?? 0
        self.hasTokens = event.tokens?.hasTokens ?? false
        self.cost = event.cost
    }

    var event: DeepSeekHarnessEvent {
        DeepSeekHarnessEvent(
            key: key,
            timestamp: timestamp,
            sessionID: sessionID,
            model: model,
            tokens: hasTokens
                ? TokenBreakdown(
                    input: input,
                    output: output,
                    total: input + output,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    reasoning: reasoning,
                    inputIncludesCache: true
                )
                : nil,
            cost: cost
        )
    }
}

private struct DeepSeekHarnessFileEntry: Codable {
    let size: Int64
    let modifiedAt: Double
    let events: [DeepSeekHarnessCachedEvent]
    let errorCount: Int
}

private struct DeepSeekHarnessScanCache: Codable {
    let version: Int
    let files: [String: DeepSeekHarnessFileEntry]
}

private struct DeepSeekHarnessInputFile {
    let url: URL
    let compressed: Bool
}

enum DeepSeekHarnessUsageScanner {
    // Version 3 invalidates entries generated before the CNY peak/off-peak
    // pricing model was added.
    private static let cacheVersion = 3
    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("deepseek-harness-scan-cache.json")
    private static let tokeiCacheRoot = AppPaths.home
        .appendingPathComponent(".tokei", isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)
        .appendingPathComponent("dsh-sessions", isDirectory: true)
    private static let assistantMarker = Data("\"type\":\"assistant/message\"".utf8)
    private static let contextMarker = Data("\"type\":\"request/context\"".utf8)
    private static let maximumCompressedBytes = 256 * 1024 * 1024
    private static let maximumDecompressedBytes = 256 * 1024 * 1024

    static func scan() -> DeepSeekHarnessScanResult {
        let compressedFiles = logFiles(under: AppPaths.deepSeekHarnessSessions, fileExtension: "zstd")
        let cachedFiles = logFiles(under: tokeiCacheRoot, fileExtension: "jsonl")
        let decoder = zstdExecutable()
        let inputs: [DeepSeekHarnessInputFile]

        // Tokei's decompressed cache is a useful fallback when a machine has
        // already been indexed by Tokei but does not have a zstd executable.
        if !compressedFiles.isEmpty, decoder != nil {
            inputs = compressedFiles.map { DeepSeekHarnessInputFile(url: $0, compressed: true) }
        } else if !cachedFiles.isEmpty {
            inputs = cachedFiles.map { DeepSeekHarnessInputFile(url: $0, compressed: false) }
        } else {
            inputs = compressedFiles.map { DeepSeekHarnessInputFile(url: $0, compressed: true) }
        }

        let previous = loadCache()
        var current: [String: DeepSeekHarnessFileEntry] = [:]
        var cacheDirty = previous == nil

        for input in inputs {
            let values = try? input.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let key = input.url.resolvingSymlinksInPath().standardizedFileURL.path

            if let cached = previous?.files[key],
               cached.size == size,
               cached.modifiedAt == modifiedAt {
                current[key] = cached
            } else {
                current[key] = parseFile(at: input.url, compressed: input.compressed, size: size, modifiedAt: modifiedAt)
                cacheDirty = true
            }
        }

        if let previous, Set(previous.files.keys) != Set(current.keys) {
            cacheDirty = true
        }
        if cacheDirty {
            saveCache(DeepSeekHarnessScanCache(version: cacheVersion, files: current))
        }

        var uniqueEvents: [String: DeepSeekHarnessEvent] = [:]
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

        let decoderAvailable = compressedFiles.isEmpty || decoder != nil || !cachedFiles.isEmpty
        return DeepSeekHarnessScanResult(
            summary: summary,
            responseCount: events.count,
            tokenResponseCount: tokenResponseCount,
            errorCount: errorCount,
            hasLogFiles: !compressedFiles.isEmpty || !cachedFiles.isEmpty,
            decoderAvailable: decoderAvailable,
            latestModel: events.last?.model
        )
    }

    private static func eventScore(_ event: DeepSeekHarnessEvent) -> (Int, Double) {
        let tokenScore = event.tokens?.total ?? 0
        return (tokenScore > 0 ? 1 : 0, event.timestamp.timeIntervalSince1970)
    }

    private static func logFiles(under root: URL, fileExtension: String) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsPackageDescendants]
              ) else { return [] }

        var files: [URL] = []
        var seen: Set<String> = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == fileExtension.lowercased(),
                  let isRegularFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegularFile == true else { continue }
            let normalized = url.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(normalized.path).inserted else { continue }
            files.append(normalized)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func sessionID(for url: URL) -> String {
        // Each Harness session file is named session.jsonl.zstd, so the
        // containing directory is a more stable identifier than the filename.
        url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func parseFile(
        at url: URL,
        compressed: Bool,
        size: Int64,
        modifiedAt: Double
    ) -> DeepSeekHarnessFileEntry {
        let fallbackDate = Date(timeIntervalSince1970: modifiedAt)
        let sessionID = sessionID(for: url)
        var currentModel: String?
        var currentProvider: String?
        var events: [DeepSeekHarnessCachedEvent] = []
        var errorCount = 0
        var lineNumber = 0

        func consume(_ line: Data) {
            lineNumber += 1
            guard line.range(of: assistantMarker) != nil || line.range(of: contextMarker) != nil else { return }
            guard let object = LocalData.parseJSON(data: line) as? [String: Any],
                  let type = LocalData.string(object["type"]) else { return }

            let data = object["data"] as? [String: Any] ?? [:]
            if type == "request/context" {
                currentModel = modelName(in: data) ?? currentModel
                currentProvider = LocalData.string(data["provider"]) ?? currentProvider
                return
            }
            guard type == "assistant/message",
                  let usage = data["usage"] as? [String: Any] else { return }

            // DeepSeek Harness already normalizes `inputTokens` to the
            // uncached prompt amount. Cache reads are a separate bucket in
            // the durable log and must not be subtracted or charged twice.
            let uncachedInput = max(number(usage, keys: ["inputTokens", "input_tokens", "input"]), 0)
            let cacheRead = max(number(usage, keys: ["cacheReadTokens", "cache_read_tokens", "cacheRead"]), 0)
            let cacheWrite = max(number(usage, keys: ["cacheWriteTokens", "cache_write_tokens", "cacheWrite"]), 0)
            let output = max(number(usage, keys: ["outputTokens", "output_tokens", "output"]), 0)
            let reasoning = max(number(usage, keys: ["reasoningTokens", "reasoning_tokens", "reasoning"]), 0)
            // Match Tokei's DeepSeek card: the displayed input is the full
            // prompt traffic, while the hit-rate flag tells the UI that the
            // cache fields are already included in it.
            let promptTotal = uncachedInput + cacheRead + cacheWrite
            let hasTokens = promptTotal > 0 || output > 0 || reasoning > 0
            let tokens: TokenBreakdown? = hasTokens
                ? TokenBreakdown(
                    input: promptTotal,
                    output: output,
                    total: promptTotal + output,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    reasoning: reasoning,
                    inputIncludesCache: true
                )
                : nil

            let model = ModelUsage.normalizedName(
                modelName(in: data) ?? currentModel ?? "未知"
            )
            let provider = LocalData.string(data["provider"]) ?? currentProvider
            let date = LocalData.date(object["time"] ?? object["timestamp"] ?? data["time"]) ?? fallbackDate
            let message = data["message"] as? [String: Any]
            let messageID = LocalData.string(message?["id"])
            let sequence = LocalData.string(object["seq"])
            let eventKey: String
            if let messageID, !messageID.isEmpty {
                eventKey = "\(sessionID)|message|\(messageID)"
            } else if let sequence, !sequence.isEmpty {
                eventKey = "\(sessionID)|seq|\(sequence)"
            } else {
                eventKey = "\(sessionID)|line|\(lineNumber)"
            }

            let cost = DeepSeekHarnessPricing.cost(
                provider: provider,
                model: model,
                uncachedInput: uncachedInput,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                output: output,
                timestamp: date
            )
            events.append(DeepSeekHarnessCachedEvent(DeepSeekHarnessEvent(
                key: eventKey,
                timestamp: date,
                sessionID: sessionID,
                model: DeepSeekHarnessPricing.displayName(model),
                tokens: tokens,
                cost: cost
            )))
        }

        guard size >= 0, size <= maximumCompressedBytes else {
            return DeepSeekHarnessFileEntry(size: size, modifiedAt: modifiedAt, events: [], errorCount: 1)
        }

        if compressed {
            guard let decompressed = decompress(url: url), decompressed.count <= maximumDecompressedBytes else {
                return DeepSeekHarnessFileEntry(size: size, modifiedAt: modifiedAt, events: [], errorCount: 1)
            }
            forEachLine(in: decompressed, body: consume)
        } else if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  data.count <= maximumDecompressedBytes {
            forEachLine(in: data, body: consume)
        } else {
            errorCount += 1
        }

        return DeepSeekHarnessFileEntry(
            size: size,
            modifiedAt: modifiedAt,
            events: events,
            errorCount: errorCount
        )
    }

    private static func number(_ object: [String: Any], keys: [String]) -> Double {
        for key in keys where object[key] != nil {
            if let value = LocalData.number(object[key]), value.isFinite {
                return value
            }
        }
        return 0
    }

    private static func modelName(in object: [String: Any]) -> String? {
        if let model = LocalData.string(object["model"]), !model.isEmpty {
            return model
        }
        if let source = object["source"] as? [String: Any],
           let model = LocalData.string(source["model"]), !model.isEmpty {
            return model
        }
        if let message = object["message"] as? [String: Any],
           let source = message["source"] as? [String: Any],
           let model = LocalData.string(source["model"]), !model.isEmpty {
            return model
        }
        return nil
    }

    private static func loadCache() -> DeepSeekHarnessScanCache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(DeepSeekHarnessScanCache.self, from: data),
              cache.version == cacheVersion else { return nil }
        return cache
    }

    private static func saveCache(_ cache: DeepSeekHarnessScanCache) {
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

    private static func forEachLine(in data: Data, body: (Data) -> Void) {
        guard !data.isEmpty else { return }
        var lineStart = data.startIndex
        while lineStart < data.endIndex,
              let newline = data[lineStart...].firstIndex(of: 0x0A) {
            body(Data(data[lineStart..<newline]))
            lineStart = newline + 1
        }
        if lineStart < data.endIndex {
            body(Data(data[lineStart..<data.endIndex]))
        }
    }

    private static func zstdExecutable() -> URL? {
        let candidates = [
            "/usr/bin/zstd",
            "/opt/homebrew/bin/zstd",
            "/usr/local/bin/zstd",
            "/opt/miniconda3/bin/zstd"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func decompress(url: URL) -> Data? {
        guard let executable = zstdExecutable() else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-q", "-d", "-c", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

private enum DeepSeekHarnessPricing {
    private struct Price {
        let cacheMiss: Double
        let cacheHit: Double
        let output: Double

        func half() -> Price {
            Price(
                cacheMiss: cacheMiss / 2,
                cacheHit: cacheHit / 2,
                output: output / 2
            )
        }
    }

    // DeepSeek's current official CNY prices are quoted per million tokens.
    // The values below are the peak rates; off-peak rates are exactly half.
    private static let peakPrices: [String: Price] = [
        "deepseek-v4-pro": Price(cacheMiss: 9.0, cacheHit: 0.30, output: 27.0),
        "deepseek-v4-flash": Price(cacheMiss: 3.0, cacheHit: 0.10, output: 9.0)
    ]

    static func displayName(_ rawModel: String) -> String {
        let normalized = normalize(rawModel)
        switch normalized {
        case "deepseek-v4-pro": return "DeepSeek V4 Pro"
        case "deepseek-v4-flash": return "DeepSeek V4 Flash"
        default: return ModelUsage.normalizedName(rawModel)
        }
    }

    static func cost(
        provider: String?,
        model: String,
        uncachedInput: Double,
        cacheRead: Double,
        cacheWrite: Double,
        output: Double,
        timestamp: Date
    ) -> Double {
        guard provider?.lowercased() == "deepseek-official",
              let peakPrice = peakPrices[normalize(model)] else { return 0 }
        let price = isPeak(timestamp) ? peakPrice : peakPrice.half()
        return (
            uncachedInput * price.cacheMiss
                + cacheRead * price.cacheHit
                + cacheWrite * 0
                + output * price.output
        ) / 1_000_000
    }

    private static func normalize(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "/")
            .last
            .map(String.init) ?? value.lowercased()
        if normalized.contains("deepseek-v4-pro") { return "deepseek-v4-pro" }
        if normalized.contains("deepseek-v4-flash") { return "deepseek-v4-flash" }
        // Before V4 retirement, these aliases routed to V4 Flash on the
        // official endpoint and should use the same current price schedule.
        if normalized.contains("deepseek-chat") || normalized.contains("deepseek-reasoner") {
            return "deepseek-v4-flash"
        }
        return normalized
    }

    private static func isPeak(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return (9 * 60 ..< 12 * 60).contains(minutes)
            || (14 * 60 ..< 18 * 60).contains(minutes)
    }
}

enum DeepSeekHarnessUsageMetrics {
    static func make(summary: LocalUsageSummary) -> [UsageMetric] {
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
                    key: "deepseek-harness-tokens-\(window.rawValue)",
                    title: "Token",
                    kind: .tokens,
                    window: window,
                    used: bucket.tokens.total,
                    limit: nil,
                    remaining: nil,
                    unit: "tokens",
                    source: .local,
                    resetAt: nil,
                    note: "按 Tokei DeepSeek Harness 口径汇总",
                    inputTokens: bucket.tokens.input,
                    outputTokens: bucket.tokens.output,
                    cacheReadTokens: bucket.tokens.cacheRead,
                    cacheWriteTokens: bucket.tokens.cacheWrite,
                    reasoningTokens: bucket.tokens.reasoning,
                    inputIncludesCache: bucket.tokens.inputIncludesCache
                ))
            }
            if bucket.requests > 0 {
                metrics.append(UsageMetric(
                    key: "deepseek-harness-requests-\(window.rawValue)",
                    title: "请求次数",
                    kind: .requests,
                    window: window,
                    used: bucket.requests,
                    limit: nil,
                    remaining: nil,
                    unit: "次",
                    source: .local,
                    resetAt: nil,
                    note: "按 assistant/message.data.usage 记录计数"
                ))
            }
            if bucket.sessions.count > 0 {
                metrics.append(UsageMetric(
                    key: "deepseek-harness-sessions-\(window.rawValue)",
                    title: "会话数",
                    kind: .requests,
                    window: window,
                    used: Double(bucket.sessions.count),
                    limit: nil,
                    remaining: nil,
                    unit: "个",
                    source: .local,
                    resetAt: nil,
                    note: "按 Harness session 文件去重"
                ))
            }
            if bucket.cost > 0 {
                metrics.append(UsageMetric(
                    key: "deepseek-harness-cost-\(window.rawValue)",
                    title: "估算成本",
                    kind: .money,
                    window: window,
                    used: bucket.cost,
                    limit: nil,
                    remaining: nil,
                    unit: "CNY",
                    source: .local,
                    resetAt: nil,
                    note: "按 DeepSeek 官方人民币峰谷价：北京时间 09–12、14–18 为高峰，其余为空闲"
                ))
            }
        }
        return metrics
    }
}
