import Foundation

/// Local TraeWork CN usage readout based on the public Trae SOLO CN adapter
/// published by token-monitor. The database is SQLCipher-encrypted, so this
/// reader intentionally requires a user-provided key instead of attempting to
/// extract secrets from the Trae process or its keychain.
struct TraeWorkScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let hasDatabase: Bool
    let keyAvailable: Bool
    let sqlCipherAvailable: Bool
    let failureMessage: String?
    let latestModel: String?
}

private struct TraeWorkUsageEvent {
    let timestamp: Date
    let sessionID: String?
    let model: String
    let tokens: TokenBreakdown
    let source: String
    let rowID: String?
}

private struct TraeWorkSQLCipherResult {
    let succeeded: Bool
    let rows: [[String: Any]]
}

enum TraeWorkUsageScanner {
    private static let keyEnvironmentNames = [
        "AIUSAGEBAR_TRAE_KEY",
        "TOKEN_MONITOR_TRAE_KEY"
    ]

    static func scan() -> TraeWorkScanResult {
        guard let databaseURL = databaseURL() else {
            return TraeWorkScanResult(
                summary: LocalUsageSummary(),
                responseCount: 0,
                hasDatabase: false,
                keyAvailable: false,
                sqlCipherAvailable: false,
                failureMessage: nil,
                latestModel: nil
            )
        }

        guard let key = databaseKey() else {
            return TraeWorkScanResult(
                summary: LocalUsageSummary(),
                responseCount: 0,
                hasDatabase: true,
                keyAvailable: false,
                sqlCipherAvailable: sqlCipherExecutable() != nil,
                failureMessage: nil,
                latestModel: nil
            )
        }

        guard let executable = sqlCipherExecutable() else {
            return TraeWorkScanResult(
                summary: LocalUsageSummary(),
                responseCount: 0,
                hasDatabase: true,
                keyAvailable: true,
                sqlCipherAvailable: false,
                failureMessage: nil,
                latestModel: nil
            )
        }

        let result = query(databaseURL: databaseURL, key: key, executable: executable)
        guard result.succeeded else {
            return TraeWorkScanResult(
                summary: LocalUsageSummary(),
                responseCount: 0,
                hasDatabase: true,
                keyAvailable: true,
                sqlCipherAvailable: true,
                failureMessage: "TraeWork CN 数据库解密失败，或当前版本的 chat_turn/history_v2 字段结构与公开实现不同。",
                latestModel: nil
            )
        }

        let parsedEvents = result.rows.compactMap(parseEvent)
        // When both tables exist, chat_turn is the newer authoritative
        // ledger. Fall back to history_v2 only when chat_turn yielded no
        // usable token rows. This mirrors the public Trae token monitor and
        // prevents counting the same response twice across schema versions.
        let chatEvents = parsedEvents.filter { $0.source == "chat_turn" }
        let sourceEvents = chatEvents.isEmpty
            ? parsedEvents.filter { $0.source == "history_v2" }
            : chatEvents
        var seenRows = Set<String>()
        let events = sourceEvents.filter { event in
            let identity = "\(event.source):\(event.rowID ?? "\(event.timestamp.timeIntervalSince1970):\(event.sessionID ?? ""):\(event.model):\(event.tokens.total)")"
            return seenRows.insert(identity).inserted
        }.sorted { $0.timestamp < $1.timestamp }
        var summary = LocalUsageSummary()
        for event in events {
            summary.add(
                date: event.timestamp,
                tokens: event.tokens,
                requests: 1,
                model: event.model,
                sessionID: event.sessionID
            )
        }
        return TraeWorkScanResult(
            summary: summary,
            responseCount: events.count,
            hasDatabase: true,
            keyAvailable: true,
            sqlCipherAvailable: true,
            failureMessage: nil,
            latestModel: events.last?.model
        )
    }

    private static func databaseURL() -> URL? {
        AppPaths.traeDatabaseCandidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private static func databaseKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in keyEnvironmentNames {
            if let key = normalizedKey(environment[name]) {
                return key
            }
        }

        for url in keyFileCandidates() {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            if let object = LocalData.parseJSON(data: data) {
                if let key = normalizedKey(LocalData.string(object)) {
                    return key
                }
                if let key = normalizedKey(LocalData.firstString(
                    in: object,
                    keys: ["key", "databasekey", "enckey", "traekey"]
                )) {
                    return key
                }
            }
            if let key = normalizedKey(String(data: data, encoding: .utf8)) {
                return key
            }
        }
        return nil
    }

