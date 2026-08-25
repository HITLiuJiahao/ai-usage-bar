import Foundation

struct CodexQuotaWindow: Codable {
    let slot: String
    let usedPercent: Double
    let windowMinutes: Int?
    let resetAt: Date?
}

struct CodexQuotaSnapshot: Codable {
    let windows: [CodexQuotaWindow]
    let planType: String?
    let creditsBalance: Double?
    let updatedAt: Date
}

struct CodexQuotaFetchResult {
    let snapshot: CodexQuotaSnapshot
    let source: DataSource
}

struct CodexUsageScanResult {
    let summary: LocalUsageSummary
    let latestQuota: CodexQuotaSnapshot?
    let hasRolloutFiles: Bool
    let recognizedEventCount: Int
}

enum CodexPricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double

        init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double = 0) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
        }
    }

    private static let defaultPrice = Price(input: 5.0, output: 30.0, cacheRead: 0.5)
    private static let defaultID = "openai/gpt-5.5"
    private static let autoReviewID = "codex-auto-review"
    private static let autoReviewCanonicalID = "openai/gpt-5.3-codex"
    private static let autoReviewPrice = Price(input: 1.75, output: 14.0, cacheRead: 0.175)
    // MiniMax's public price page is denominated in CNY. The dashboard's
    // existing cost column is USD-based, so these are the equivalent standard
    // API rates used by the local Tokei price table: $0.30 / $1.20 / $0.06 per
    // million input / output / cache-read tokens for MiniMax M3.
    private static let builtInProviderPrices: [String: Price] = [
        "minimax/minimax-m3": Price(input: 0.30, output: 1.20, cacheRead: 0.06),
        "minimax/minimax-m2.7": Price(input: 0.30, output: 1.20, cacheRead: 0.06),
        "minimax/minimax-m2.7-highspeed": Price(input: 0.60, output: 2.40, cacheRead: 0.06),
        "minimax/minimax-m2.5": Price(input: 0.30, output: 1.20, cacheRead: 0.03),
        "minimax/minimax-m2.5-highspeed": Price(input: 0.60, output: 2.40, cacheRead: 0.03),
        "minimax/minimax-m2.1": Price(input: 0.30, output: 1.20, cacheRead: 0.03),
        "minimax/minimax-m2.1-highspeed": Price(input: 0.60, output: 2.40, cacheRead: 0.03),
        "minimax/minimax-m2": Price(input: 0.30, output: 1.20, cacheRead: 0.03),
        // WorkBuddy fallback prices. The local ~/.tokei/pricing.json, when
        // present, is loaded afterwards and takes precedence over these.
        "moonshotai/kimi-k3": Price(input: 3.0, output: 15.0, cacheRead: 0.30),
        "tencent/hy3": Price(input: 0.132, output: 0.528, cacheRead: 0.033),
        "tencent/hy3-preview": Price(input: 0.18, output: 0.60, cacheRead: 0.06),
        // Qianwen Office Mode reports provider token counts, but not the
        // subscription's Credits deduction. These public USD-equivalent
        // list rates are therefore comparison estimates, not official bills.
        "qwen3.8-max": Price(input: 2.0, output: 6.0, cacheRead: 0.25, cacheWrite: 2.50),
        "qwen3.8-max-preview": Price(input: 2.0, output: 6.0, cacheRead: 0.25, cacheWrite: 2.50),
        "deepseek-v4-flash": Price(input: 0.14, output: 0.28, cacheRead: 0.0028),
        "deepseek-v4-flash-0731": Price(input: 0.14, output: 0.28, cacheRead: 0.0028),
        "glm-5.2": Price(input: 1.40, output: 4.40, cacheRead: 0.26),
        // OpenCode-hosted free models. These are explicit zero-cost entries
        // so the dashboard does not incorrectly label them as unpriced.
        "qwen3-coder": Price(input: 0, output: 0, cacheRead: 0),
        "glm-4.7-free": Price(input: 0, output: 0, cacheRead: 0),
        "minimax-m2.1-free": Price(input: 0, output: 0, cacheRead: 0),
        "x-preview-f-free": Price(input: 0, output: 0, cacheRead: 0)
    ]

    private static let pricingStore: (models: [String: Price], aliases: [String: String]) = {
        var models: [String: Price] = [
            defaultID: defaultPrice,
            autoReviewCanonicalID: autoReviewPrice
        ]
        for (model, price) in builtInProviderPrices {
            models[model] = price
        }
        var aliases: [String: String] = [
            autoReviewID: autoReviewCanonicalID,
            "minimax-m3": "minimax/minimax-m3",
            "minimax/m3": "minimax/minimax-m3",
            // WorkBuddy reports these provider-local names while the shared
            // Tokei price table uses the canonical provider IDs.
            "kimi-k3": "moonshotai/kimi-k3",
            "kimi-k3-1": "moonshotai/kimi-k3",
            "hy3": "tencent/hy3",
            "hy3-preview": "tencent/hy3-preview",
            "qwen/qwen3.8-max": "qwen3.8-max",
            "qwen/qwen3.8-max-preview": "qwen3.8-max-preview",
            "deepseek/deepseek-v4-flash": "deepseek-v4-flash",
            "deepseek/deepseek-v4-flash-0731": "deepseek-v4-flash-0731",
            "z-ai/glm-5.2": "glm-5.2",
            "zai/glm-5.2": "glm-5.2"
        ]

        let homePricing = AppPaths.home
            .appendingPathComponent(".tokei", isDirectory: true)
            .appendingPathComponent("pricing.json")
        let homeOverrides = AppPaths.home
            .appendingPathComponent(".tokei", isDirectory: true)
            .appendingPathComponent("pricing_overrides.json")

        func loadModels(from url: URL) {
            guard let root = LocalData.loadJSON(at: url) as? [String: Any] else { return }
            let rawModels = (root["models"] as? [String: Any]) ?? root
            for (rawID, rawValue) in rawModels {
                guard let object = rawValue as? [String: Any] else { continue }
                let input = LocalData.number(object["in"] ?? object["input"] ?? object["prompt"]) ?? 0
                let output = LocalData.number(object["out"] ?? object["output"] ?? object["completion"]) ?? 0
                let cacheRead = LocalData.number(object["cache_read"] ?? object["cacheRead"] ?? object["input_cache_read"]) ?? 0
                let cacheWrite = LocalData.number(object["cache_write"] ?? object["cacheWrite"] ?? object["input_cache_write"]) ?? 0
                guard input > 0 || output > 0 || cacheRead > 0 else { continue }
                models[normalize(rawID)] = Price(
                    input: input,
                    output: output,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite
                )
            }
        }

        func loadOverrides(from url: URL) {
            guard let root = LocalData.loadJSON(at: url) as? [String: Any] else { return }
            if let rawAliases = root["aliases"] as? [String: Any] {
                for (key, value) in rawAliases {
                    if let target = value as? String, !target.isEmpty {
                        aliases[key.lowercased()] = normalize(target)
                    }
                }
            }
            loadModels(from: url)
        }

        loadModels(from: homePricing)
        loadOverrides(from: homeOverrides)
        return (models, aliases)
    }()

    static func displayName(_ rawModel: String?) -> String {
        guard let rawModel else { return "未知" }
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未知" }
        let lower = trimmed.lowercased()
        if ["unknown", "null", "nil", "none", "default", "<synthetic>"].contains(lower) {
            return "未知"
        }
        if lower == autoReviewID || lower == "openai/\(autoReviewID)" {
            return "GPT-5.3-Codex"
        }

        let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let pieces = name.split(separator: "-").map(String.init)
        if pieces.first?.lowercased() == "gpt", pieces.count >= 2 {
            let version = pieces[1]
            let variants = pieces.dropFirst(2).map { $0.capitalized }.joined(separator: " ")
            return variants.isEmpty ? "GPT-\(version)" : "GPT-\(version) \(variants)"
        }
        return pieces.map { piece in
            piece.prefix(1).uppercased() + piece.dropFirst()
        }.joined(separator: " ")
    }

    static func cost(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) -> Double {
        let price = resolvedPrice(for: model)
        let highContext = inputTokens > 272_000
        let inputPrice = price.input * (highContext ? 2 : 1)
        let cachePrice = price.cacheRead * (highContext ? 2 : 1)
        let outputPrice = price.output * (highContext ? 1.5 : 1)
        let uncachedInput = max(inputTokens - cachedInputTokens, 0)
        return Double(uncachedInput) / 1_000_000 * inputPrice
            + Double(cachedInputTokens) / 1_000_000 * cachePrice
            + Double(outputTokens) / 1_000_000 * outputPrice
    }

    /// Estimate a generic provider's token cost from the same local price
    /// table used by Tokei. Unlike Codex's own estimator, this deliberately
    /// does not apply Codex long-context multipliers.
    static func estimatedCost(
        model: String,
        inputTokens: Double,
        cachedInputTokens: Double,
        outputTokens: Double,
        cacheWriteTokens: Double = 0
    ) -> Double? {
        guard let price = knownPrice(for: model) else { return nil }
        let longContextMultiplier = isMiniMaxM3(model) && inputTokens > 512_000 ? 2.0 : 1.0
        let totalInput = max(inputTokens, 0)
        let cachedInput = min(max(cachedInputTokens, 0), totalInput)
        let cacheWrite = min(max(cacheWriteTokens, 0), max(totalInput - cachedInput, 0))
        let uncachedInput = max(totalInput - cachedInput - cacheWrite, 0)
        return uncachedInput / 1_000_000 * price.input * longContextMultiplier
            + cachedInput / 1_000_000 * price.cacheRead * longContextMultiplier
            + cacheWrite / 1_000_000 * price.cacheWrite * longContextMultiplier
            + max(outputTokens, 0) / 1_000_000 * price.output * longContextMultiplier
    }

    private static func resolvedPrice(for rawModel: String) -> Price {
        if let price = knownPrice(for: rawModel) { return price }

        // Tokei falls back conservatively to the current GPT-5 family price
        // when a Codex model is not present in the local price table.
        return pricingStore.models[defaultID] ?? defaultPrice
    }

    private static func knownPrice(for rawModel: String) -> Price? {
        let normalized = normalize(rawModel)
        if let alias = pricingStore.aliases[rawModel.lowercased()],
           let price = pricingStore.models[alias] {
            return price
        }
        return pricingStore.models[normalized]
    }

    private static func isMiniMaxM3(_ rawModel: String) -> Bool {
        normalize(rawModel) == "minimax/minimax-m3"
    }

    private static func normalize(_ model: String) -> String {
        var value = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        if value.hasSuffix(":free") { value.removeLast(5) }
        if value.hasSuffix("-free") { value.removeLast(5) }
        if value == "kimi-k3" || value == "kimi-k3-1" {
            return "moonshotai/kimi-k3"
        }
        if value == "hy3" {
            return "tencent/hy3"
        }
        if value == "hy3-preview" {
            return "tencent/hy3-preview"
        }
        if value.hasPrefix("minimax/") {
            let suffix = String(value.dropFirst("minimax/".count))
            return suffix.hasPrefix("minimax-")
                ? value
                : "minimax/minimax-\(suffix)"
        }
        if value.hasPrefix("minimax-") {
            return "minimax/\(value)"
        }
        if value.contains("/") { return value }
        if value.hasPrefix("gpt") || value.hasPrefix("o1") || value.hasPrefix("o3") || value.hasPrefix("o4") {
            return "openai/\(value)"
        }
        return value
    }
}

