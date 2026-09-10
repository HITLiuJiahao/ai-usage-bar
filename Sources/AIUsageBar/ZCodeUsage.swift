import Foundation

struct ZCodeScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let tokenResponseCount: Int
    let hasDatabase: Bool
    let latestModel: String?
    let unpricedModels: [String]
}

private struct ZCodeUsageRow {
    let model: String
    let sessionID: String?
    let timestamp: Date
    let tokens: TokenBreakdown
}

enum ZCodeUsageScanner {
    // ZCode's model_usage table contains one row per model attempt. The
    // computed total is the app's authoritative total; input_tokens already
    // follows ZCode's prompt-total convention and includes cache fields.
    private static let usageSQL = """
        SELECT
            COALESCE(model_id, '未知') AS model_id,
            session_id,
            started_at,
            input_tokens,
            output_tokens,
            reasoning_tokens,
            cache_creation_input_tokens,
            cache_read_input_tokens,
            computed_total_tokens
        FROM model_usage
        WHERE status IN ('completed', 'error')
          AND (
              input_tokens > 0
              OR output_tokens > 0
              OR reasoning_tokens > 0
              OR cache_creation_input_tokens > 0
              OR cache_read_input_tokens > 0
              OR computed_total_tokens > 0
          )
        ORDER BY started_at ASC;
        """

    static func scan() -> ZCodeScanResult {
        guard let databaseURL = databaseURL() else {
            return ZCodeScanResult(
                summary: LocalUsageSummary(),
                responseCount: 0,
                tokenResponseCount: 0,
                hasDatabase: false,
                latestModel: nil,
                unpricedModels: []
            )
        }

        let rows = SQLiteReader.query(databaseURL: databaseURL, sql: usageSQL)
        var summary = LocalUsageSummary()
        var responseCount = 0
        var tokenResponseCount = 0
        var latestModel: String?
        var unpricedModels: Set<String> = []

        for object in rows {
            guard let row = parseRow(object) else { continue }
            responseCount += 1
            latestModel = row.model
            if row.tokens.hasTokens {
                tokenResponseCount += 1
            }

            let cost = CodexPricing.estimatedCost(
                model: row.model,
                inputTokens: row.tokens.input,
                cachedInputTokens: row.tokens.cacheRead,
                outputTokens: row.tokens.output,
                cacheWriteTokens: row.tokens.cacheWrite
            )
            if row.tokens.hasTokens, cost == nil {
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

        return ZCodeScanResult(
            summary: summary,
            responseCount: responseCount,
            tokenResponseCount: tokenResponseCount,
            hasDatabase: true,
            latestModel: latestModel,
            unpricedModels: unpricedModels.sorted()
        )
    }

    private static func databaseURL() -> URL? {
        AppPaths.zcodeDatabaseCandidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private static func parseRow(_ object: [String: Any]) -> ZCodeUsageRow? {
        guard let timestamp = LocalData.date(object["started_at"]) else { return nil }

        let input = nonNegativeNumber(object["input_tokens"])
        let output = nonNegativeNumber(object["output_tokens"])
        let reasoning = nonNegativeNumber(object["reasoning_tokens"])
        let cacheWrite = nonNegativeNumber(object["cache_creation_input_tokens"])
        let cacheRead = nonNegativeNumber(object["cache_read_input_tokens"])
        let reportedTotal = nonNegativeNumber(object["computed_total_tokens"])
        let total = reportedTotal > 0 ? reportedTotal : input + output
        let tokens = TokenBreakdown(
            input: input,
            output: output,
            total: total,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            reasoning: reasoning,
            inputIncludesCache: true
        )
        guard tokens.hasTokens else { return nil }

        let model = ModelUsage.normalizedName(LocalData.string(object["model_id"]))
        let sessionID = LocalData.string(object["session_id"])
        return ZCodeUsageRow(
            model: model,
            sessionID: sessionID,
            timestamp: timestamp,
            tokens: tokens
        )
    }

    private static func nonNegativeNumber(_ value: Any?) -> Double {
        guard let number = LocalData.number(value), number.isFinite else { return 0 }
        return max(number, 0)
    }
}
