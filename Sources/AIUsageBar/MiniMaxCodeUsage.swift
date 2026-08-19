import Foundation

/// A read-only view of MiniMax Code's local usage ledger.
///
/// MiniMax Code currently persists one row per model response in
/// `~/.minimax/v2/sqlite/runtime-state.sqlite`.  Keeping this adapter separate
/// from the browser-cache reader is important: cache records can contain
/// duplicated UI state, while the runtime ledger has the token breakdown that
/// the MiniMax client itself records.
struct MiniMaxCodeScanResult {
    let summary: LocalUsageSummary
    let recognizedEventCount: Int
    let hasDatabase: Bool
    let hasSessionFiles: Bool
}

enum MiniMaxCodeUsageScanner {
    static func scan() -> MiniMaxCodeScanResult {
        let hasDatabase = FileManager.default.fileExists(atPath: AppPaths.miniMaxRuntimeDatabase.path)
        let hasSessionFiles = containsSessionFiles()
        let configuredModel = configuredModel()

        if hasDatabase {
            let databaseScan = scanDatabase(defaultModel: configuredModel)
            if databaseScan.recognizedEventCount > 0 {
                return MiniMaxCodeScanResult(
                    summary: databaseScan.summary,
                    recognizedEventCount: databaseScan.recognizedEventCount,
                    hasDatabase: true,
                    hasSessionFiles: hasSessionFiles
                )
            }
        }

        let sessionScan = scanSessionFiles(defaultModel: configuredModel)
        return MiniMaxCodeScanResult(
            summary: sessionScan.summary,
            recognizedEventCount: sessionScan.recognizedEventCount,
            hasDatabase: hasDatabase,
            hasSessionFiles: hasSessionFiles
        )
    }

    private static func scanDatabase(defaultModel: String?) -> (summary: LocalUsageSummary, recognizedEventCount: Int) {
        let rows = SQLiteReader.query(
            databaseURL: AppPaths.miniMaxRuntimeDatabase,
            sql: """
            SELECT id, session_id, agent_name, framework_type, model, ts,
                   input_tokens, output_tokens, reasoning_tokens,
                   cache_read_tokens, cache_write_tokens, cost_usd, raw
            FROM local_runtime_token_usage
            ORDER BY ts ASC
            """
        )

        var summary = LocalUsageSummary()
        var recognizedEventCount = 0
        for row in rows {
            guard let tokens = tokenBreakdown(in: row) else { continue }
            let date = LocalData.date(row["ts"])
                ?? LocalData.firstDate(in: row, keys: ["timestamp", "createdat", "updatedat", "time"])
                ?? Date()
            let model = normalizedModel(LocalData.string(row["model"])) ?? defaultModel
            let recordedCost = cost(in: row)
            let cost = recordedCost > 0
                ? recordedCost
                : estimatedCost(model: model, tokens: tokens)

            // MiniMax's runtime table is already one row per model response.
            // Do not pass sessionID here: the dashboard's request metric should
            // show response/request rows rather than collapsing a long coding
            // session into the number 1.
            summary.add(
                date: date,
                tokens: tokens,
                requests: 1,
                cost: cost,
                model: model
            )
            recognizedEventCount += 1
        }
        return (summary, recognizedEventCount)
    }

    private static func scanSessionFiles(defaultModel: String?) -> (summary: LocalUsageSummary, recognizedEventCount: Int) {
        let records = LocalData.jsonLines(
            under: [AppPaths.miniMaxSessions],
            maxFiles: 500,
            maxLinesPerFile: 20_000,
            modifiedAfter: LocalData.previousMonthStart
        )
        var summary = LocalUsageSummary()
        var recognizedEventCount = 0
        for record in records {
            guard let usage = LocalData.firstObject(in: record.object, keys: ["usage"]),
                  let tokens = tokenBreakdown(in: usage)
            else { continue }

            let date = LocalData.firstDate(
                in: record.object,
                keys: ["timestamp", "createdat", "updatedat", "time", "ts"]
            ) ?? record.fallbackDate
            let model = normalizedModel(LocalData.modelName(in: record.object)) ?? defaultModel
            let recordedCost = cost(in: record.object)
            let cost = recordedCost > 0
                ? recordedCost
                : estimatedCost(model: model, tokens: tokens)
            summary.add(
                date: date,
                tokens: tokens,
                requests: 1,
                cost: cost,
                model: model
            )
            recognizedEventCount += 1
        }
        return (summary, recognizedEventCount)
    }

