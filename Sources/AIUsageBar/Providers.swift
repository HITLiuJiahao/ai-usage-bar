import CommonCrypto
import CryptoKit
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
        request.timeoutInterval = 20
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
        request.timeoutInterval = 20
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

enum TraeCredentialVariant: Equatable {
    case work
    case china

    var defaultHost: String {
        switch self {
        case .work: return "grow-normal.trae.ai"
        // Current CN clients have used both hosts. The value stored in the
        // encrypted client profile wins when it is present; this is only the
        // safe fallback for a profile without a host field.
        case .china: return "api.trae.com.cn"
    }
}
}

struct TraeCredential {
    let token: String
    let userID: String
    let host: String
    let accountName: String?
    let variant: TraeCredentialVariant
}

enum TraeCredentialReader {
    private static let authKey = "iCubeAuthInfo://icube.cloudide"
    private static let header = Data([116, 99, 5, 16, 0, 0])
    private static let allowedHosts: Set<String> = [
        "api.trae.cn", "api.trae.com.cn", "api-sg-central.trae.ai",
        "api-us-east.trae.ai", "grow-normal.trae.ai",
        "growsg-normal.trae.ai", "grow-normal.traeapi.us"
    ]

    static func read(preferredVariant: TraeCredentialVariant = .china) -> TraeCredential? {
        let chinaCandidates: [(root: URL, variant: TraeCredentialVariant)] = [
            (AppPaths.traeWorkSupportCandidates[0], .china)
        ] + AppPaths.traeChinaSupportCandidates.map { ($0, .china) }
        let workCandidates: [(root: URL, variant: TraeCredentialVariant)] = [
            (AppPaths.traeWorkSupportCandidates[1], .work)
        ]
        let candidates = preferredVariant == .china
            ? chinaCandidates + workCandidates
            : workCandidates + chinaCandidates
        for candidate in candidates {
            let root = candidate.root
            let storage = root.appendingPathComponent("User/globalStorage/storage.json")
            guard let object = LocalData.loadJSON(at: storage) as? [String: Any],
                  let blob = object[authKey] as? String,
                  let auth = decodeAuth(blob),
                  let token = nonemptyString(in: auth, keys: ["token", "accesstoken"]),
                  let userID = nonemptyString(in: auth, keys: ["userid", "user_id", "useridentifier"])
            else { continue }
            let rawHost = nonemptyString(in: auth, keys: ["host"])
            let host = validatedHost(rawHost) ?? candidate.variant.defaultHost
            let account = (auth["account"] as? [String: Any]).flatMap {
                nonemptyString(in: $0, keys: ["name", "nickname", "username", "email"])
            }
            return TraeCredential(
                token: token,
                userID: userID,
                host: host,
                accountName: account,
                variant: candidate.variant
            )
        }
        return nil
    }

    private static func decodeAuth(_ value: String) -> [String: Any]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return LocalData.parseJSON(string: trimmed) as? [String: Any]
        }
        guard let blob = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              blob.count >= header.count + 32 + kCCBlockSizeAES128,
              blob.prefix(header.count) == header
        else { return nil }

        let randomKey = Data(blob[header.count..<(header.count + 32)])
        let encrypted = Data(blob[(header.count + 32)...])
        var material = Data(SHA512.hash(data: randomKey))
        material.append(hexData("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58"))
        material = Data(SHA512.hash(data: material))
        guard let plain = crypt(
            operation: CCOperation(kCCDecrypt),
            input: encrypted,
            key: Data(material.prefix(16)),
            iv: Data(material.dropFirst(16).prefix(16))
        ), plain.count >= 64 else { return nil }

        let digest = Data(plain.prefix(64))
        let payload = Data(plain.dropFirst(64))
        guard timingSafeEqual(digest, Data(SHA512.hash(data: payload))) else { return nil }
        return LocalData.parseJSON(data: payload) as? [String: Any]
    }

    private static func crypt(
        operation: CCOperation,
        input: Data,
        key: Data,
        iv: Data
    ) -> Data? {
        let capacity = input.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            capacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func hexData(_ value: String) -> Data {
        var data = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            data.append(UInt8(value[index..<next], radix: 16) ?? 0)
            index = next
        }
        return data
    }

    private static func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }

    private static func validatedHost(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: candidate), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return nil }
        return host
    }

    private static func nonemptyString(in object: [String: Any], keys: [String]) -> String? {
        for wanted in keys {
            for (key, value) in object where LocalData.normalizedKey(key) == LocalData.normalizedKey(wanted) {
                if let string = LocalData.string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
                    return string
                }
            }
        }
        return nil
    }
}