enum CodexUsageScanner {
    private struct EventKey: Hashable {
        let totalInput: Int
        let totalCached: Int
        let totalOutput: Int
        let totalReasoning: Int
        let input: Int
        let cached: Int
        let output: Int
        let reasoning: Int
    }

    private struct CodexEvent: Codable {
        let timestamp: Double
        let dateKey: String
        let totalInput: Int?
        let totalCached: Int?
        let totalOutput: Int?
        let totalReasoning: Int?
        let input: Int
        let cached: Int
        let output: Int
        let reasoning: Int
        let cost: Double
        let model: String

        var totalKey: EventKey? {
            guard let totalInput, let totalCached, let totalOutput, let totalReasoning else { return nil }
            return EventKey(
                totalInput: totalInput,
                totalCached: totalCached,
                totalOutput: totalOutput,
                totalReasoning: totalReasoning,
                input: input,
                cached: cached,
                output: output,
                reasoning: reasoning
            )
        }

        var tokenBreakdown: TokenBreakdown {
            TokenBreakdown(
                input: Double(input),
                output: Double(output),
                total: Double(input + cached + output),
                cacheRead: Double(cached),
                cacheWrite: 0,
                reasoning: Double(reasoning)
            )
        }
    }

    private struct FileEntry: Codable {
        let size: Int64
        let modifiedAt: Double
        let sessionID: String?
        let forkedFromID: String?
        let events: [CodexEvent]
        let latestQuota: CodexQuotaSnapshot?
    }