    private static func tokenBreakdown(in row: [String: Any]) -> TokenBreakdown? {
        let rawObject: [String: Any]? = {
            if let raw = LocalData.string(row["raw"]),
               let parsed = LocalData.parseJSON(string: raw) as? [String: Any] {
                return parsed
            }
            return row["raw"] as? [String: Any]
        }()

        let input = max(
            LocalData.number(row["input_tokens"])
                ?? rawObject.flatMap { LocalData.firstNumber(in: $0, keys: ["inputtokens", "input"]) }
                ?? 0,
            0
        )
        let output = max(
            LocalData.number(row["output_tokens"])
                ?? rawObject.flatMap { LocalData.firstNumber(in: $0, keys: ["outputtokens", "output"]) }
                ?? 0,
            0
        )
        let reasoning = max(
            LocalData.number(row["reasoning_tokens"])
                ?? rawObject.flatMap { LocalData.firstNumber(in: $0, keys: ["reasoningtokens", "reasoning"]) }
                ?? 0,
            0
        )
        let cacheRead = max(
            LocalData.number(row["cache_read_tokens"])
                ?? rawObject.flatMap { LocalData.firstNumber(in: $0, keys: ["cachereadtokens", "cacheread"]) }
                ?? 0,
            0
        )
        let cacheWrite = max(
            LocalData.number(row["cache_write_tokens"])
                ?? rawObject.flatMap { LocalData.firstNumber(in: $0, keys: ["cachewritetokens", "cachewrite"]) }
                ?? 0,
            0
        )
        let explicitTotal = rawObject.flatMap {
            LocalData.firstNumber(in: $0, keys: ["totaltokens", "total"])
        }
        let total = max(explicitTotal ?? (input + output + cacheRead + cacheWrite), 0)
        let result = TokenBreakdown(
            input: input,
            output: output,
            total: total,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            reasoning: reasoning
        )
        return result.hasTokens ? result : nil
    }

    private static func tokenBreakdown(in value: Any) -> TokenBreakdown? {
        guard let object = value as? [String: Any] else { return nil }
        return tokenBreakdown(in: object)
    }

    private static func cost(in row: [String: Any]) -> Double {
        if let value = LocalData.number(row["cost_usd"]) {
            let normalized = max(value, 0)
            if normalized > 0 { return normalized }
        }
        let rawObject: [String: Any]? = {
            if let raw = LocalData.string(row["raw"]),
               let parsed = LocalData.parseJSON(string: raw) as? [String: Any] {
                return parsed
            }
            return row["raw"] as? [String: Any]
        }()
        return cost(in: rawObject)
    }

    private static func cost(in value: Any?) -> Double {
        guard let value else { return 0 }
        let costObject = LocalData.firstObject(in: value, keys: ["cost"])
        let costValue = costObject.flatMap {
            LocalData.firstNumber(in: $0, keys: ["total", "totalusd", "costusd"])
        } ?? LocalData.firstNumber(in: value, keys: ["costusd", "cost"])
        return max(costValue ?? 0, 0)
    }

    private static func estimatedCost(model: String?, tokens: TokenBreakdown) -> Double {
        guard let model, tokens.hasTokens else { return 0 }
        return CodexPricing.estimatedCost(
            model: model,
            inputTokens: tokens.input + tokens.cacheRead + tokens.cacheWrite,
            cachedInputTokens: tokens.cacheRead,
            outputTokens: tokens.output,
            cacheWriteTokens: tokens.cacheWrite
        ) ?? 0
    }

    private static func configuredModel() -> String? {
        let configURL = AppPaths.miniMaxRoot.appendingPathComponent("config.yaml")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("defaultmodel:") else { continue }
            let rawValue = String(trimmed.dropFirst("defaultModel:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedModel(
                rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            )
        }
        return nil
    }

    private static func normalizedModel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let slash = trimmed.lastIndex(of: "/") {
            let suffix = String(trimmed[trimmed.index(after: slash)...])
            if !suffix.isEmpty { return suffix }
        }
        return trimmed
    }

    private static func containsSessionFiles() -> Bool {
        guard FileManager.default.fileExists(atPath: AppPaths.miniMaxSessions.path),
              let enumerator = FileManager.default.enumerator(
                  at: AppPaths.miniMaxSessions,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsPackageDescendants]
              )
        else { return false }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "jsonl" {
                return true
            }
        }
        return false
    }
}
