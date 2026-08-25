import Foundation

struct HTTPJSONResult {
    let object: Any
    let statusCode: Int
}

enum HTTPJSON {
    static func get(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> HTTPJSONResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard let object = LocalData.parseJSON(data: data) else {
            throw URLError(.cannotParseResponse)
        }
        return HTTPJSONResult(object: object, statusCode: httpResponse.statusCode)
    }

    static func post(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> HTTPJSONResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard let object = LocalData.parseJSON(data: data) else {
            throw URLError(.cannotParseResponse)
        }
        return HTTPJSONResult(object: object, statusCode: httpResponse.statusCode)
    }
}

enum CredentialLocator {
    static func credential(in value: Any) -> String? {
        guard let object = value as? [String: Any] else {
            if let array = value as? [Any] {
                for child in array {
                    if let result = credential(in: child) { return result }
                }
            }
            return nil
        }
        let priority = ["apikey", "accesstoken", "access_token", "token", "api_key"]
        for wanted in priority {
            for (key, value) in object where LocalData.normalizedKey(key) == LocalData.normalizedKey(wanted) {
                if let string = LocalData.string(value), !string.isEmpty {
                    return string
                }
            }
        }
        for child in object.values {
            if let result = credential(in: child) { return result }
        }
        return nil
    }

    static func accountName(in value: Any) -> String? {
        LocalData.firstString(
            in: value,
            keys: ["subusername", "username", "email", "nickname", "userid"]
        )
    }
}

struct MiniMaxProvider: UsageProvider {
    let id: ProviderID = .miniMax

    func fetch() async -> ProviderSnapshot {
        let localRootExists = FileManager.default.fileExists(atPath: AppPaths.miniMaxRoot.path)
            || FileManager.default.fileExists(atPath: AppPaths.miniMaxSupport.path)
        let codeScan = MiniMaxCodeUsageScanner.scan()
        let localSummary = codeScan.recognizedEventCount > 0
            ? codeScan.summary
            : scanLocalLogs()
        var metrics = UsageMetrics.localMetrics(summary: localSummary, includeMoney: true)
        let config = LocalData.loadJSON(at: AppPaths.miniMaxConfig)
        let accountName = CredentialLocator.accountName(in: config ?? [:]) ?? "当前 MiniMax 账户"
        var remoteMessage: String?
        var remoteConnected = false

        if let remote = await fetchRemote(config: config) {
            metrics.insert(contentsOf: remote.metrics, at: 0)
            remoteMessage = remote.message
            remoteConnected = !remote.metrics.isEmpty
        } else {
            let hasCredential = credential(config: config) != nil
            remoteMessage = hasCredential
                ? "已找到本机凭证，但额度接口暂未返回可识别字段。"
                : "未找到 MiniMax API Key；如需服务端额度，请在环境变量 MINIMAX_API_KEY 中提供。"
        }

        let state: ProviderState
        if remoteConnected || !metrics.isEmpty {
            // Local token usage is a complete, usable data source for the
            // dashboard. A missing remote quota endpoint should not mark the
            // entire MiniMax card as partially available.
            state = .connected
        } else if localRootExists {
            state = .partial
        } else {
            state = .unavailable
        }
        let localMessage = metrics.contains(where: { $0.source == .local })
            ? (codeScan.recognizedEventCount > 0
                ? "本地 Token/请求来自 MiniMax Code 的 runtime-state.sqlite，用量按响应记录汇总；成本按 MiniMax M3/M2 系列官方 API 标准 Token 价格折算。Token Plan 实际扣减仍以服务端额度为准。"
                : "本地 Token/请求来自 ~/.minimax 与 MiniMax 应用日志。")
            : nil
        let message = SnapshotFactory.combineMessages([remoteMessage, localMessage])
        var accounts = [AccountUsageSnapshot(
            id: "\(id.rawValue)-active",
            provider: id,
            accountName: accountName,
            state: state,
            metrics: metrics,
            updatedAt: Date(),
            message: message,
            source: remoteConnected ? .server : (metrics.isEmpty ? .unavailable : .local),
            modelUsages: UsageMetrics.modelUsages(summary: localSummary)
        )]
        for account in LocalAccountStore.accounts(for: id) {
            guard let token = CredentialKeychain.load(for: account) else {
                accounts.append(AccountUsageSnapshot(
                    id: account.id.uuidString,
                    provider: id,
                    accountName: account.name,
                    state: .partial,
                    metrics: [],
                    updatedAt: Date(),
                    message: "钥匙串中没有找到该账户凭据。",
                    source: .unavailable
                ))
                continue
            }
            if let remote = await fetchRemote(token: token) {
                accounts.append(AccountUsageSnapshot(
                    id: account.id.uuidString,
                    provider: id,
                    accountName: account.name,
                    state: .connected,
                    metrics: remote.metrics,
                    updatedAt: Date(),
                    message: remote.message,
                    source: .server
                ))
            } else {
                accounts.append(AccountUsageSnapshot(
                    id: account.id.uuidString,
                    provider: id,
                    accountName: account.name,
                    state: .partial,
                    metrics: [],
                    updatedAt: Date(),
                    message: "额度接口未返回可识别数据，请检查凭据或产品区域。",
                    source: .unavailable
                ))
            }
        }
        let overallState: ProviderState = accounts.contains(where: { $0.state == .connected })
            ? .connected
            : (accounts.contains(where: { $0.state == .partial }) ? .partial : state)
        return SnapshotFactory.make(provider: id, accounts: accounts, state: overallState)
    }