    private struct ScanCache: Codable {
        let version: Int
        let files: [String: FileEntry]
    }

    private static let cacheVersion = 1
    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("codex-scan-cache.json")
    private static let tokenMarker = Data("\"token_count\"".utf8)
    private static let modelMarker = Data("\"turn_context\"".utf8)
    private static let sessionMarker = Data("\"session_meta\"".utf8)

    static func scan() -> CodexUsageScanResult {
        let files = rolloutFiles()
        let previous = loadCache()
        var current: [String: FileEntry] = [:]

        for url in files {
            let path = url.path
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

            if let cached = previous[path], cached.size == size, cached.modifiedAt == modifiedAt {
                current[path] = cached
            } else {
                current[path] = parseFile(url: url, size: size, modifiedAt: modifiedAt)
            }
        }

        saveCache(ScanCache(version: cacheVersion, files: current))

        let canonical = canonicalEntries(current)
        var summary = LocalUsageSummary()
        var latestQuota: CodexQuotaSnapshot?
        var recognizedEventCount = 0

        for (path, entry) in canonical {
            let dropCount = replayedPrefixCount(for: path, entry: entry, entries: canonical)
            let visibleEvents = entry.events.dropFirst(dropCount)
            for event in visibleEvents {
                let date = Date(timeIntervalSince1970: event.timestamp)
                summary.add(
                    date: date,
                    tokens: event.tokenBreakdown,
                    cost: event.cost,
                    model: CodexPricing.displayName(event.model),
                    sessionID: path
                )
                recognizedEventCount += 1
            }
            if let quota = entry.latestQuota,
               latestQuota == nil || quota.updatedAt > latestQuota!.updatedAt {
                latestQuota = quota
            }
        }

        return CodexUsageScanResult(
            summary: summary,
            latestQuota: latestQuota,
            hasRolloutFiles: !files.isEmpty,
            recognizedEventCount: recognizedEventCount
        )
    }