struct TraeWorkProvider: UsageProvider {
    let id: ProviderID = .traeWork

    private struct RemoteUsage {
        let metrics: [UsageMetric]
        let summary: LocalUsageSummary?
    }

    private struct RemoteResult {
        let metrics: [UsageMetric]
        let accountName: String?
        let planName: String?
        let message: String
        let summary: LocalUsageSummary?
    }

    func fetch() async -> ProviderSnapshot {
        let databaseScan = await Task.detached(priority: .utility) {
            TraeWorkUsageScanner.scan()
        }.value
        let fallbackSummary = databaseScan.responseCount == 0 ? scanLocalLogs() : LocalUsageSummary()
        let localSummary = databaseScan.responseCount > 0 ? databaseScan.summary : fallbackSummary
        var metrics = UsageMetrics.localMetrics(summary: localSummary, includeCredits: true, includeMoney: true)
        // Prefer the CN client even when an older international TRAE SOLO
        // installation is also present. The two clients use different
        // entitlement semantics and different usage endpoints.
        let credential = TraeCredentialReader.read(preferredVariant: .china)
        var remoteMessage: String?
        var remoteConnected = false
        var accountName = credential?.accountName ?? "当前 TraeWork 账户"
        var planName: String?
        var displaySummary = localSummary

        if let credential, let remote = await fetchRemote(credential: credential) {
            metrics.insert(contentsOf: remote.metrics, at: 0)
            remoteMessage = remote.message
            remoteConnected = !remote.metrics.isEmpty
            accountName = remote.accountName ?? accountName
            planName = remote.planName
            // The Trae API is the authoritative source for server usage. Use
            // it for model rows whenever it returned session records; only
            // fall back to the encrypted local ledger for quota-only replies.
            if let summary = remote.summary {
                displaySummary = summary
            }
        } else if credential == nil {
            remoteMessage = "未识别到 TraeWork 当前登录凭证；已保留本地日志统计。"
        } else {
            remoteMessage = "已识别 TraeWork 登录凭证，但服务端接口暂未返回可识别额度。"
        }

        var localMessages: [String] = []
        if databaseScan.responseCount > 0 {
            localMessages.append("按公开 TraeWork 实现读取 SQLCipher：兼容新版 chat_turn.context.token_usage 和旧版 history_v2，并按日期、session_id、模型聚合。")
        } else if databaseScan.hasDatabase {
            if !databaseScan.keyAvailable {
                localMessages.append("已发现 TraeWork CN 的 SQLCipher 数据库，但未配置 64 位解密密钥；可设置 AIUSAGEBAR_TRAE_KEY，或在 AIUsageBar 支持目录放置 trae-key.json。")
            } else if !databaseScan.sqlCipherAvailable {
                localMessages.append("已发现 TraeWork CN 数据库和解密密钥，但本机未找到 sqlcipher 命令；安装 SQLCipher 后即可读取 history_v2。")
            } else if let failure = databaseScan.failureMessage {
                localMessages.append(failure)
            }
        }
        if fallbackSummary.hasUsage {
            localMessages.append("另从 TraeWork 本机兼容日志读取到部分 Token/请求数据。")
        }

        let storageExists = AppPaths.traeSupportCandidates.contains {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("User/globalStorage/storage.json").path)
        }
        let databaseExists = databaseScan.hasDatabase
        let state: ProviderState
        if remoteConnected {
            state = .connected
        } else if !metrics.isEmpty || storageExists || databaseExists {
            state = .partial
        } else {
            state = .unavailable
        }
        if metrics.contains(where: { $0.source == .local }) && localMessages.isEmpty {
            localMessages.append("本地 Token/请求来自 TraeWork 本机数据。")
        }
        var accounts = [AccountUsageSnapshot(
            id: "\(id.rawValue)-active",
            provider: id,
            accountName: accountName,
            planName: planName,
            state: state,
            metrics: metrics,
            updatedAt: Date(),
            message: SnapshotFactory.combineMessages([remoteMessage] + localMessages),
            source: remoteConnected ? .server : (metrics.isEmpty ? .unavailable : .local),
            modelUsages: UsageMetrics.modelUsages(summary: displaySummary)
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
            let configured = TraeCredential(
                token: token,
                userID: account.id.uuidString,
                host: TraeCredentialVariant.work.defaultHost,
                accountName: account.name,
                variant: .work
            )
            if let remote = await fetchRemote(credential: configured) {
                accounts.append(AccountUsageSnapshot(
                    id: account.id.uuidString,
                    provider: id,
                    accountName: account.name,
                    planName: remote.planName,
                    state: .connected,
                    metrics: remote.metrics,
                    updatedAt: Date(),
                    message: remote.message,
                    source: .server,
                    modelUsages: remote.summary.map(UsageMetrics.modelUsages(summary:)) ?? []
                ))
            } else {
                accounts.append(AccountUsageSnapshot(
                    id: account.id.uuidString,
                    provider: id,
                    accountName: account.name,
                    state: .partial,
                    metrics: [],
                    updatedAt: Date(),
                    message: "额度接口未返回可识别数据，请检查 Access Token。",
                    source: .unavailable
                ))
            }
        }
        let overallState: ProviderState = accounts.contains(where: { $0.state == .connected })
            ? .connected
            : (accounts.contains(where: { $0.state == .partial }) ? .partial : state)
        return SnapshotFactory.make(provider: id, accounts: accounts, state: overallState)
    }

