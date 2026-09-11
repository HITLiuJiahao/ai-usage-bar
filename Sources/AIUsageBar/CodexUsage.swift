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
    let resetCreditsAvailableCount: Int?
    let resetCreditsExpiresAt: Date?
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

enum CodexResetCreditsParser {
    struct Summary {
        let availableCount: Int?
        let earliestExpiresAt: Date?
    }

    static func summary(in value: Any, now: Date = Date()) -> Summary {
        guard let object = value as? [String: Any] else {
            return Summary(availableCount: nil, earliestExpiresAt: nil)
        }

        let candidates = candidateObjects(in: object)
        let availableCount = candidates.compactMap(directCount(in:)).first
        let earliestExpiresAt = candidates
            .flatMap(creditObjects(in:))
            .compactMap { credit -> Date? in
                if let status = LocalData.string(credit["status"]),
                   !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   status.lowercased() != "available" {
                    return nil
                }
                guard let expiresAt = LocalData.date(
                    credit["expires_at"]
                        ?? credit["expiresAt"]
                        ?? credit["expiration"]
                        ?? credit["expiration_at"]
                        ?? credit["expirationAt"]
                ), expiresAt > now else {
                    return nil
                }
                return expiresAt
            }
            .min()

        return Summary(
            availableCount: availableCount,
            earliestExpiresAt: earliestExpiresAt
        )
    }

    static func availableCount(in object: [String: Any]) -> Int? {
        summary(in: object).availableCount
    }

    static func earliestExpiresAt(in value: Any, now: Date = Date()) -> Date? {
        summary(in: value, now: now).earliestExpiresAt
    }

    private static func candidateObjects(in object: [String: Any]) -> [[String: Any]] {
        var candidates = [object]
        for key in [
            "rate_limit",
            "rateLimit",
            "rate_limit_reset_credits",
            "rateLimitResetCredits",
            "data",
            "result"
        ] {
            if let nested = object[key] as? [String: Any] {
                candidates.append(nested)
            }
        }
        return candidates
    }

    private static func creditObjects(in object: [String: Any]) -> [[String: Any]] {
        for key in ["credits", "reset_credits", "resetCredits"] {
            if let rawCredits = object[key] as? [Any] {
                return rawCredits.compactMap { $0 as? [String: Any] }
            }
        }
        return []
    }