    private func credential(config: Any?) -> String? {
        if let environment = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !environment.isEmpty {
            return environment
        }
        if let config, let value = CredentialLocator.credential(in: config) {
            return value
        }
        let candidates = [
            AppPaths.miniMaxRoot.appendingPathComponent("local-runtime.auth.json"),
            AppPaths.miniMaxRoot.appendingPathComponent("config.yaml")
        ]
        for url in candidates {
            if url.pathExtension.lowercased() == "json",
               let value = LocalData.loadJSON(at: url),
               let token = CredentialLocator.credential(in: value) {
                return token
            }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                for line in text.split(whereSeparator: \.isNewline) {
                    let lower = line.lowercased()
                    if lower.contains("api_key") || lower.contains("apikey") || lower.contains("access_token") {
                        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))
                            let value = parts[1].trimmingCharacters(in: trimSet)
                            if !value.isEmpty { return value }
                        }
                    }
                }
            }
        }
        return nil
    }

    private func scanLocalLogs() -> LocalUsageSummary {
        let records = LocalData.jsonLines(
            under: [AppPaths.miniMaxRoot, AppPaths.miniMaxSupport],
            maxFiles: 300,
            maxLinesPerFile: 10_000,
            modifiedAfter: LocalData.previousMonthStart
        )
        var summary = LocalUsageSummary()
        for record in records {
            guard let tokens = LocalData.tokenBreakdown(in: record.object) else { continue }
            let date = LocalData.firstDate(
                in: record.object,
                keys: ["timestamp", "createdat", "updatedat", "time"]
            ) ?? record.fallbackDate
            let cost = LocalData.firstNumber(in: record.object, keys: ["costusd", "cost"])
            summary.add(
                date: date,
                tokens: tokens,
                requests: 1,
                cost: max(cost ?? 0, 0),
                model: LocalData.modelName(in: record.object)
            )
        }
        return summary
    }

    private func fetchRemote(config: Any?) async -> (metrics: [UsageMetric], message: String)? {
        guard let token = credential(config: config) else { return nil }
        return await fetchRemote(token: token)
    }

    private func fetchRemote(token: String) async -> (metrics: [UsageMetric], message: String)? {
        guard !token.contains("\n") else { return nil }
        let endpoints = [
            "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains",
            "https://www.minimaxi.com/v1/token_plan/remains",
            "https://www.minimax.io/v1/api/openplatform/coding_plan/remains",
            "https://www.minimax.io/v1/token_plan/remains"
        ].compactMap(URL.init(string:))
        for endpoint in endpoints {
            do {
                let result = try await HTTPJSON.get(
                    url: endpoint,
                    headers: [
                        "Authorization": "Bearer \(token)",
                        "api-key": token,
                        "MM-API-Source": "AIUsageBar",
                        "User-Agent": "AIUsageBar/0.1"
                    ]
                )
                guard (200..<300).contains(result.statusCode) else { continue }
                let metrics = parseRemoteMetrics(result.object)
                if !metrics.isEmpty {
                    return (metrics, "MiniMax 服务端额度已读取。")
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func parseRemoteMetrics(_ object: Any) -> [UsageMetric] {
        let codingPlanMetrics = parseCodingPlanMetrics(object)
        if !codingPlanMetrics.isEmpty {
            return codingPlanMetrics
        }

        var metrics: [UsageMetric] = []
        if let intervalUsed = LocalData.firstNumber(in: object, keys: ["currentintervalusagecount"]),
           let intervalLimit = LocalData.firstNumber(in: object, keys: ["currentintervaltotalcount"]),
           intervalLimit > 0 {
            metrics.append(UsageMetric(
                key: "minimax-interval",
                title: "5 小时额度",
                kind: .quota,
                window: .fiveHours,
                used: max(intervalUsed, 0),
                limit: max(intervalLimit, 0),
                remaining: max(intervalLimit - intervalUsed, 0),
                unit: "次",
                source: .server,
                resetAt: LocalData.firstDate(in: object, keys: ["endtime"]),
                note: "MiniMax Token Plan 接口"
            ))
        }
        if let weeklyUsed = LocalData.firstNumber(in: object, keys: ["currentweeklyusagecount"]),
           let weeklyLimit = LocalData.firstNumber(in: object, keys: ["currentweeklytotalcount"]),
           weeklyLimit > 0 {
            metrics.append(UsageMetric(
                key: "minimax-weekly",
                title: "周额度",
                kind: .quota,
                window: .weekly,
                used: max(weeklyUsed, 0),
                limit: max(weeklyLimit, 0),
                remaining: max(weeklyLimit - weeklyUsed, 0),
                unit: "次",
                source: .server,
                resetAt: LocalData.firstDate(in: object, keys: ["weeklyendtime"]),
                note: "MiniMax Token Plan 接口"
            ))
        }
        if metrics.isEmpty,
           let used = LocalData.firstNumber(in: object, keys: ["used", "usage"]),
           let limit = LocalData.firstNumber(in: object, keys: ["limit", "total", "quota"]) {
            metrics.append(UsageMetric(
                key: "minimax-plan",
                title: "订阅额度",
                kind: .quota,
                window: .billing,
                used: max(used, 0),
                limit: max(limit, 0),
                remaining: max(limit - used, 0),
                unit: "次",
                source: .server,
                resetAt: nil,
                note: "MiniMax 服务端响应"
            ))
        }
        return metrics
    }

    private func parseCodingPlanMetrics(_ object: Any) -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        var seen: Set<String> = []
        LocalData.walk(object) { value, _ in
            guard let dictionary = value as? [String: Any] else { return }
            let intervalPercent = remainingPercent(
                directNumber(in: dictionary, keys: ["currentintervalremainingpercent"])
            )
            let weeklyPercent = remainingPercent(
                directNumber(in: dictionary, keys: ["currentweeklyremainingpercent"])
            )
            let intervalUsed = directNumber(in: dictionary, keys: ["currentintervalusagecount"])
            let intervalLimit = directNumber(in: dictionary, keys: ["currentintervaltotalcount"])
            let weeklyUsed = directNumber(in: dictionary, keys: ["currentweeklyusagecount"])
            let weeklyLimit = directNumber(in: dictionary, keys: ["currentweeklytotalcount"])
            guard intervalPercent != nil || weeklyPercent != nil
                || (intervalUsed != nil && intervalLimit != nil)
                || (weeklyUsed != nil && weeklyLimit != nil)
            else { return }

            let model = ModelUsage.normalizedName(
                directString(in: dictionary, keys: ["modelname", "model"])
            )
            let modelKey = model == "未知" ? "all" : model
            let intervalReset = directDate(in: dictionary, keys: ["endtime"])
            let weeklyReset = directDate(in: dictionary, keys: ["weeklyendtime"])

            if let intervalMetric = makeQuotaMetric(
                key: "minimax-interval-\(modelKey)",
                title: model == "未知" ? "5 小时额度" : "5 小时 · \(model)",
                window: .fiveHours,
                remainingPercent: intervalPercent,
                used: intervalUsed,
                limit: intervalLimit,
                resetAt: intervalReset
            ), seen.insert(intervalMetric.key).inserted {
                metrics.append(intervalMetric)
            }
            if let weeklyMetric = makeQuotaMetric(
                key: "minimax-weekly-\(modelKey)",
                title: model == "未知" ? "周额度" : "周额度 · \(model)",
                window: .weekly,
                remainingPercent: weeklyPercent,
                used: weeklyUsed,
                limit: weeklyLimit,
                resetAt: weeklyReset
            ), seen.insert(weeklyMetric.key).inserted {
                metrics.append(weeklyMetric)
            }
        }
        return metrics
    }

    private func directNumber(in dictionary: [String: Any], keys: Set<String>) -> Double? {
        for (key, value) in dictionary where keys.contains(LocalData.normalizedKey(key)) {
            if let result = LocalData.number(value) { return result }
        }
        return nil
    }

    private func directString(in dictionary: [String: Any], keys: Set<String>) -> String? {
        for (key, value) in dictionary where keys.contains(LocalData.normalizedKey(key)) {
            if let result = LocalData.string(value), !result.isEmpty { return result }
        }
        return nil
    }

    private func directDate(in dictionary: [String: Any], keys: Set<String>) -> Date? {
        for (key, value) in dictionary where keys.contains(LocalData.normalizedKey(key)) {
            if let result = LocalData.date(value) { return result }
        }
        return nil
    }

    private func makeQuotaMetric(
        key: String,
        title: String,
        window: UsageWindow,
        remainingPercent: Double?,
        used: Double?,
        limit: Double?,
        resetAt: Date?
    ) -> UsageMetric? {
        if let remainingPercent {
            return UsageMetric(
                key: key,
                title: title,
                kind: .quota,
                window: window,
                used: nil,
                limit: 100,
                remaining: remainingPercent,
                unit: "%",
                source: .server,
                resetAt: resetAt,
                note: "MiniMax coding plan remains 接口"
            )
        }
        guard let used, let limit, limit > 0 else { return nil }
        return UsageMetric(
            key: key,
            title: title,
            kind: .quota,
            window: window,
            used: max(used, 0),
            limit: max(limit, 0),
            remaining: max(limit - used, 0),
            unit: "次",
            source: .server,
            resetAt: resetAt,
            note: "MiniMax coding plan remains 接口"
        )
    }

    private func remainingPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        let percent = value >= 0 && value <= 1 && value != 0 ? value * 100 : value
        return min(max(percent, 0), 100)
    }
}

struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            CodexUsageScanner.scan()
        }.value
        let liveQuota = await CodexQuotaService.fetchLive()

        var metrics = UsageMetrics.localMetrics(summary: scan.summary, includeMoney: true)
        if let liveQuota {
            metrics.append(contentsOf: CodexQuotaMetrics.make(from: liveQuota.snapshot, source: liveQuota.source))
        } else if let latestQuota = scan.latestQuota {
            metrics.append(contentsOf: CodexQuotaMetrics.make(from: latestQuota, source: .local))
        }

        let hasLocalUsage = scan.recognizedEventCount > 0
        let hasQuota = liveQuota != nil || scan.latestQuota != nil
        let planName = liveQuota?.snapshot.planType ?? scan.latestQuota?.planType
        let codexRootExists = FileManager.default.fileExists(atPath: AppPaths.codexRoot.path)
        let state: ProviderState
        if hasLocalUsage || hasQuota {
            state = .connected
        } else if codexRootExists || scan.hasRolloutFiles {
            state = .partial
        } else {
            state = .unavailable
        }

        var messages: [String] = []
        if hasLocalUsage {
            messages.append("Token、模型和估算成本来自本机 Codex rollout 日志，已按 Tokei 口径去重。")
        } else if scan.hasRolloutFiles {
            messages.append("已找到 Codex rollout 文件，但暂未识别到 token_count 用量事件。")
        } else {
            messages.append("未找到 ~/.codex/sessions 或 archived_sessions 中的 Codex rollout 日志。")
        }
        if liveQuota != nil {
            messages.append("5 小时/周订阅额度来自 Codex 官方接口。")
        } else if scan.latestQuota != nil {
            messages.append("官方额度接口暂不可用，当前显示最近一次本地 rate_limits 快照。")
        } else {
            messages.append("暂未读取到 Codex 订阅额度；本地 Token 数据仍可正常显示。")
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: planName.map { "Codex · \($0)" } ?? "当前 Codex 账户",
            planName: planName,
            state: state,
            metrics: metrics,
            message: messages.joined(separator: "\n"),
            source: liveQuota?.source ?? (hasLocalUsage || scan.latestQuota != nil ? .local : .unavailable),
            modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
        )
    }
}