    private func scanLocalLogs() -> LocalUsageSummary {
        let roots = [
            AppPaths.home.appendingPathComponent(".trae-cn", isDirectory: true),
            AppPaths.traeWorkSupportCandidates[0].appendingPathComponent("User/workspaceStorage", isDirectory: true),
            AppPaths.traeChinaSupportCandidates[0].appendingPathComponent("User/workspaceStorage", isDirectory: true),
            AppPaths.traeWorkSupportCandidates[1].appendingPathComponent("User/workspaceStorage", isDirectory: true)
        ]
        let records = LocalData.jsonLines(
            under: roots,
            maxFiles: 300,
            maxLinesPerFile: 10_000,
            modifiedAfter: LocalData.previousMonthStart
        )
        var summary = LocalUsageSummary()
        for record in records {
            guard let tokens = LocalData.tokenBreakdown(in: record.object) else { continue }
            let date = LocalData.firstDate(in: record.object, keys: ["timestamp", "createdat", "updatedat", "time"]) ?? record.fallbackDate
            let credits = LocalData.firstNumber(in: record.object, keys: ["credits", "amountfloat", "creditused"])
            let cost = LocalData.firstNumber(in: record.object, keys: ["costmoneyfloat", "costusd", "cost"])
            summary.add(
                date: date,
                tokens: tokens,
                requests: 1,
                credits: max(credits ?? 0, 0),
                cost: max(cost ?? 0, 0),
                model: LocalData.modelName(in: record.object)
            )
        }
        return summary
    }

    private struct TraeQuotaResult {
        let metrics: [UsageMetric]
        let planName: String?
        let score: Int
        let hasUsage: Bool
    }

    private func fetchRemote(credential: TraeCredential) async -> RemoteResult? {
        var metrics: [UsageMetric] = []
        var quotaResult: TraeQuotaResult?
        var usageSummary: LocalUsageSummary?

        if let quota = await fetchQuota(credential: credential) {
            quotaResult = quota
            metrics.append(contentsOf: quota.metrics)
        }

        // The international session endpoint is intentionally not used for
        // CN. Public Trae monitors use it for TRAE Work, while CN accounts
        // expose quota/entitlement data but not the same session-usage API.
        if credential.variant == .work,
           let baseURL = URL(string: "https://\(credential.host)"),
           let usage = await fetchUsage(baseURL: baseURL, token: credential.token) {
            metrics.append(contentsOf: usage.metrics)
            usageSummary = usage.summary
        }

        guard !metrics.isEmpty else { return nil }
        let message: String
        if usageSummary != nil {
            message = "TraeWork 服务端额度/按会话用量已读取。"
        } else if quotaResult?.hasUsage == true {
            message = "TraeWork CN 官方额度已读取；Token 明细来自本机 Trae 数据库。"
        } else {
            message = "TraeWork CN 官方套餐额度已同步；未猜测未返回的剩余值。"
        }
        return RemoteResult(
            metrics: metrics,
            accountName: credential.accountName,
            planName: quotaResult?.planName,
            message: message,
            summary: usageSummary
        )
    }

