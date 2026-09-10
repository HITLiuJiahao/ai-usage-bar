import Foundation

struct OpenCodeScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let hasDatabase: Bool
    let latestModel: String?
    let unpricedModels: [String]
}

private struct OpenCodeUsageRow {
    let model: String
    let pricingModel: String
    let sessionID: String?
    let timestamp: Date
    let tokens: TokenBreakdown
    let storedCost: Double?
}

enum OpenCodeUsageScanner {
    // OpenCode's local monitor implementations read message.data rather than
    // prompt/part content. Each assistant message with a token block is one
    // model response and already contains its provider/model metadata.
    private static let messageSQL = """
        SELECT session_id, time_created, data
        FROM message
        ORDER BY time_created ASC;
        """

    static func scan() -> OpenCodeScanResult {
        guard let databaseURL = databaseURL() else {
            return OpenCodeScanResult(
                summary: LocalUsageSummary(),
                responseCount: 0,
                hasDatabase: false,
                latestModel: nil,
                unpricedModels: []
            )
        }

        let rows = SQLiteReader.query(databaseURL: databaseURL, sql: messageSQL)
        var summary = LocalUsageSummary()
        var responseCount = 0
        var latestModel: String?
        var unpricedModels: Set<String> = []

        for object in rows {
            guard let row = parseRow(object) else { continue }
            responseCount += 1
            latestModel = row.model

            let cost = estimateCost(for: row)
            if cost == nil {
                unpricedModels.insert(row.model)
            }

            summary.add(
                date: row.timestamp,
                tokens: row.tokens,
                requests: 1,
                cost: cost ?? 0,
                model: row.model,
                sessionID: row.sessionID
            )
        }

        return OpenCodeScanResult(
            summary: summary,
            responseCount: responseCount,
            hasDatabase: true,
            latestModel: latestModel,
            unpricedModels: unpricedModels.sorted()
        )
    }

    private static func databaseURL() -> URL? {
        AppPaths.openCodeDatabaseCandidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private static func parseRow(_ object: [String: Any]) -> OpenCodeUsageRow? {
        guard let data = LocalData.string(object["data"]),
              let message = LocalData.parseJSON(string: data) as? [String: Any],
              LocalData.string(message["role"])?.lowercased() == "assistant",
              let tokenObject = message["tokens"] as? [String: Any] else {
            return nil
        }

        let cacheObject = tokenObject["cache"] as? [String: Any]
        let input = nonNegativeNumber(tokenObject["input"])
        let output = nonNegativeNumber(tokenObject["output"])
        let reasoning = nonNegativeNumber(tokenObject["reasoning"])
        let cacheRead = firstNumber(
            in: cacheObject,
            keys: ["read", "cacheRead", "cache_read"]
        ) ?? firstNumber(
            in: tokenObject,
            keys: ["cacheRead", "cache_read"]
        ) ?? 0
        let cacheWrite = firstNumber(
            in: cacheObject,
            keys: ["write", "cacheWrite", "cache_write"]
        ) ?? firstNumber(
            in: tokenObject,
            keys: ["cacheWrite", "cache_write"]
        ) ?? 0
        let promptTokens = input + cacheRead + cacheWrite
        let reportedTotal = nonNegativeNumber(tokenObject["total"] ?? message["total"])
        let total = reportedTotal > 0
            ? reportedTotal
            : promptTokens + output + reasoning
        let tokens = TokenBreakdown(
            input: input,
            output: output,
            total: total,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            reasoning: reasoning,
            inputIncludesCache: false
        )
        guard tokens.hasTokens else { return nil }

        let modelObject = message["model"] as? [String: Any]
        let rawModel = LocalData.string(message["modelID"])
            ?? LocalData.string(message["model_id"])
            ?? LocalData.string(modelObject?["modelID"])
            ?? LocalData.string(modelObject?["model_id"])
        let modelID = ModelUsage.normalizedName(rawModel)
        let rawProvider = LocalData.string(message["providerID"])
            ?? LocalData.string(message["provider_id"])
            ?? LocalData.string(modelObject?["providerID"])
            ?? LocalData.string(modelObject?["provider_id"])
        let providerID = rawProvider?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayModel: String
        if let providerID, !providerID.isEmpty, !modelID.contains("/") {
            displayModel = "\(providerID)/\(modelID)"
        } else {
            displayModel = modelID
        }

        let timeObject = message["time"] as? [String: Any]
        let timestamp = LocalData.date(
            timeObject?["created"] ?? timeObject?["completed"]
        ) ?? LocalData.date(object["time_created"])
        guard let timestamp else { return nil }

        let storedCost: Double?
        if let value = LocalData.number(message["cost"]), value.isFinite, value > 0 {
            storedCost = value
        } else {
            storedCost = nil
        }

        return OpenCodeUsageRow(
            model: displayModel,
            pricingModel: modelID,
            sessionID: LocalData.string(object["session_id"]),
            timestamp: timestamp,
            tokens: tokens,
            storedCost: storedCost
        )
    }

    private static func estimateCost(for row: OpenCodeUsageRow) -> Double? {
        if let storedCost = row.storedCost {
            return storedCost
        }

        let promptTokens = row.tokens.input + row.tokens.cacheRead + row.tokens.cacheWrite
        let outputTokens = row.tokens.output + row.tokens.reasoning
        let cachedInputTokens = row.tokens.cacheRead
        return CodexPricing.estimatedCost(
            model: row.pricingModel,
            inputTokens: promptTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: row.tokens.cacheWrite
        ) ?? CodexPricing.estimatedCost(
            model: row.model,
            inputTokens: promptTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: row.tokens.cacheWrite
        )
    }

    private static func firstNumber(
        in object: [String: Any]?,
        keys: [String]
    ) -> Double? {
        guard let object else { return nil }
        for key in keys {
            if let number = LocalData.number(object[key]), number.isFinite {
                return max(number, 0)
            }
        }
        return nil
    }

    private static func nonNegativeNumber(_ value: Any?) -> Double {
        guard let number = LocalData.number(value), number.isFinite else { return 0 }
        return max(number, 0)
    }
}