protocol UsageProvider {
    var id: ProviderID { get }
    func fetch() async -> ProviderSnapshot
}

enum ProviderRegistry {
    static let all: [any UsageProvider] = [
        CodexProvider(),
        QwenWorkProvider(),
        ZCodeProvider(),
        DoubaoWorkProvider(),
        WorkBuddyProvider(),
        MiniMaxProvider()
    ]
}

enum SnapshotFactory {
    static func make(
        provider: ProviderID,
        accountName: String,
        planName: String? = nil,
        state: ProviderState,
        metrics: [UsageMetric],
        message: String?,
        source: DataSource,
        modelUsages: [ModelUsage] = [],
        updatedAt: Date = Date()
    ) -> ProviderSnapshot {
        let account = AccountUsageSnapshot(
            id: "\(provider.rawValue)-\(accountName)",
            provider: provider,
            accountName: accountName,
            planName: planName,
            state: state,
            metrics: metrics,
            updatedAt: updatedAt,
            message: message,
            source: source,
            modelUsages: modelUsages
        )
        return ProviderSnapshot(
            provider: provider,
            accounts: [account],
            state: state,
            updatedAt: updatedAt
        )
    }

    static func make(
        provider: ProviderID,
        accounts: [AccountUsageSnapshot],
        state: ProviderState,
        updatedAt: Date = Date()
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            accounts: accounts,
            state: state,
            updatedAt: updatedAt
        )
    }

    static func combineMessages(_ messages: [String?]) -> String? {
        let values = messages.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }
}