    private func fetchQuota(credential: TraeCredential) async -> TraeQuotaResult? {
        let endpoints: [(path: String, body: [String: Any])] = {
            switch credential.variant {
            case .china:
                // CN's current client calls pay_status first. The v2/v1
                // entitlement endpoints remain compatible fallbacks because
                // older CN releases expose usage under ide_user_ent_usage.
                return [
                    ("trae/api/v1/pay/ide_user_pay_status", [:]),
                    ("trae/api/v2/pay/ide_user_ent_usage", ["require_usage": true]),
                    ("trae/api/v1/pay/ide_user_ent_usage", ["require_usage": true]),
                    ("trae/api/v1/pay/user_current_entitlement_list", [:])
                ]
            case .work:
                return [
                    ("trae/api/v2/pay/ide_user_ent_usage", ["require_usage": true]),
                    ("trae/api/v1/pay/ide_user_ent_usage", ["require_usage": true]),
                    ("trae/api/v1/pay/user_current_entitlement_list", [:])
                ]
            }
        }()

        var best: TraeQuotaResult?
        for baseURL in candidateBaseURLs(for: credential) {
            for endpoint in endpoints {
                guard let url = URL(string: endpoint.path, relativeTo: baseURL) else { continue }
                do {
                    let result = try await HTTPJSON.post(
                        url: url,
                        body: endpoint.body,
                        headers: requestHeaders(token: credential.token)
                    )
                    guard (200..<300).contains(result.statusCode),
                          let parsed = parseQuota(result.object)
                    else { continue }
                    if best == nil || parsed.score > best!.score {
                        best = parsed
                    }
                } catch {
                    continue
                }
            }
            // A response with actual consumed usage is authoritative enough;
            // avoid repeatedly querying the alternate CN host on every tick.
            if let best, best.score >= 100 { return best }
        }
        return best
    }

    private func candidateBaseURLs(for credential: TraeCredential) -> [URL] {
        var hosts = [credential.host]
        if credential.variant == .china {
            hosts.append(contentsOf: ["api.trae.com.cn", "api.trae.cn"])
        }
        var seen = Set<String>()
        return hosts.compactMap { host in
            guard seen.insert(host).inserted else { return nil }
            return URL(string: "https://\(host)")
        }
    }