    private static func directCount(in object: [String: Any]) -> Int? {
        let raw = object["available_count"]
            ?? object["availableCount"]
            ?? object["rate_limit_reset_credits"]
            ?? object["rateLimitResetCredits"]
            ?? object["reset_credits"]
            ?? object["resetCredits"]
        let value: Any?
        if let details = raw as? [String: Any] {
            value = details["available_count"] ?? details["availableCount"]
        } else {
            value = raw
        }
        guard let number = LocalData.number(value), number.isFinite else {
            return nil
        }
        return max(Int(min(number.rounded(), Double(Int.max))), 0)
    }
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
    // GPT-6 Astra's official OpenAI API Standard rates, in USD per million
    // tokens: $10 input, $1 cache read, $12.50 cache write, and $50 output.
    // Local ~/.tokei pricing files are still loaded afterwards and can
    // override this built-in value when a user supplies a newer price.
    private static let astraPrice = Price(input: 10.0, output: 50.0, cacheRead: 1.0, cacheWrite: 12.50)
    // GPT-5.6 Sol's current official API Standard rates, in USD per million
    // tokens. OpenAI documents cache writes as 1.25x the uncached input rate.
    private static let solPrice = Price(input: 4.0, output: 20.0, cacheRead: 0.4, cacheWrite: 5.0)
    // MiniMax's public price page is denominated in CNY. The dashboard's
    // existing cost column is USD-based, so these are the equivalent standard
    // API rates used by the local Tokei price table: $0.30 / $1.20 / $0.06 per
    // million input / output / cache-read tokens for MiniMax M3.
    private static let builtInProviderPrices: [String: Price] = [
        "openai/gpt-6-astra": astraPrice,
        "openai/gpt-5.6-sol": solPrice,
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

    private struct PricingFileSignature: Equatable {
        let size: Int64
        let modifiedAt: Double
    }

    private struct PricingSourceSignature: Equatable {
        let bundled: PricingFileSignature?
        let home: PricingFileSignature?
        let overrides: PricingFileSignature?
    }

    private struct PricingCatalog {
        let models: [String: Price]
        let aliases: [String: String]
        let sourceSignature: PricingSourceSignature
        let version: String
    }

    // Include the pricing algorithm and long-context threshold in the
    // version. A future formula change therefore revalues existing cached
    // events even when the local pricing file itself did not change.
    private static let pricingRevision = "codex-pricing-v3-long-context-272k"
    private static let longContextThreshold = 272_000
    private static let pricingLock = NSLock()
    private static var pricingCatalog = makePricingCatalog()

    static var currentPriceVersion: String {
        pricingLock.lock()
        defer { pricingLock.unlock() }
        return pricingCatalog.version
    }

    /// Reload pricing sources when Tokei or the app's bundled catalog changes.
    /// This is called once per refresh pass, before provider adapters run in
    /// parallel, so all estimates in that pass share one price version.
    static func refresh() {
        let signature = currentPricingSourceSignature()
        pricingLock.lock()
        let unchanged = pricingCatalog.sourceSignature == signature
        pricingLock.unlock()
        guard !unchanged else { return }

        let rebuilt = makePricingCatalog(sourceSignature: signature)
        pricingLock.lock()
        if pricingCatalog.sourceSignature != signature {
            pricingCatalog = rebuilt
        }
        pricingLock.unlock()
    }

    private static func makePricingCatalog(
        sourceSignature suppliedSignature: PricingSourceSignature? = nil
    ) -> PricingCatalog {
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
            "k3-agent": "moonshotai/kimi-k3",
            "k3-agent-swarm": "moonshotai/kimi-k3",
            "kimi/k3-agent": "moonshotai/kimi-k3",
            "kimi/k3-agent-swarm": "moonshotai/kimi-k3",
            "hy3": "tencent/hy3",
            "hy3-preview": "tencent/hy3-preview",
            "qwen/qwen3.8-max": "qwen3.8-max",
            "qwen/qwen3.8-max-preview": "qwen3.8-max-preview",
            "deepseek/deepseek-v4-flash": "deepseek-v4-flash",
            "deepseek/deepseek-v4-flash-0731": "deepseek-v4-flash-0731",
            "z-ai/glm-5.2": "glm-5.2",
            "zai/glm-5.2": "glm-5.2"
        ]

        let urls = pricingURLs()
        let homePricing = urls.home
        let homeOverrides = urls.overrides
        let bundledPricing = urls.bundled

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

        // Ship the current Tokei snapshot with the app so a fresh install
        // still has model prices. A user's home table remains authoritative
        // and is loaded afterwards, preserving the existing override flow.
        if let bundledPricing {
            loadModels(from: bundledPricing)
        }
        loadModels(from: homePricing)
        // The shared Tokei catalog can lag behind OpenAI's official prices.
        // Keep verified OpenAI values authoritative over that catalog while
        // allowing an explicit pricing_overrides.json entry to opt in to a
        // custom value.
        models["openai/gpt-6-astra"] = astraPrice
        models["openai/gpt-5.6-sol"] = solPrice
        loadOverrides(from: homeOverrides)
        let sourceSignature = suppliedSignature ?? currentPricingSourceSignature()
        return PricingCatalog(
            models: models,
            aliases: aliases,
            sourceSignature: sourceSignature,
            version: makePricingVersion(
                models: models,
                aliases: aliases,
                sourceSignature: sourceSignature
            )
        )
    }