struct ZCodeProvider: UsageProvider {
    let id: ProviderID = .zcode

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            ZCodeUsageScanner.scan()
        }.value
        let metrics = UsageMetrics.localMetrics(
            summary: scan.summary,
            includeMoney: true
        )

        let state: ProviderState
        if scan.responseCount > 0 {
            state = .connected
        } else if scan.hasDatabase {
            state = .partial
        } else {
            state = .unavailable
        }

        var message: String
        if scan.responseCount > 0 {
            message = "Token、模型、会话和请求来自 ZCode 本机 SQLite 的 model_usage 表；input_tokens 按 ZCode 的完整 prompt 总量处理，缓存读取单独用于命中率和成本估算。成本优先使用 ~/.tokei 价格表，未匹配模型不会强行估价。"
            if !scan.unpricedModels.isEmpty {
                message += "\n以下模型未匹配到价格，仅计入 Token，不计入成本：\(scan.unpricedModels.joined(separator: ", "))。"
            }
        } else if scan.hasDatabase {
            message = "已找到 ZCode 本机用量数据库，但暂未识别到有 Token 的模型调用。"
        } else {
            message = "未找到 ZCode 本机用量数据库（~/.zcode/cli/db/db.sqlite）。请先启动并使用 ZCode。"
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: scan.latestModel.map { "ZCode · \($0)" } ?? "本机活动账户",
            state: state,
            metrics: metrics,
            message: message,
            source: scan.responseCount > 0 ? .local : .unavailable,
            modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
        )
    }
}