    private func parseQuota(_ object: Any) -> TraeQuotaResult? {
        var packs = quotaPacks(in: object)
        if packs.isEmpty, let dictionary = object as? [String: Any] {
            packs = [dictionary]
        }
        guard !packs.isEmpty else { return nil }

        let remainingKeys: Set<String> = [
            "creditsremaining", "remainingcredits", "creditremaining",
            "remainingamount", "amountremaining", "remaining", "remain",
            "balance", "creditbalance", "availablecredits", "available", "left"
        ]
        let fastLimitKeys: Set<String> = [
            "premiummodelfastrequestlimit", "premiummodelslowrequestlimit",
            "advancedmodelrequestlimit", "fastrequestlimit"
        ]
        let fastUsedKeys: Set<String> = [
            "premiummodelfastamount", "premiummodelfastrequestusage",
            "premiummodelslowamount", "premiummodelslowrequestusage",
            "advancedmodelamount", "advancedmodelrequestusage", "fastrequestusage"
        ]

        var used = 0.0
        var total = 0.0
        var hasTotal = false
        var hasUsed = false
        var hasRemaining = false
        var explicitRemaining = 0.0
        var unlimited = false
        var fastUsed = 0.0
        var fastTotal = 0.0
        var hasFastFields = false
        var payGo = 0.0
        var planNames: [String] = []
        var resetAt: Date?

        for pack in packs {
            let base = directObject(in: pack, keys: ["entitlementbaseinfo", "entitlementbase", "entitlement"]) ?? pack
            let quota = directObject(in: base, keys: ["quota"])
                ?? directObject(in: pack, keys: ["quota"])
                ?? base
            let usage = directObject(in: pack, keys: ["usage", "entitlementusage"])
                ?? directObject(in: base, keys: ["usage"])
                ?? [:]

            if let name = directOrNestedString(
                in: pack,
                keys: ["packagename", "productname", "planname", "displaydesc", "groupname", "producttype"]
            ), !planNames.contains(name), !name.isEmpty {
                planNames.append(name)
            }
            resetAt = resetAt
                ?? LocalData.firstDate(in: pack, keys: ["resetat", "nextbillingtime", "expiretime", "endtime", "validuntil"])

            let basicLimit = number(in: quota, keys: ["basicusagelimit"])
            let bonusLimit = number(in: quota, keys: ["bonususagelimit"])
            let creditsLimit = number(in: quota, keys: ["creditslimit", "creditlimit", "creditstotal", "totalcredits"])
            let explicitTotal = creditsLimit
                ?? ((basicLimit != nil || bonusLimit != nil)
                    ? (basicLimit ?? 0) + (bonusLimit ?? 0)
                    : number(in: quota, keys: ["totallimit", "totalamount", "limit"]))
            if let explicitTotal {
                hasTotal = true
                if explicitTotal < 0 {
                    unlimited = true
                } else {
                    total += max(explicitTotal, 0)
                }
            }

            let basicUsed = number(in: usage, keys: ["basicusageamount"])
            let bonusUsed = number(in: usage, keys: ["bonususageamount"])
            let genericUsed = number(in: usage, keys: [
                "creditsamount", "creditsused", "usedcredits", "amountused",
                "usageamount", "usedamount", "consumedcredits", "consumed", "used"
            ])
            if let value = genericUsed ?? ((basicUsed != nil || bonusUsed != nil)
                ? (basicUsed ?? 0) + (bonusUsed ?? 0)
                : nil) {
                hasUsed = true
                used += max(value, 0)
            }
            if let value = number(in: usage, keys: remainingKeys)
                ?? number(in: quota, keys: remainingKeys)
                ?? number(in: base, keys: remainingKeys) {
                hasRemaining = true
                explicitRemaining += max(value, 0)
            }
            payGo += max(number(in: usage, keys: ["paygoamount", "paygoused"]) ?? 0, 0)

            if let value = number(in: quota, keys: fastLimitKeys) {
                hasFastFields = true
                if value >= 0 { fastTotal += value }
            }
            if let value = number(in: usage, keys: fastUsedKeys) {
                hasFastFields = true
                fastUsed += max(value, 0)
            }
        }

        guard hasTotal || hasUsed || hasRemaining || hasFastFields else { return nil }
        let finiteTotal: Double? = unlimited ? nil : (hasTotal ? total : nil)
        var resolvedUsed: Double? = hasUsed ? used : nil
        var resolvedRemaining: Double? = hasRemaining ? explicitRemaining : nil
        if resolvedUsed == nil, let finiteTotal, resolvedRemaining != nil {
            resolvedUsed = max(finiteTotal - resolvedRemaining!, 0)
        }
        if resolvedRemaining == nil, let finiteTotal, let resolvedUsed {
            resolvedRemaining = max(finiteTotal - resolvedUsed, 0)
        }

        var metrics: [UsageMetric] = []
        if hasTotal || hasUsed || hasRemaining {
            var notes: [String] = []
            if !planNames.isEmpty { notes.append("套餐：\(planNames.joined(separator: "、"))") }
            if payGo > 0 { notes.append("额外用量 \(NumberFormat.compact(payGo)) credits") }
            if resolvedUsed == nil && resolvedRemaining == nil {
                notes.append("官方接口已同步，但未返回可确认的已用/剩余值")
            }
            metrics.append(UsageMetric(
                key: "trae-billing-credits",
                title: "订阅 Credits",
                kind: .quota,
                window: .billing,
                used: resolvedUsed,
                limit: finiteTotal,
                remaining: resolvedRemaining,
                unit: "credits",
                source: .server,
                resetAt: resetAt,
                note: notes.isEmpty ? nil : notes.joined(separator: "；")
            ))
        }
        if hasFastFields && (fastTotal > 0 || fastUsed > 0) {
            metrics.append(UsageMetric(
                key: "trae-billing-fast-requests",
                title: "快速请求",
                kind: .quota,
                window: .billing,
                used: fastUsed,
                limit: fastTotal > 0 ? fastTotal : nil,
                remaining: fastTotal > 0 ? max(fastTotal - fastUsed, 0) : nil,
                unit: "次",
                source: .server,
                resetAt: resetAt,
                note: "Trae 官方套餐请求额度"
            ))
        }
        guard !metrics.isEmpty else { return nil }
        var score = 20
        if hasUsed { score += 60 }
        if hasRemaining { score += 20 }
        if used > 0 || fastUsed > 0 { score += 20 }
        if hasTotal { score += 10 }
        return TraeQuotaResult(
            metrics: metrics,
            planName: planNames.first,
            score: score,
            hasUsage: hasUsed || fastUsed > 0
        )
    }