    private static func rolloutFiles() -> [URL] {
        var results: [URL] = []
        var seen: Set<String> = []
        for root in [AppPaths.codexSessions, AppPaths.codexArchivedSessions] {
            guard FileManager.default.fileExists(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsPackageDescendants]
                  ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-") else { continue }
                let normalized = url.resolvingSymlinksInPath().standardizedFileURL
                guard seen.insert(normalized.path).inserted else { continue }
                results.append(normalized)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    private static func loadCache() -> [String: FileEntry] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ScanCache.self, from: data),
              cache.version == cacheVersion else { return [:] }
        return cache.files
    }

    private static func saveCache(_ cache: ScanCache) {
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: cacheURL.path
            )
        } catch {
            // Usage collection should continue even if the optional cache
            // cannot be written in a restricted environment.
        }
    }

    private static func parseFile(url: URL, size: Int64, modifiedAt: Double) -> FileEntry {
        var sessionID: String?
        var forkedFromID: String?
        var currentModel: String?
        var previousTotalKey: EventKey?
        var events: [CodexEvent] = []
        var latestQuota: CodexQuotaSnapshot?
        let fallbackDate = Date(timeIntervalSince1970: modifiedAt)

        forEachLine(at: url) { line in
            guard line.range(of: tokenMarker) != nil
                || line.range(of: modelMarker) != nil
                || line.range(of: sessionMarker) != nil else { return }
            guard let object = LocalData.parseJSON(data: line) as? [String: Any] else { return }
            let outerType = LocalData.string(object["type"])
            let payload = object["payload"] as? [String: Any] ?? [:]

            if outerType == "session_meta" {
                let metaID = LocalData.string(payload["id"] ?? payload["session_id"])
                if sessionID == nil { sessionID = metaID }
                if forkedFromID == nil {
                    forkedFromID = LocalData.string(payload["forked_from_id"] ?? payload["parent_thread_id"])
                    if forkedFromID == nil,
                       let source = payload["source"] as? [String: Any],
                       let subagent = source["subagent"] as? [String: Any],
                       let spawn = subagent["thread_spawn"] as? [String: Any] {
                        forkedFromID = LocalData.string(spawn["parent_thread_id"])
                    }
                }
            }

            if outerType == "turn_context",
               let model = LocalData.string(payload["model"]),
               !model.isEmpty {
                currentModel = model
            }

            guard LocalData.string(payload["type"]) == "token_count" else { return }
            let timestamp = LocalData.date(object["timestamp"] ?? payload["timestamp"]) ?? fallbackDate
            let info = payload["info"] as? [String: Any] ?? [:]
            let last = info["last_token_usage"] as? [String: Any] ?? [:]
            guard !last.isEmpty else { return }

            if let rateLimits = payload["rate_limits"] {
                let quota = CodexQuotaParser.parse(rateLimits, timestamp: timestamp)
                if let quota, latestQuota == nil || quota.updatedAt > latestQuota!.updatedAt {
                    latestQuota = quota
                }
            }

            let rawInput = CodexUsageScanner.integer(last["input_tokens"])
            let cached = CodexUsageScanner.integer(last["cached_input_tokens"])
            let output = CodexUsageScanner.integer(last["output_tokens"])
            let reasoning = CodexUsageScanner.integer(last["reasoning_output_tokens"])
            let total = info["total_token_usage"] as? [String: Any]
            let totalKey: EventKey?
            if let total {
                totalKey = EventKey(
                    totalInput: CodexUsageScanner.integer(total["input_tokens"]),
                    totalCached: CodexUsageScanner.integer(total["cached_input_tokens"]),
                    totalOutput: CodexUsageScanner.integer(total["output_tokens"]),
                    totalReasoning: CodexUsageScanner.integer(total["reasoning_output_tokens"]),
                    input: rawInput,
                    cached: cached,
                    output: output,
                    reasoning: reasoning
                )
            } else {
                totalKey = nil
            }
            if let totalKey, totalKey == previousTotalKey {
                previousTotalKey = totalKey
                return
            }
            previousTotalKey = totalKey

            let model = currentModel ?? "unknown"
            events.append(CodexEvent(
                timestamp: timestamp.timeIntervalSince1970,
                dateKey: CodexUsageScanner.dateKey(timestamp),
                totalInput: total?["input_tokens"].flatMap(CodexUsageScanner.integer),
                totalCached: total?["cached_input_tokens"].flatMap(CodexUsageScanner.integer),
                totalOutput: total?["output_tokens"].flatMap(CodexUsageScanner.integer),
                totalReasoning: total?["reasoning_output_tokens"].flatMap(CodexUsageScanner.integer),
                input: max(rawInput - cached, 0),
                cached: cached,
                output: output,
                reasoning: reasoning,
                cost: CodexPricing.cost(
                    model: model,
                    inputTokens: rawInput,
                    cachedInputTokens: cached,
                    outputTokens: output
                ),
                model: model
            ))
        }

        return FileEntry(
            size: size,
            modifiedAt: modifiedAt,
            sessionID: sessionID,
            forkedFromID: forkedFromID,
            events: events,
            latestQuota: latestQuota
        )
    }

    private static func forEachLine(at url: URL, body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        let maxRelevantLineBytes = 2 * 1024 * 1024
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
                if newline - lineStart <= maxRelevantLineBytes {
                    body(Data(buffer[lineStart..<newline]))
                }
                lineStart = newline + 1
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
            if buffer.count > maxRelevantLineBytes {
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty, buffer.count <= maxRelevantLineBytes { body(buffer) }
    }

    private static func canonicalEntries(_ entries: [String: FileEntry]) -> [String: FileEntry] {
        var selected: [String: (score: (Int, Double, Int64), path: String)] = [:]
        var result: [String: FileEntry] = [:]
        for (path, entry) in entries {
            let logicalID = entry.sessionID.map { "session:\($0)" } ?? "rollout:\(URL(fileURLWithPath: path).lastPathComponent)"
            let score = (entry.events.count, entry.events.last?.timestamp ?? 0, entry.size)
            if let existing = selected[logicalID], score <= existing.score { continue }
            if let existing = selected[logicalID] { result.removeValue(forKey: existing.path) }
            selected[logicalID] = (score, path)
            result[path] = entry
        }
        return result
    }

    private static func replayedPrefixCount(
        for childPath: String,
        entry: FileEntry,
        entries: [String: FileEntry]
    ) -> Int {
        var best = 0
        if let parentID = entry.forkedFromID,
           let parent = entries.first(where: { $0.value.sessionID == parentID }) {
            best = prefixMatch(entry.events, parent.value.events)
        }

        if best == 0, entry.events.count >= 2,
           let first = entry.events.prefix(2).map(\.totalKey) as? [EventKey?],
           first.count == 2, first.allSatisfy({ $0 != nil }) {
            let childFirstTimestamp = entry.events[0].timestamp
            for (path, candidate) in entries where path != childPath {
                guard candidate.events.count >= 2,
                      candidate.events[0].timestamp < childFirstTimestamp,
                      candidate.events[0].totalKey == first[0],
                      candidate.events[1].totalKey == first[1] else { continue }
                best = max(best, prefixMatch(entry.events, candidate.events))
            }
        }

        let burstSecond = entry.events.dropFirst(best).first.map { Int($0.timestamp) }
        if let burstSecond {
            let burstCount = entry.events.dropFirst(best).prefix { Int($0.timestamp) == burstSecond }.count
            if burstCount >= 5 { best += burstCount }
        }
        return min(best, entry.events.count)
    }

    private static func prefixMatch(_ child: [CodexEvent], _ parent: [CodexEvent]) -> Int {
        var count = 0
        while count < child.count, count < parent.count,
              let childKey = child[count].totalKey,
              childKey == parent[count].totalKey {
            count += 1
        }
        return count
    }

    private static func integer(_ value: Any?) -> Int {
        guard let number = LocalData.number(value), number.isFinite else { return 0 }
        return max(Int(number.rounded()), 0)
    }

    private static func dateKey(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

enum CodexQuotaParser {
    static func parse(_ value: Any, timestamp: Date) -> CodexQuotaSnapshot? {
        guard let object = value as? [String: Any] else { return nil }
        if let limitID = LocalData.string(object["limit_id"] ?? object["limitId"]),
           limitID != "codex" {
            return nil
        }

        var windows: [CodexQuotaWindow] = []
        for slot in ["primary", "secondary"] {
            if let raw = object[slot] as? [String: Any],
               let window = parseWindow(raw, slot: slot, timestamp: timestamp) {
                windows.append(window)
            }
        }
        for slot in ["primary_window", "secondary_window"] {
            if let raw = object[slot] as? [String: Any],
               let window = parseWindow(raw, slot: slot, timestamp: timestamp) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { return nil }

        let credits = object["credits"] as? [String: Any]
        return CodexQuotaSnapshot(
            windows: windows,
            planType: LocalData.string(object["plan_type"] ?? object["planType"]),
            creditsBalance: LocalData.number(credits?["balance"] ?? object["credits_balance"]),
            updatedAt: timestamp
        )
    }

    private static func parseWindow(
        _ object: [String: Any],
        slot: String,
        timestamp: Date
    ) -> CodexQuotaWindow? {
        guard let used = LocalData.number(object["used_percent"] ?? object["usedPercent"]), used.isFinite else {
            return nil
        }
        let windowMinutes = LocalData.number(object["window_minutes"] ?? object["windowDurationMins"]).map { Int($0.rounded()) }
            ?? LocalData.number(object["limit_window_seconds"]).map { Int(($0 / 60).rounded()) }
        var resetAt = LocalData.date(object["resets_at"] ?? object["reset_at"] ?? object["resetAt"])
        if resetAt == nil, let after = LocalData.number(object["reset_after_seconds"]) {
            resetAt = timestamp.addingTimeInterval(after)
        }
        return CodexQuotaWindow(
            slot: slot,
            usedPercent: min(max(used, 0), 100),
            windowMinutes: windowMinutes,
            resetAt: resetAt
        )
    }
}

enum CodexQuotaService {
    private struct PersistedCache: Codable {
        let snapshot: CodexQuotaSnapshot
        let fetchedAt: Date
        let lastFailureAt: Date?
    }

    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("codex-quota-cache.json")
    private static var memory: PersistedCache?

    static func fetchLive() async -> CodexQuotaFetchResult? {
        let now = Date()
        let cache = loadCache()
        if let cache, now.timeIntervalSince(cache.fetchedAt) < 30 {
            return CodexQuotaFetchResult(snapshot: cache.snapshot, source: .cached)
        }
        if let cache,
           let lastFailureAt = cache.lastFailureAt,
           now.timeIntervalSince(lastFailureAt) < 300,
           now.timeIntervalSince(cache.fetchedAt) < 300 {
            return CodexQuotaFetchResult(snapshot: cache.snapshot, source: .cached)
        }
        guard let auth = authContext() else {
            return cache.map { CodexQuotaFetchResult(snapshot: $0.snapshot, source: .cached) }
        }

        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }
        do {
            var headers = [
                "Authorization": "Bearer \(auth.token)",
                "User-Agent": "AIUsageBar/0.1"
            ]
            if let accountID = auth.accountID {
                headers["ChatGPT-Account-Id"] = accountID
            }
            let result = try await HTTPJSON.get(url: url, headers: headers)
            guard (200..<300).contains(result.statusCode),
                  let snapshot = parseLiveResponse(result.object, updatedAt: now) else {
                throw URLError(.badServerResponse)
            }
            saveCache(PersistedCache(snapshot: snapshot, fetchedAt: now, lastFailureAt: nil))
            return CodexQuotaFetchResult(snapshot: snapshot, source: .server)
        } catch {
            let failed = PersistedCache(snapshot: cache?.snapshot ?? CodexQuotaSnapshot(windows: [], planType: nil, creditsBalance: nil, updatedAt: now), fetchedAt: cache?.fetchedAt ?? .distantPast, lastFailureAt: now)
            if cache != nil { saveCache(failed) }
            return cache.map { CodexQuotaFetchResult(snapshot: $0.snapshot, source: .cached) }
        }
    }

    private static func parseLiveResponse(_ value: Any, updatedAt: Date) -> CodexQuotaSnapshot? {
        guard let root = value as? [String: Any] else { return nil }
        let rateLimit = (root["rate_limit"] as? [String: Any])
            ?? (root["rateLimit"] as? [String: Any])
            ?? root
        var windows: [CodexQuotaWindow] = []
        for slot in ["primary_window", "secondary_window", "primary", "secondary"] {
            if let raw = rateLimit[slot] as? [String: Any],
               let window = parseLiveWindow(raw, slot: slot, timestamp: updatedAt) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { return nil }
        let credits = root["credits"] as? [String: Any]
        return CodexQuotaSnapshot(
            windows: windows,
            planType: LocalData.string(root["plan_type"] ?? root["planType"] ?? rateLimit["plan_type"]),
            creditsBalance: LocalData.number(credits?["balance"] ?? root["credits_balance"]),
            updatedAt: updatedAt
        )
    }

    private static func parseLiveWindow(
        _ object: [String: Any],
        slot: String,
        timestamp: Date
    ) -> CodexQuotaWindow? {
        guard let used = LocalData.number(object["used_percent"] ?? object["usedPercent"]), used.isFinite else {
            return nil
        }
        let minutes = LocalData.number(object["limit_window_seconds"]).map { Int(($0 / 60).rounded()) }
            ?? LocalData.number(object["window_minutes"] ?? object["windowDurationMins"]).map { Int($0.rounded()) }
        var resetAt = LocalData.date(object["reset_at"] ?? object["resets_at"] ?? object["resetAt"])
        if resetAt == nil, let after = LocalData.number(object["reset_after_seconds"]) {
            resetAt = timestamp.addingTimeInterval(after)
        }
        return CodexQuotaWindow(
            slot: slot,
            usedPercent: min(max(used, 0), 100),
            windowMinutes: minutes,
            resetAt: resetAt
        )
    }

    private static func authContext() -> (token: String, accountID: String?)? {
        for url in AppPaths.codexAuthCandidates {
            guard let object = LocalData.loadJSON(at: url) as? [String: Any] else { continue }
            let tokens = object["tokens"] as? [String: Any] ?? [:]
            guard let token = LocalData.string(tokens["access_token"] ?? tokens["accessToken"] ?? object["access_token"]),
                  !token.isEmpty, !token.contains("\n") else { continue }

            let accountID = LocalData.string(
                tokens["account_id"] ?? tokens["accountId"] ?? object["account_id"] ?? object["accountId"]
            ) ?? jwtAccountID(token: token, idToken: LocalData.string(tokens["id_token"] ?? tokens["idToken"] ?? object["id_token"]))
            return (token, accountID)
        }
        return nil
    }

    private static func jwtAccountID(token: String, idToken: String?) -> String? {
        for raw in [token, idToken].compactMap({ $0 }) {
            let parts = raw.split(separator: ".")
            guard parts.count >= 2 else { continue }
            var encoded = String(parts[1])
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]),
                  let claims = LocalData.parseJSON(data: data) as? [String: Any],
                  let auth = claims["https://api.openai.com/auth"] as? [String: Any],
                  let accountID = LocalData.string(auth["chatgpt_account_id"]) else { continue }
            return accountID
        }
        return nil
    }

    private static func loadCache() -> PersistedCache? {
        if let memory { return memory }
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(PersistedCache.self, from: data) else { return nil }
        memory = cache
        return cache
    }

    private static func saveCache(_ cache: PersistedCache) {
        memory = cache
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: cacheURL.path
            )
        } catch {
            // Quota caching is best-effort; local rollout data remains usable.
        }
    }
}