struct OpenCodeProvider: UsageProvider {
    let id: ProviderID = .openCode

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            OpenCodeUsageScanner.scan()
        }.value
        let metrics = UsageMetrics.localMetrics(
            summary: scan.summary,
            includeMoney: true
        )

        let state: ProviderState
        if scan.responseCount > 0 {
            state = .connected
        } else if scan.hasDatabase {
            state = .partial
        } else {
            state = .unavailable
        }

        var message: String
        if scan.responseCount > 0 {
            message = "Token、模型、缓存、请求和会话来自 OpenCode 本机 SQLite 的 message 表；缓存读取/写入作为独立输入项统计，成本优先使用消息内记录或本机价格表。"
            if !scan.unpricedModels.isEmpty {
                message += "\n以下模型未匹配到价格，仅计入 Token，不计入成本：\(scan.unpricedModels.joined(separator: ", "))。"
            }
        } else if scan.hasDatabase {
            message = "已找到 OpenCode 本机用量数据库，但暂未识别到有 Token 的 assistant 消息。"
        } else {
            message = "未找到 OpenCode 本机用量数据库（~/.local/share/opencode/opencode.db）。请先启动并使用 OpenCode。"
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: scan.latestModel.map { "OpenCode · \($0)" } ?? "本机活动账户",
            state: state,
            metrics: metrics,
            message: message,
            source: scan.responseCount > 0 ? .local : .unavailable,
            modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
        )
    }
}