    private func quotaPacks(in object: Any) -> [[String: Any]] {
        var packs: [[String: Any]] = []
        LocalData.walk(object) { value, _ in
            guard let dictionary = value as? [String: Any] else { return }
            let keys = Set(dictionary.keys.map(LocalData.normalizedKey))
            let hasBase = keys.contains("entitlementbaseinfo") || keys.contains("entitlementbase") || keys.contains("entitlement")
            let hasUsage = keys.contains("usage") || keys.contains("entitlementusage")
            let hasQuota = keys.contains("quota")
            guard (hasBase && hasUsage) || (hasUsage && (hasQuota || keys.contains("productid") || keys.contains("producttype"))) else { return }
            packs.append(dictionary)
        }
        return packs
    }

    private func directObject(in object: [String: Any], keys: Set<String>) -> [String: Any]? {
        for (key, value) in object where keys.contains(LocalData.normalizedKey(key)) {
            if let nested = value as? [String: Any] { return nested }
        }
        return nil
    }

    private func directNumber(in object: [String: Any], keys: Set<String>) -> Double? {
        for (key, value) in object where keys.contains(LocalData.normalizedKey(key)) {
            if let number = LocalData.number(value), number.isFinite { return number }
        }
        return nil
    }

    private func number(in object: [String: Any], keys: Set<String>) -> Double? {
        directNumber(in: object, keys: keys) ?? LocalData.firstNumber(in: object, keys: keys)
    }

    private func directOrNestedString(in object: [String: Any], keys: Set<String>) -> String? {
        if let value = LocalData.firstString(in: object, keys: keys), !value.isEmpty {
            return value
        }
        return nil
    }

    private func fetchUsage(baseURL: URL, token: String) async -> RemoteUsage? {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let start = LocalData.previousMonthStart
        // The public Trae client sends an inclusive Unix-second end bound.
        // Using the current second (rather than a millisecond timestamp)
        // avoids silently excluding the newest session on the server.
        let endSecond = max(Int64(start.timeIntervalSince1970), Int64(ceil(now.timeIntervalSince1970)) - 1)
        let pageSize = 100
        var records: [TraeUsageRecord] = []
        var seenSessionIDs = Set<String>()
        var expectedTotal: Int?
        var page = 1
        while page <= 100 {
            guard let url = URL(string: "trae/api/v1/pay/query_user_usage_group_by_session", relativeTo: baseURL) else { break }
            do {
                let result = try await HTTPJSON.post(
                    url: url,
                    body: [
                        "start_time": Int64(start.timeIntervalSince1970),
                        "end_time": endSecond,
                        "page_size": pageSize,
                        "page_num": page
                    ],
                    headers: requestHeaders(token: token)
                )
                guard (200..<300).contains(result.statusCode), let pageResult = parseUsagePage(result.object) else { break }
                if pageResult.records.isEmpty { break }
                expectedTotal = expectedTotal ?? pageResult.total
                for record in pageResult.records {
                    if let sessionID = record.sessionID,
                       !seenSessionIDs.insert(sessionID).inserted {
                        continue
                    }
                    records.append(record)
                }
                if let expectedTotal, records.count >= expectedTotal { break }
                if pageResult.records.count < pageSize { break }
                page += 1
            } catch {
                break
            }
        }
        guard !records.isEmpty else { return nil }
        var summary = LocalUsageSummary()
        for record in records {
            summary.add(
                date: record.date,
                tokens: record.tokens,
                requests: 1,
                credits: record.credits,
                cost: record.cost,
                model: record.modelName,
                sessionID: record.sessionID,
                calendar: calendar
            )
        }
        let metrics = UsageMetrics.localMetrics(summary: summary, includeCredits: true, includeMoney: true).map { metric in
            UsageMetric(
                key: "trae-remote-\(metric.key)",
                title: metric.title,
                kind: metric.kind,
                window: metric.window,
                used: metric.used,
                limit: metric.limit,
                remaining: metric.remaining,
                unit: metric.unit,
                source: .server,
                resetAt: metric.resetAt,
                note: "Trae 服务端按会话用量汇总"
            )
        }
        return RemoteUsage(metrics: metrics, summary: summary)
    }