    private static func pricingURLs() -> (bundled: URL?, home: URL, overrides: URL) {
        let homePricing = AppPaths.home
            .appendingPathComponent(".tokei", isDirectory: true)
            .appendingPathComponent("pricing.json")
        let homeOverrides = AppPaths.home
            .appendingPathComponent(".tokei", isDirectory: true)
            .appendingPathComponent("pricing_overrides.json")
        return (
            Bundle.main.url(forResource: "pricing", withExtension: "json"),
            homePricing,
            homeOverrides
        )
    }

    private static func currentPricingSourceSignature() -> PricingSourceSignature {
        let urls = pricingURLs()
        return PricingSourceSignature(
            bundled: fileSignature(at: urls.bundled),
            home: fileSignature(at: urls.home),
            overrides: fileSignature(at: urls.overrides)
        )
    }

    private static func fileSignature(at url: URL?) -> PricingFileSignature? {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(
                  forKeys: [.fileSizeKey, .contentModificationDateKey]
              ),
              let modifiedAt = values.contentModificationDate else {
            return nil
        }
        return PricingFileSignature(
            size: Int64(values.fileSize ?? 0),
            modifiedAt: modifiedAt.timeIntervalSince1970
        )
    }

    private static func makePricingVersion(
        models: [String: Price],
        aliases: [String: String],
        sourceSignature: PricingSourceSignature
    ) -> String {
        var material = [pricingRevision]
        for model in models.keys.sorted() {
            guard let price = models[model] else { continue }
            material.append(
                "model|\(model)|\(price.input)|\(price.output)|\(price.cacheRead)|\(price.cacheWrite)"
            )
        }
        for alias in aliases.keys.sorted() {
            guard let target = aliases[alias] else { continue }
            material.append("alias|\(alias)|\(target)")
        }
        material.append("bundled|\(signatureDescription(sourceSignature.bundled))")
        material.append("home|\(signatureDescription(sourceSignature.home))")
        material.append("overrides|\(signatureDescription(sourceSignature.overrides))")
        return stableFingerprint(material.joined(separator: "\n"))
    }

    private static func signatureDescription(_ signature: PricingFileSignature?) -> String {
        guard let signature else { return "missing" }
        return "\(signature.size):\(signature.modifiedAt)"
    }