struct DoubaoWorkProvider: UsageProvider {
    let id: ProviderID = .doubaoWork

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            DoubaoWorkUsageScanner.scan()
        }.value
        let metrics = UsageMetrics.localMetrics(summary: scan.summary)
        let hasRoot = FileManager.default.fileExists(atPath: AppPaths.doubaoWorkRoot.path)

        let state: ProviderState
        if scan.responseCount > 0 {
            state = .connected
        } else if hasRoot || scan.hasLogFiles {
            state = .partial
        } else {
            state = .unavailable
        }

        let message: String
        if scan.responseCount > 0 {
            message = "请求次数来自豆包工作本机的 Tea/tea.db 与 sdk_storage/log 网络事件；仅统计 /chat/completion 和 /samantha/chat/completion，并对重复日志去重。当前日志未保存可可靠复原的 input/output Token，Token 与成本暂不估算。"
        } else if hasRoot || scan.hasLogFiles {
            message = "已找到豆包工作本机日志，但暂未识别到工作模式模型完成请求（/chat/completion 或 /samantha/chat/completion）。"
        } else {
            message = "未找到豆包工作本机日志（~/Library/Application Support/DoubaoWork）。请先启动并使用豆包工作。"
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: "豆包工作 · 工作模式",
            state: state,
            metrics: metrics,
            message: message,
            source: scan.responseCount > 0 ? .local : .unavailable
        )
    }
}

struct WorkBuddyProvider: UsageProvider {
    let id: ProviderID = .workBuddy

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            WorkBuddyUsageScanner.scan()
        }.value
        var metrics = UsageMetrics.localMetrics(
            summary: scan.summary,
            includeCredits: true,
            includeMoney: true
        )
        let quota = await WorkBuddyQuotaService.fetch()
        if let quota {
            metrics.insert(quota.metric, at: 0)
        }

        let hasRoot = FileManager.default.fileExists(atPath: AppPaths.workBuddyRoot.path)
        let state: ProviderState
        if scan.responseCount > 0 || quota != nil {
            state = .connected
        } else if hasRoot || scan.hasLogFiles || FileManager.default.fileExists(atPath: AppPaths.workBuddyAuthFile.path) {
            state = .partial
        } else {
            state = .unavailable
        }

        var messages: [String] = []
        if scan.responseCount > 0 {
            messages.append("按 WorkBuddy 本机口径读取 ~/.workbuddy/logs 的 AcpUsagePublisher 积分流水，并与 ~/.workbuddy/projects 的 rawUsage 去重合并；Token 按 prompt_tokens / prompt_cache_hit_tokens 统计，成本按模型价格表估算。")
        } else if scan.hasLogFiles {
            messages.append("已找到 WorkBuddy 本地记录，但暂未识别到 AcpUsagePublisher 积分流水或 assistant rawUsage。")
        } else {
            messages.append("未找到 ~/.workbuddy/projects 或 ~/.workbuddy/logs 下的 WorkBuddy 会话记录。")
        }
        if quota != nil {
            messages.append("订阅 Credits 余额来自 CodeBuddy 资源包接口；本机积分消耗来自 AcpUsagePublisher 流水；成本估算是按 Token 价格换算的美元金额，不等同于 Credits 扣减。")
        } else {
            messages.append("服务端 Credits 暂不可用，本地 Token、积分和按价格表换算的成本仍可显示。")
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: quota?.packageName.map { "WorkBuddy · \($0)" } ?? "本机活动账户",
            planName: quota?.packageName,
            state: state,
            metrics: metrics,
            message: messages.joined(separator: "\n"),
            source: quota != nil ? .server : (scan.responseCount > 0 ? .local : .unavailable),
            modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
        )
    }
}