enum CodexQuotaMetrics {
    static func make(from snapshot: CodexQuotaSnapshot, source: DataSource) -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        let now = Date()
        var usedSlots: Set<String> = []
        for window in snapshot.windows {
            let isWeekly = window.windowMinutes == 10_080
                || (window.windowMinutes == nil && window.slot.contains("secondary"))
            let usageWindow: UsageWindow = isWeekly ? .weekly : .fiveHours
            let slotKey = usageWindow.rawValue
            guard usedSlots.insert(slotKey).inserted else { continue }
            let used = window.resetAt.map { $0 <= now } == true ? 0 : window.usedPercent
            let title = isWeekly ? "周额度" : "5 小时额度"
            let resetText = window.resetAt.map {
                "重置：\($0.formatted(date: .abbreviated, time: .shortened))"
            }
            let planText = snapshot.planType.map { "套餐：\($0)" }
            metrics.append(UsageMetric(
                key: "codex-quota-\(usageWindow.rawValue)",
                title: title,
                kind: .quota,
                window: usageWindow,
                used: used,
                limit: 100,
                remaining: max(100 - used, 0),
                unit: "%",
                source: source,
                resetAt: window.resetAt,
                note: [planText, resetText].compactMap { $0 }.joined(separator: " · ")
            ))
        }
        if let balance = snapshot.creditsBalance {
            metrics.append(UsageMetric(
                key: "codex-credits",
                title: "可用 Credits",
                kind: .credits,
                window: .billing,
                used: nil,
                limit: nil,
                remaining: max(balance, 0),
                unit: "credits",
                source: source,
                resetAt: nil,
                note: snapshot.planType.map { "套餐：\($0)" }
            ))
        }
        return metrics
    }
}