    private static func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

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
        outputTokens: Int,
        cacheWriteInputTokens: Int = 0
    ) -> Double {
        let price = resolvedPrice(for: model)
        let totalInput = max(inputTokens, 0)
        let cachedInput = min(max(cachedInputTokens, 0), totalInput)
        let cacheWrite = min(max(cacheWriteInputTokens, 0), max(totalInput - cachedInput, 0))
        let uncachedInput = max(totalInput - cachedInput - cacheWrite, 0)
        let highContext = totalInput > longContextThreshold
        let inputPrice = price.input * (highContext ? 2 : 1)
        let cachePrice = price.cacheRead * (highContext ? 2 : 1)
        let cacheWritePrice = price.cacheWrite * (highContext ? 2 : 1)
        let outputPrice = price.output * (highContext ? 1.5 : 1)
        return Double(uncachedInput) / 1_000_000 * inputPrice
            + Double(cachedInput) / 1_000_000 * cachePrice
            + Double(cacheWrite) / 1_000_000 * cacheWritePrice
            + Double(max(outputTokens, 0)) / 1_000_000 * outputPrice
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
        pricingLock.lock()
        let catalog = pricingCatalog
        pricingLock.unlock()
        return resolvedPrice(for: rawModel, in: catalog)
    }

    private static func resolvedPrice(
        for rawModel: String,
        in catalog: PricingCatalog
    ) -> Price {
        if let price = knownPrice(for: rawModel, in: catalog) { return price }

        // Tokei falls back conservatively to the current GPT-5 family price
        // when a Codex model is not present in the local price table.
        return catalog.models[defaultID] ?? defaultPrice
    }

    private static func knownPrice(for rawModel: String) -> Price? {
        pricingLock.lock()
        let catalog = pricingCatalog
        pricingLock.unlock()
        return knownPrice(for: rawModel, in: catalog)
    }

    private static func knownPrice(
        for rawModel: String,
        in catalog: PricingCatalog
    ) -> Price? {
        let normalized = normalize(rawModel)
        if let alias = catalog.aliases[rawModel.lowercased()],
           let price = catalog.models[alias] {
            return price
        }
        return catalog.models[normalized]
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
        let totalCacheWrite: Int
        let totalOutput: Int
        let totalReasoning: Int
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
        let reasoning: Int
    }

    private struct CodexEvent: Codable, Equatable {
        let timestamp: Double
        let dateKey: String
        let totalInput: Int?
        let totalCached: Int?
        let totalCacheWrite: Int?
        let totalOutput: Int?
        let totalReasoning: Int?
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
        let reasoning: Int
        let cost: Double
        let model: String
        let priceVersion: String

        var totalKey: EventKey? {
            guard let totalInput, let totalCached, let totalOutput, let totalReasoning else { return nil }
            return EventKey(
                totalInput: totalInput,
                totalCached: totalCached,
                totalCacheWrite: totalCacheWrite ?? 0,
                totalOutput: totalOutput,
                totalReasoning: totalReasoning,
                input: input,
                cached: cached,
                cacheWrite: cacheWrite,
                output: output,
                reasoning: reasoning
            )
        }

        var tokenBreakdown: TokenBreakdown {
            TokenBreakdown(
                input: Double(input),
                output: Double(output),
                total: Double(input + cached + cacheWrite + output),
                cacheRead: Double(cached),
                cacheWrite: Double(cacheWrite),
                reasoning: Double(reasoning)
            )
        }

        func repriced(using version: String) -> CodexEvent {
            CodexEvent(
                timestamp: timestamp,
                dateKey: dateKey,
                totalInput: totalInput,
                totalCached: totalCached,
                totalCacheWrite: totalCacheWrite,
                totalOutput: totalOutput,
                totalReasoning: totalReasoning,
                input: input,
                cached: cached,
                cacheWrite: cacheWrite,
                output: output,
                reasoning: reasoning,
                cost: CodexPricing.cost(
                    model: model,
                    inputTokens: input + cached + cacheWrite,
                    cachedInputTokens: cached,
                    outputTokens: output,
                    cacheWriteInputTokens: cacheWrite
                ),
                model: model,
                priceVersion: version
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

    private struct LoadedCache {
        let files: [String: FileEntry]
        let pricingVersion: String
    }

    private struct FileSignature: Codable, Equatable {
        let size: Int64
        let modifiedAt: Double
    }

    private struct ScanCache: Codable {
        let version: Int
        let pricingVersion: String
        let files: [String: FileEntry]
    }

    // This small sidecar lets the common refresh path avoid decoding the
    // complete event cache. It is invalidated by file metadata, pricing, or
    // calendar-day changes, so cached summaries never hide a changed log.
    private struct SummaryCache: Codable {
        let version: Int
        let pricingVersion: String
        let contextKey: String
        let files: [String: FileSignature]
        let summary: LocalUsageSummary
        let latestQuota: CodexQuotaSnapshot?
        let recognizedEventCount: Int
    }

    // Version 4 rebuilds the event cache after fixing incremental overlap
    // matching. Older entries may contain the same token_count event more
    // than once when the pricing catalog changed between refreshes.
    private static let cacheVersion = 4
    private static let cacheURL = AppPaths.appSupport.appendingPathComponent("codex-scan-cache.json")
    private static let summaryCacheVersion = 2
    private static let summaryCacheURL = AppPaths.appSupport.appendingPathComponent("codex-summary-cache.json")
    private static let incrementalOverlapBytes: Int64 = 2 * 1024 * 1024
    private static let tokenMarker = Data("\"token_count\"".utf8)
    private static let modelMarker = Data("\"turn_context\"".utf8)
    private static let sessionMarker = Data("\"session_meta\"".utf8)

    static func scan() -> CodexUsageScanResult {
        CodexPricing.refresh()
        let pricingVersion = CodexPricing.currentPriceVersion
        let files = rolloutFiles()
        let fileSignatures = signatures(for: files)
        let contextKey = summaryContextKey()

        // Most refreshes only need to check file metadata. Reuse the already
        // aggregated result instead of decoding and replaying every event.
        if let cachedSummary = loadSummaryCache(),
           cachedSummary.version == summaryCacheVersion,
           cachedSummary.pricingVersion == pricingVersion,
           cachedSummary.contextKey == contextKey,
           cachedSummary.files == fileSignatures {
            return CodexUsageScanResult(
                summary: cachedSummary.summary,
                latestQuota: cachedSummary.latestQuota,
                hasRolloutFiles: !files.isEmpty,
                recognizedEventCount: cachedSummary.recognizedEventCount
            )
        }

        let loadedCache = loadCache()
        let previous = loadedCache?.files ?? [:]
        let pricingChanged = loadedCache?.pricingVersion != pricingVersion
        let filesChanged = loadedCache == nil
            || previous.count != fileSignatures.count
            || fileSignatures.contains { path, signature in
                guard let cached = previous[path] else { return true }
                return cached.size != signature.size || cached.modifiedAt != signature.modifiedAt
            }
        let cacheNeedsSave = filesChanged || pricingChanged
        var current: [String: FileEntry] = [:]

        for url in files {
            let path = url.path
            let signature = fileSignatures[path] ?? FileSignature(size: 0, modifiedAt: 0)
            let size = signature.size
            let modifiedAt = signature.modifiedAt

            if let cached = previous[path], cached.size == size, cached.modifiedAt == modifiedAt {
                current[path] = pricingChanged
                    ? reprice(cached, using: pricingVersion)
                    : cached
            } else if let cached = previous[path],
                      cached.size > 0,
                      size > cached.size {
                let appended = parseAppendedFile(
                    url: url,
                    previous: cached,
                    size: size,
                    modifiedAt: modifiedAt
                )
                current[path] = pricingChanged
                    ? reprice(appended, using: pricingVersion)
                    : appended
            } else {
                current[path] = parseFile(url: url, size: size, modifiedAt: modifiedAt)
            }
        }

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

        if cacheNeedsSave || loadedCache == nil {
            saveCache(
                ScanCache(
                    version: cacheVersion,
                    pricingVersion: pricingVersion,
                    files: current
                )
            )
        }
        saveSummaryCache(
            SummaryCache(
                version: summaryCacheVersion,
                pricingVersion: pricingVersion,
                contextKey: contextKey,
                files: fileSignatures,
                summary: summary,
                latestQuota: latestQuota,
                recognizedEventCount: recognizedEventCount
            )
        )

        return CodexUsageScanResult(
            summary: summary,
            latestQuota: latestQuota,
            hasRolloutFiles: !files.isEmpty,
            recognizedEventCount: recognizedEventCount
        )
    }

    private static func parseAppendedFile(
        url: URL,
        previous: FileEntry,
        size: Int64,
        modifiedAt: Double
    ) -> FileEntry {
        let offset = max(0, previous.size - incrementalOverlapBytes)
        let tail = parseFile(
            url: url,
            size: size,
            modifiedAt: modifiedAt,
            fromOffset: offset,
            initial: previous
        )
        let overlap = sharedSuffixPrefixCount(previous.events, tail.events)
        let events = previous.events + tail.events.dropFirst(overlap)

        return FileEntry(
            size: size,
            modifiedAt: modifiedAt,
            sessionID: tail.sessionID ?? previous.sessionID,
            forkedFromID: tail.forkedFromID ?? previous.forkedFromID,
            events: events,
            latestQuota: tail.latestQuota ?? previous.latestQuota
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

    private static func signatures(for urls: [URL]) -> [String: FileSignature] {
        var result: [String: FileSignature] = [:]
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            result[url.path] = FileSignature(
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            )
        }
        return result
    }

    private static func summaryContextKey() -> String {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return [
            calendar.timeZone.identifier,
            String(calendar.timeZone.secondsFromGMT(for: now)),
            String(components.year ?? 0),
            String(components.month ?? 0),
            String(components.day ?? 0)
        ].joined(separator: "|")
    }

    private static func loadCache() -> LoadedCache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ScanCache.self, from: data),
              cache.version == cacheVersion else { return nil }
        return LoadedCache(files: cache.files, pricingVersion: cache.pricingVersion)
    }

    private static func loadSummaryCache() -> SummaryCache? {
        guard let data = try? Data(contentsOf: summaryCacheURL) else { return nil }
        return try? JSONDecoder().decode(SummaryCache.self, from: data)
    }

    private static func reprice(_ entry: FileEntry, using version: String) -> FileEntry {
        var didChange = false
        let events = entry.events.map { event -> CodexEvent in
            guard event.priceVersion != version else { return event }
            didChange = true
            return event.repriced(using: version)
        }
        guard didChange else { return entry }
        return FileEntry(
            size: entry.size,
            modifiedAt: entry.modifiedAt,
            sessionID: entry.sessionID,
            forkedFromID: entry.forkedFromID,
            events: events,
            latestQuota: entry.latestQuota
        )
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

    private static func saveSummaryCache(_ cache: SummaryCache) {
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: summaryCacheURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: summaryCacheURL.path
            )
        } catch {
            // The sidecar is an optimization; the event cache remains the
            // authoritative fallback when it cannot be written.
        }
    }

    private static func parseFile(
        url: URL,
        size: Int64,
        modifiedAt: Double,
        fromOffset: Int64 = 0,
        initial: FileEntry? = nil
    ) -> FileEntry {
        var sessionID = initial?.sessionID
        var forkedFromID = initial?.forkedFromID
        var currentModel = initial?.events.last?.model
        var previousTotalKey = initial?.events.last?.totalKey
        var events: [CodexEvent] = []
        var latestQuota = initial?.latestQuota
        let fallbackDate = Date(timeIntervalSince1970: modifiedAt)

        forEachLine(at: url, fromOffset: fromOffset) { line in
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
            let rawCached = CodexUsageScanner.integer(last["cached_input_tokens"])
            let rawCacheWrite = CodexUsageScanner.integer(last["cache_write_input_tokens"])
            let cached = min(rawCached, rawInput)
            let cacheWrite = min(rawCacheWrite, max(rawInput - cached, 0))
            let output = CodexUsageScanner.integer(last["output_tokens"])
            let reasoning = CodexUsageScanner.integer(last["reasoning_output_tokens"])
            let total = info["total_token_usage"] as? [String: Any]
            let totalKey: EventKey?
            if let total {
                totalKey = EventKey(
                    totalInput: CodexUsageScanner.integer(total["input_tokens"]),
                    totalCached: CodexUsageScanner.integer(total["cached_input_tokens"]),
                    totalCacheWrite: CodexUsageScanner.integer(total["cache_write_input_tokens"]),
                    totalOutput: CodexUsageScanner.integer(total["output_tokens"]),
                    totalReasoning: CodexUsageScanner.integer(total["reasoning_output_tokens"]),
                    input: rawInput,
                    cached: cached,
                    cacheWrite: cacheWrite,
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
                totalCacheWrite: total?["cache_write_input_tokens"].flatMap(CodexUsageScanner.integer),
                totalOutput: total?["output_tokens"].flatMap(CodexUsageScanner.integer),
                totalReasoning: total?["reasoning_output_tokens"].flatMap(CodexUsageScanner.integer),
                input: max(rawInput - cached - cacheWrite, 0),
                cached: cached,
                cacheWrite: cacheWrite,
                output: output,
                reasoning: reasoning,
                cost: CodexPricing.cost(
                    model: model,
                    inputTokens: rawInput,
                    cachedInputTokens: cached,
                    outputTokens: output,
                    cacheWriteInputTokens: cacheWrite
                ),
                model: model,
                priceVersion: CodexPricing.currentPriceVersion
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

    private static func forEachLine(
        at url: URL,
        fromOffset: Int64 = 0,
        body: (Data) -> Void
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        if fromOffset > 0 {
            do {
                try handle.seek(toOffset: UInt64(fromOffset))
            } catch {
                return
            }
        }

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

    private static func sharedSuffixPrefixCount(
        _ existing: [CodexEvent],
        _ incoming: [CodexEvent]
    ) -> Int {
        let maximum = min(existing.count, incoming.count)
        guard maximum > 0 else { return 0 }

        for count in stride(from: maximum, through: 1, by: -1) {
            var matches = true
            for index in 0..<count {
                if !sameLogicalEvent(
                    existing[existing.count - count + index],
                    incoming[index]
                ) {
                    matches = false
                    break
                }
            }
            if matches { return count }
        }
        return 0
    }

    /// `parseAppendedFile` may read the overlap with a different pricing
    /// catalog than the cached prefix. Cost and priceVersion are presentation
    /// values, so they must not prevent the same cumulative token event from
    /// matching across refreshes.
    private static func sameLogicalEvent(_ lhs: CodexEvent, _ rhs: CodexEvent) -> Bool {
        if let lhsKey = lhs.totalKey, let rhsKey = rhs.totalKey {
            return lhsKey == rhsKey
        }
        return lhs.timestamp == rhs.timestamp
            && lhs.dateKey == rhs.dateKey
            && lhs.totalInput == rhs.totalInput
            && lhs.totalCached == rhs.totalCached
            && lhs.totalCacheWrite == rhs.totalCacheWrite
            && lhs.totalOutput == rhs.totalOutput
            && lhs.totalReasoning == rhs.totalReasoning
            && lhs.input == rhs.input
            && lhs.cached == rhs.cached
            && lhs.cacheWrite == rhs.cacheWrite
            && lhs.output == rhs.output
            && lhs.reasoning == rhs.reasoning
            && lhs.model == rhs.model
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
        let resetCreditsAvailableCount = CodexResetCreditsParser.availableCount(in: object)
        guard !windows.isEmpty || resetCreditsAvailableCount != nil else { return nil }
        let resetCreditsExpiresAt = CodexResetCreditsParser.earliestExpiresAt(in: object)

        let credits = object["credits"] as? [String: Any]
        return CodexQuotaSnapshot(
            windows: windows,
            planType: LocalData.string(object["plan_type"] ?? object["planType"]),
            creditsBalance: LocalData.number(credits?["balance"] ?? object["credits_balance"]),
            resetCreditsAvailableCount: resetCreditsAvailableCount,
            resetCreditsExpiresAt: resetCreditsExpiresAt,
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
    // The dashboard refreshes every 30 seconds. Keep the successful quota
    // cache shorter than that interval so a refresh does not routinely reuse
    // a several-minute-old 5-hour balance.
    private static let successfulCacheTTL: TimeInterval = 15
    private static let failedCacheTTL: TimeInterval = 15
    private static var memory: PersistedCache?

    static func fetchLive(forceRefresh: Bool = false) async -> CodexQuotaFetchResult? {
        let now = Date()
        let cache = loadCache()
        if !forceRefresh,
           let cache,
           now.timeIntervalSince(cache.fetchedAt) < successfulCacheTTL {
            return CodexQuotaFetchResult(snapshot: cache.snapshot, source: .cached)
        }
        if !forceRefresh,
           let cache,
           let lastFailureAt = cache.lastFailureAt,
           now.timeIntervalSince(lastFailureAt) < failedCacheTTL,
           now.timeIntervalSince(cache.fetchedAt) < failedCacheTTL {
            return CodexQuotaFetchResult(snapshot: cache.snapshot, source: .cached)
        }
        guard let auth = authContext() else {
            return cache.map { CodexQuotaFetchResult(snapshot: $0.snapshot, source: .cached) }
        }

        var components = URLComponents(string: "https://chatgpt.com/backend-api/wham/usage")
        components?.queryItems = [
            URLQueryItem(
                name: "_ai_usage_bar_refresh",
                value: String(Int(now.timeIntervalSince1970))
            )
        ]
        guard let url = components?.url else { return nil }
        var resetCreditsComponents = URLComponents(
            string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
        )
        resetCreditsComponents?.queryItems = components?.queryItems
        let resetCreditsURL = resetCreditsComponents?.url
        do {
            let headers: [String: String] = {
                var headers = [
                    "Authorization": "Bearer \(auth.token)",
                    "User-Agent": "AIUsageBar/0.1",
                    "Cache-Control": "no-cache"
                ]
                if let accountID = auth.accountID {
                    headers["ChatGPT-Account-Id"] = accountID
                }
                return headers
            }()
            async let resetCredits = fetchResetCredits(
                url: resetCreditsURL,
                headers: headers,
                now: now
            )
            let result = try await HTTPJSON.get(
                url: url,
                headers: headers,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
            let resetCreditsSummary = await resetCredits
            guard (200..<300).contains(result.statusCode),
                  let snapshot = parseLiveResponse(
                      result.object,
                      updatedAt: now,
                      resetCreditsSummary: resetCreditsSummary
                  ) else {
                throw URLError(.badServerResponse)
            }
            saveCache(PersistedCache(snapshot: snapshot, fetchedAt: now, lastFailureAt: nil))
            return CodexQuotaFetchResult(snapshot: snapshot, source: .server)
        } catch {
            let failed = PersistedCache(
                snapshot: cache?.snapshot ?? CodexQuotaSnapshot(
                    windows: [],
                    planType: nil,
                    creditsBalance: nil,
                    resetCreditsAvailableCount: nil,
                    resetCreditsExpiresAt: nil,
                    updatedAt: now
                ),
                fetchedAt: cache?.fetchedAt ?? .distantPast,
                lastFailureAt: now
            )
            if cache != nil { saveCache(failed) }
            return cache.map { CodexQuotaFetchResult(snapshot: $0.snapshot, source: .cached) }
        }
    }

    private static func fetchResetCredits(
        url: URL?,
        headers: [String: String],
        now: Date
    ) async -> CodexResetCreditsParser.Summary? {
        guard let url else { return nil }
        do {
            let result = try await HTTPJSON.get(
                url: url,
                headers: headers,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 2
            )
            guard (200..<300).contains(result.statusCode),
                  result.object is [String: Any] else {
                return nil
            }
            return CodexResetCreditsParser.summary(in: result.object, now: now)
        } catch {
            return nil
        }
    }

    private static func parseLiveResponse(
        _ value: Any,
        updatedAt: Date,
        resetCreditsSummary: CodexResetCreditsParser.Summary?
    ) -> CodexQuotaSnapshot? {
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
        let inlineResetCredits = CodexResetCreditsParser.summary(in: root, now: updatedAt)
        let resetCreditsAvailableCount = resetCreditsSummary?.availableCount
            ?? inlineResetCredits.availableCount
        let resetCreditsExpiresAt: Date?
        if let resetCreditsSummary {
            resetCreditsExpiresAt = resetCreditsSummary.earliestExpiresAt
        } else {
            resetCreditsExpiresAt = inlineResetCredits.earliestExpiresAt
        }
        guard !windows.isEmpty || resetCreditsAvailableCount != nil else { return nil }
        let credits = root["credits"] as? [String: Any]
        return CodexQuotaSnapshot(
            windows: windows,
            planType: LocalData.string(root["plan_type"] ?? root["planType"] ?? rateLimit["plan_type"]),
            creditsBalance: LocalData.number(credits?["balance"] ?? root["credits_balance"]),
            resetCreditsAvailableCount: resetCreditsAvailableCount,
            resetCreditsExpiresAt: resetCreditsExpiresAt,
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