struct QwenWorkProvider: UsageProvider {
    let id: ProviderID = .qwenWork

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            QwenWorkUsageScanner.scan()
        }.value
        let localMetrics = QwenWorkUsageMetrics.make(summary: scan.summary, scan: scan)
        let rootExists = FileManager.default.fileExists(atPath: AppPaths.qwenWorkRoot.path)

        let credentials = QwenWorkQuotaService.credentialCandidates()
        var remoteAccounts: [(QwenWorkCredentialCandidate, QwenWorkQuotaResult)] = []
        for candidate in credentials {
            if let quota = await QwenWorkQuotaService.fetch(token: candidate.token) {
                remoteAccounts.append((candidate, quota))
            }
        }

        let localHasActivity = scan.responseCount > 0 || !localMetrics.isEmpty
        let localAccountName = QwenWorkUsageScanner.localAccountName() ?? "本机活动账户"
        var localMessage: String?
        if localHasActivity {
            var parts = [
                "本地明细来自 ~/.qwenworkcn/projects 的会话 JSONL：请求、会话、活跃时长和模型按去重后的 message.id 汇总。"
            ]
            if scan.tokenResponseCount == 0 {
                parts.append("当前版本日志没有提供 Token 字段，因此不显示 Token 与成本估算。")
            } else {
                parts.append("Token 只采用日志中明确写出的 usage / usageMetadata，不从文本长度反推。")
            }
            localMessage = parts.joined(separator: "\n")
        } else if rootExists || scan.hasLogFiles {
            localMessage = scan.hasLogFiles
                ? "已找到 QwenWorkCN 会话 JSONL，但暂未识别到可统计的 assistant 响应。"
                : "已找到 QwenWorkCN 数据目录，但还没有可统计的模型响应。"
        }

        let remoteMessage: String?
        if !remoteAccounts.isEmpty {
            let plans = remoteAccounts.compactMap { $0.1.planName }.filter { !$0.isEmpty }
            remoteMessage = plans.isEmpty
                ? "服务端订阅 Credits 来自 QwenWork 官方 account-context 接口。"
                : "服务端订阅 Credits 来自 QwenWork 官方 account-context 接口（套餐：\(Array(Set(plans)).joined(separator: "、"))）。"
        } else if credentials.isEmpty {
            remoteMessage = "未读取服务端 Credits：QwenWork 登录令牌由 Electron 安全存储保护；可在账户设置中添加 Access Token 后读取官方额度。"
        } else {
            remoteMessage = "已找到 QwenWork 凭据，但官方 account-context 额度接口暂未返回可识别数据。"
        }

        var accounts: [AccountUsageSnapshot] = []
        var remainingRemoteAccounts = remoteAccounts
        if localHasActivity {
            var metrics = localMetrics
            var messages: [String?] = [localMessage]
            var accountName = localAccountName
            var planName: String?
            var source: DataSource = localMetrics.isEmpty ? .unavailable : .local

            // The active local transcript and the first configured remote
            // credential normally refer to the same account. Merge them so a
            // single QwenWork card shows both live Credits and local detail.
            if let first = remainingRemoteAccounts.first {
                metrics.insert(contentsOf: first.1.metrics, at: 0)
                accountName = first.1.accountName ?? first.0.name
                planName = first.1.planName
                messages.append(remoteMessage)
                source = .server
                remainingRemoteAccounts.removeFirst()
            }

            accounts.append(AccountUsageSnapshot(
                id: "\(id.rawValue)-active",
                provider: id,
                accountName: accountName,
                planName: planName,
                state: .connected,
                metrics: metrics,
                updatedAt: Date(),
                message: SnapshotFactory.combineMessages(messages),
                source: source,
                modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
            ))
        }

        for (candidate, quota) in remainingRemoteAccounts {
            accounts.append(AccountUsageSnapshot(
                id: "\(id.rawValue)-\(candidate.id)",
                provider: id,
                accountName: quota.accountName ?? candidate.name,
                planName: quota.planName,
                state: .connected,
                metrics: quota.metrics,
                updatedAt: Date(),
                message: remoteMessage,
                source: .server
            ))
        }

        let state: ProviderState
        if !remoteAccounts.isEmpty || localHasActivity {
            state = .connected
        } else if rootExists || scan.hasLogFiles {
            state = .partial
        } else {
            state = .unavailable
        }

        if accounts.isEmpty {
            accounts.append(AccountUsageSnapshot(
                id: "\(id.rawValue)-active",
                provider: id,
                accountName: localAccountName,
                state: state,
                metrics: [],
                updatedAt: Date(),
                message: SnapshotFactory.combineMessages([localMessage, remoteMessage]),
                source: .unavailable
            ))
        }

        return SnapshotFactory.make(
            provider: id,
            accounts: accounts,
            state: state,
            updatedAt: Date()
        )
    }
}