    private static func keyFileCandidates() -> [URL] {
        var urls = [
            AppPaths.appSupport.appendingPathComponent("trae-key.json"),
            AppPaths.appSupport.appendingPathComponent("trae-key.txt")
        ]
        urls.append(contentsOf: AppPaths.traeDatabaseCandidates.map {
            $0.deletingLastPathComponent().appendingPathComponent("trae-key.json")
        })
        urls.append(contentsOf: AppPaths.traeSupportCandidates.map {
            $0.appendingPathComponent("trae-key.json")
        })
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func normalizedKey(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("x'") && value.hasSuffix("'") {
            value = String(value.dropFirst(2).dropLast())
        } else if value.lowercased().hasPrefix("0x") {
            value = String(value.dropFirst(2))
        }
        value = value.filter { !$0.isWhitespace && !$0.isNewline }
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return value.lowercased()
    }

    private static func sqlCipherExecutable() -> URL? {
        var paths = [
            "/opt/homebrew/bin/sqlcipher",
            "/usr/local/bin/sqlcipher",
            "/opt/local/bin/sqlcipher",
            "/usr/bin/sqlcipher"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/sqlcipher" })
        }
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func query(databaseURL: URL, key: String, executable: URL) -> TraeWorkSQLCipherResult {
        let tableResult = runQuery(
            databaseURL: databaseURL,
            key: key,
            executable: executable,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('chat_turn', 'history_v2') ORDER BY name;"
        )
        guard tableResult.succeeded else { return tableResult }

        let tableNames = Set(tableResult.rows.compactMap {
            LocalData.string($0["name"])?.lowercased()
        })
        var selects: [String] = []
        // Read both possible schemas in one SQLCipher session. The caller
        // chooses chat_turn over history_v2 after parsing, so the database is
        // decrypted once and each table is never counted twice.
        if tableNames.contains("chat_turn") {
            selects.append("""
            SELECT 'chat_turn' AS source, rowid AS row_id,
                   NULL AS token_usage, NULL AS messages,
                   session_id, created_at, context
            FROM chat_turn
            WHERE context IS NOT NULL
            """)
        }
        if tableNames.contains("history_v2") {
            selects.append("""
            SELECT 'history_v2' AS source, rowid AS row_id,
                   token_usage, messages, session_id, created_at,
                   NULL AS context
            FROM history_v2
            WHERE token_usage IS NOT NULL
              AND CAST(token_usage AS REAL) > 0
            """)
        }
        guard !selects.isEmpty else {
            return TraeWorkSQLCipherResult(succeeded: true, rows: [])
        }
        return runQuery(
            databaseURL: databaseURL,
            key: key,
            executable: executable,
            sql: selects.joined(separator: " UNION ALL ") + " ORDER BY created_at ASC;"
        )
    }

    private static func runQuery(
        databaseURL: URL,
        key: String,
        executable: URL,
        sql: String
    ) -> TraeWorkSQLCipherResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = [databaseURL.path]
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        let script = """
        PRAGMA key = "x'\(key)'";
        PRAGMA cipher_compatibility = 4;
        .mode json
        \(sql)
        """

        do {
            try process.run()
            input.fileHandleForWriting.write(Data(script.utf8))
            input.fileHandleForWriting.closeFile()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            _ = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let rows = LocalData.parseJSON(data: outputData) as? [[String: Any]]
            else {
                return TraeWorkSQLCipherResult(succeeded: false, rows: [])
            }
            return TraeWorkSQLCipherResult(succeeded: true, rows: rows)
        } catch {
            return TraeWorkSQLCipherResult(succeeded: false, rows: [])
        }
    }

    private static func parseEvent(_ row: [String: Any]) -> TraeWorkUsageEvent? {
        let source = LocalData.string(row["source"]) ?? "history_v2"
        if source == "chat_turn" {
            return parseChatTurn(row)
        }

        guard let timestamp = LocalData.date(row["created_at"]) else { return nil }
        if let usage = LocalData.embeddedJSON(row["token_usage"]) as? [String: Any] {
            return makeEvent(
                usage: usage,
                context: row["messages"],
                timestamp: timestamp,
                sessionID: LocalData.string(row["session_id"]),
                inputIncludesCache: true,
                source: source,
                rowID: LocalData.string(row["row_id"])
            )
        }

        let output = max(LocalData.number(row["token_usage"]) ?? 0, 0)
        guard output > 0 else { return nil }

        let details = messageDetails(row["messages"])
        let input = max(details.input ?? 0, 0)
        let tokens = TokenBreakdown(
            input: input,
            output: output,
            total: input + output
        )
        let sessionID = LocalData.string(row["session_id"])
        return TraeWorkUsageEvent(
            timestamp: timestamp,
            sessionID: sessionID,
            model: details.model ?? "未知",
            tokens: tokens,
            source: source,
            rowID: LocalData.string(row["row_id"])
        )
    }

    private static func parseChatTurn(_ row: [String: Any]) -> TraeWorkUsageEvent? {
        guard let timestamp = LocalData.date(row["created_at"]),
              let context = LocalData.embeddedJSON(row["context"]),
              let usage = LocalData.firstObject(in: context, keys: ["tokenusage"])
        else { return nil }
        return makeEvent(
            usage: usage,
            context: context,
            timestamp: timestamp,
            sessionID: LocalData.string(row["session_id"]),
            inputIncludesCache: true,
            source: "chat_turn",
            rowID: LocalData.string(row["row_id"])
        )
    }

    private static func makeEvent(
        usage: [String: Any],
        context: Any?,
        timestamp: Date,
        sessionID: String?,
        inputIncludesCache: Bool,
        source: String,
        rowID: String?
    ) -> TraeWorkUsageEvent? {
        let input = max(LocalData.firstNumber(
            in: usage,
            keys: ["prompttokens", "inputtokens", "inputtoken"]
        ) ?? 0, 0)
        let output = max(LocalData.firstNumber(
            in: usage,
            keys: ["completiontokens", "outputtokens", "outputtoken"]
        ) ?? 0, 0)
        let total = max(LocalData.firstNumber(
            in: usage,
            keys: ["totaltokens", "totaltoken", "total"]
        ) ?? input + output, 0)
        let cacheRead = max(LocalData.firstNumber(
            in: usage,
            keys: ["cachereadinputtokens", "cachereadtoken"]
        ) ?? 0, 0)
        let cacheWrite = max(LocalData.firstNumber(
            in: usage,
            keys: ["cachecreationinputtokens", "cachecreationtoken", "cachewritetokens"]
        ) ?? 0, 0)
        let reasoning = max(LocalData.firstNumber(
            in: usage,
            keys: ["reasoningtokens", "reasoningtoken"]
        ) ?? 0, 0)
        guard total > 0 || input > 0 || output > 0 else { return nil }

        let model = chatTurnModel(in: context) ?? messageDetails(context).model ?? "未知"
        return TraeWorkUsageEvent(
            timestamp: timestamp,
            sessionID: sessionID,
            model: model,
            tokens: TokenBreakdown(
                input: input,
                output: output,
                total: total > 0 ? total : input + output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                reasoning: reasoning,
                inputIncludesCache: inputIncludesCache
            ),
            source: source,
            rowID: rowID
        )
    }

    private static func chatTurnModel(in value: Any?) -> String? {
        guard let value = LocalData.embeddedJSON(value) else { return nil }
        if let modelInfo = LocalData.firstObject(in: value, keys: ["modelinfo"]),
           let name = LocalData.firstString(
               in: modelInfo,
               keys: ["configname", "modelname", "model", "name"]
           ) {
            return name
        }
        return LocalData.modelName(in: value)
    }

    private static func messageDetails(_ value: Any?) -> (model: String?, input: Double?) {
        guard let root = LocalData.embeddedJSON(value) else { return (nil, nil) }
        var rawMessages: [Any] = []
        if let object = root as? [String: Any] {
            for (key, value) in object where LocalData.normalizedKey(key) == "rawmessages" {
                rawMessages = value as? [Any]
                    ?? (LocalData.embeddedJSON(value) as? [Any] ?? [])
                break
            }
            if rawMessages.isEmpty {
                rawMessages = [object]
            }
        } else if let array = root as? [Any] {
            rawMessages = array
        }

        for rawMessage in rawMessages {
            guard let object = rawMessage as? [String: Any] else { continue }
            let extraInfo = extraInfo(in: object)
            let model = LocalData.firstString(
                in: extraInfo,
                keys: ["model", "modelname", "modelid", "modelalias"]
            )
            let input = LocalData.firstNumber(
                in: extraInfo,
                keys: ["inputtoken", "inputtokens"]
            )
            if model != nil || input != nil {
                return (model, input)
            }
        }

        return (
            LocalData.modelName(in: root),
            LocalData.firstNumber(in: root, keys: ["inputtoken", "inputtokens"])
        )
    }

    private static func extraInfo(in object: [String: Any]) -> Any {
        for (key, value) in object where LocalData.normalizedKey(key) == "extrainfo" {
            if let dictionary = value as? [String: Any] {
                return dictionary
            }
            if let embedded = LocalData.embeddedJSON(value) {
                return embedded
            }
        }
        return object
    }
}