    private struct TraeUsageRecord {
        let date: Date
        let sessionID: String?
        let tokens: TokenBreakdown?
        let credits: Double
        let cost: Double
        let modelName: String?
    }

    private func requestHeaders(token: String) -> [String: String] {
        let normalized = token.hasPrefix("Cloud-IDE-JWT ")
            ? String(token.dropFirst("Cloud-IDE-JWT ".count))
            : token
        return [
            "Authorization": "Cloud-IDE-JWT \(normalized)",
            // CN clients send the raw JWT in this header for the pay APIs.
            // Keeping both official forms makes the reader compatible with
            // the current and older Trae desktop releases.
            "x-cloudide-token": normalized
        ]
    }

    private struct TraeUsagePage {
        let records: [TraeUsageRecord]
        let total: Int?
    }

    private func parseUsagePage(_ object: Any) -> TraeUsagePage? {
        var rows: [Any]?
        LocalData.walk(object) { value, path in
            guard rows == nil, let array = value as? [Any],
                  let last = path.last,
                  ["userusagegroupbysessions", "usagegroupbysessions", "sessionusagelist"].contains(LocalData.normalizedKey(last))
            else { return }
            rows = array
        }
        guard let rows else { return nil }
        let records = rows.compactMap { value -> TraeUsageRecord? in
            guard let row = value as? [String: Any],
                  let date = LocalData.date(row["usage_time"] ?? row["usagetime"] ?? row["timestamp"]) else { return nil }

            // This mirrors WorkBuddy-Switch's Trae parser: the server groups
            // one usage row by session and keeps token/cost fields in
            // `extra_info`. Some releases serialize that object as JSON.
            let extra = (row["extra_info"] as? [String: Any])
                ?? (LocalData.embeddedJSON(row["extra_info"]) as? [String: Any])
                ?? row
            let input = max(LocalData.firstNumber(in: extra, keys: ["inputtoken", "inputtokens"]) ?? 0, 0)
            let output = max(LocalData.firstNumber(in: extra, keys: ["outputtoken", "outputtokens"]) ?? 0, 0)
            let cacheRead = max(LocalData.firstNumber(in: extra, keys: ["cachereadtoken", "cachereadinputtokens"]) ?? 0, 0)
            let cacheWrite = max(LocalData.firstNumber(in: extra, keys: ["cachewritetoken", "cachecreationinputtokens"]) ?? 0, 0)
            let reasoning = max(LocalData.firstNumber(in: extra, keys: ["reasoningtoken", "reasoningtokens", "reasoningoutputtokens"]) ?? 0, 0)
            let explicitTotal = max(LocalData.firstNumber(in: extra, keys: ["totaltoken", "totaltokens"]) ?? 0, 0)
            let total = explicitTotal > 0 ? explicitTotal : input + output + cacheRead + cacheWrite + reasoning
            let tokens: TokenBreakdown? = total > 0 || input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0 || reasoning > 0
                ? TokenBreakdown(
                    input: input,
                    output: output,
                    total: total,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    reasoning: reasoning
                )
                : nil
            let credits = max(LocalData.firstNumber(in: row, keys: ["amountfloat", "credits"]) ?? 0, 0)
            let cost = max(LocalData.firstNumber(in: row, keys: ["costmoneyfloat", "dollarfloat", "costusd"]) ?? 0, 0)
            let sessionID = LocalData.firstString(in: row, keys: ["sessionid"])
            let model = LocalData.firstString(in: row, keys: ["modelname", "model"]) 
                ?? LocalData.modelName(in: extra)
                ?? "未知"
            return TraeUsageRecord(
                date: date,
                sessionID: sessionID,
                tokens: tokens,
                credits: credits,
                cost: cost,
                modelName: model
            )
        }
        let total = LocalData.firstNumber(in: object, keys: ["total", "totalcount"]).map { max(Int($0.rounded()), 0) }
        return TraeUsagePage(records: records, total: total)
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
        WorkBuddyProvider(),
        DeepSeekHarnessProvider(),
        TraeWorkProvider(),
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