struct QianwenOfficeProvider: UsageProvider {
    let id: ProviderID = .qianwenOffice

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            QianwenOfficeUsageScanner.scan()
        }.value
        let metrics = UsageMetrics.localMetrics(
            summary: scan.summary,
            includeCredits: false,
            includeMoney: true
        )
        let rootExists = FileManager.default.fileExists(atPath: AppPaths.qianwenAgentRoot.path)
        let hasActivity = scan.responseCount > 0 || !metrics.isEmpty

        let state: ProviderState
        if hasActivity {
            state = .connected
        } else if rootExists || scan.hasSessionFiles {
            state = .partial
        } else {
            state = .unavailable
        }

        var message: String
        if hasActivity {
            message = "本地明细来自千问主客户端办公模式的 thread-events.jsonl；仅统计 turnId 为 workbench_* 且 usageSource=provider 的响应。成本按模型公开 Token 价格估算，使用 USD 显示；这不是千问官方 Credits/余额扣减。缓存命中按缓存价计算，未重复计入普通输入。"
            if scan.tokenResponseCount < scan.responseCount {
                message += "\n其中 \(scan.responseCount - scan.tokenResponseCount) 条响应没有非零 Token 字段，仅计入请求数。"
            }
            if !scan.unpricedModels.isEmpty {
                message += "\n以下模型未匹配到价格，仅计入 Token，不计入成本：\(scan.unpricedModels.joined(separator: ", "))。"
            }
            if scan.errorCount > 0 {
                message += "\n有 \(scan.errorCount) 条事件读取失败，已跳过。"
            }
        } else if scan.hasSessionFiles {
            message = "已找到千问主客户端 agent 会话文件，但暂未识别到办公模式 provider usage。"
        } else if rootExists {
            message = "已找到千问主客户端 agent 数据目录，但还没有可统计的办公模式响应。"
        } else {
            message = "未找到千问主客户端办公模式数据目录。"
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: "本机活动账户",
            state: state,
            metrics: metrics,
            message: message,
            source: hasActivity ? .local : .unavailable,
            modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
        )
    }
}

struct DeepSeekHarnessProvider: UsageProvider {
    let id: ProviderID = .deepSeekHarness

    func fetch() async -> ProviderSnapshot {
        let scan = await Task.detached(priority: .utility) {
            DeepSeekHarnessUsageScanner.scan()
        }.value
        let metrics = DeepSeekHarnessUsageMetrics.make(summary: scan.summary)
        let rootExists = FileManager.default.fileExists(atPath: AppPaths.deepSeekHarnessRoot.path)
        let state: ProviderState
        let message: String?

        if !scan.decoderAvailable && scan.hasLogFiles {
            state = .partial
            message = "已找到 DeepSeek Harness 压缩日志，但本机未找到 zstd 解压器；如已安装 Tokei，可优先使用其本地解压缓存。"
        } else if scan.tokenResponseCount > 0 {
            state = .connected
            var messages = ["Token、模型、请求来自 ~/.dsh/sessions 本机日志；成本按 DeepSeek 官方人民币峰谷价估算。"]
            if scan.errorCount > 0 {
                messages.append("有 \(scan.errorCount) 个日志文件读取失败，已跳过。")
            }
            message = messages.joined(separator: "\n")
        } else if scan.responseCount > 0 {
            state = .partial
            message = "已识别 DeepSeek Harness 响应记录，但当前没有可用的非零 Token 字段。"
        } else if rootExists || scan.hasLogFiles {
            state = .partial
            message = scan.hasLogFiles
                ? "已找到 DeepSeek Harness 日志，但暂未识别到 assistant/message.data.usage。"
                : "已找到 ~/.dsh，但还没有可统计的 Harness 会话。"
        } else {
            state = .unavailable
            message = "未找到 ~/.dsh/sessions，请先启动并使用 DeepSeek Harness。"
        }

        return SnapshotFactory.make(
            provider: id,
            accountName: scan.latestModel.map { "DeepSeek · \($0)" } ?? "当前 DeepSeek Harness 账户",
            state: state,
            metrics: metrics,
            message: message,
            source: metrics.isEmpty ? .unavailable : .local,
            modelUsages: UsageMetrics.modelUsages(summary: scan.summary)
        )
    }
}
