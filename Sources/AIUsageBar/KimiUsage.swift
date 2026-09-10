import Foundation

/// The local usage ledger written by KIMI Desktop's Agent runtime.
///
/// KIMI writes both `usage.record` and a copy of the same usage under a
/// `step.end` loop event.  `usage.record` is authoritative; the loop event is
/// used only as a compatibility fallback for older sessions so one model
/// response is never counted twice.
struct KimiUsageScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let tokenResponseCount: Int
    let hasSessionFiles: Bool
    let latestModel: String?
    let unpricedModels: [String]
    let sessionCounts: KimiSessionCounts
}

struct KimiSessionCounts {
    private var values: [String: Set<String>] = [:]

    mutating func insert(date: Date, sessionID: String, now: Date = Date()) {
        guard !sessionID.isEmpty else { return }
        for window in KimiWindowBuckets.containing(date: date, now: now) {
            values[window.rawValue, default: []].insert(sessionID)
        }
    }

    func count(for window: UsageWindow) -> Int {
        values[window.rawValue]?.count ?? 0
    }
}

private enum KimiWindowBuckets {
    static func containing(
        date: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [UsageWindow] {
        guard date <= now.addingTimeInterval(60) else { return [] }

        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
        let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) ?? startOfWeek
        let components = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: components) ?? startOfDay
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
        let yearComponents = calendar.dateComponents([.year], from: now)
        let startOfYear = calendar.date(from: yearComponents) ?? startOfMonth

        var windows: [UsageWindow] = []
        if date >= startOfDay {
            windows.append(.today)
        }
        if date >= startOfYesterday && date < startOfDay {
            windows.append(.yesterday)
        }
        if date >= startOfWeek && date < startOfTomorrow {
            windows.append(.weekly)
        }
        if date >= startOfLastWeek && date < startOfWeek {
            windows.append(.lastWeek)
        }
        if date >= startOfMonth {
            windows.append(.monthly)
        }
        if date >= startOfLastMonth && date < startOfMonth {
            windows.append(.lastMonth)
        }
        if date >= startOfYear {
            windows.append(.yearly)
        }
        return windows
    }
}

private struct KimiUsageEvent {
    let date: Date
    let model: String
    let tokens: TokenBreakdown?
    let cost: Double?
}

private enum KimiTokenParser {
    static func breakdown(in value: Any?) -> TokenBreakdown? {
        guard let object = value as? [String: Any] else { return nil }

        let inputOther = number(in: object, keys: ["inputOther", "input_other", "inputTokens", "input_tokens"])
        let cacheRead = number(in: object, keys: ["inputCacheRead", "input_cache_read", "cacheRead", "cache_read"])
        let cacheWrite = number(in: object, keys: ["inputCacheCreation", "input_cache_creation", "cacheWrite", "cache_write"])
        let output = number(in: object, keys: ["output", "outputTokens", "output_tokens", "completionTokens", "completion_tokens"])
        let total = inputOther + cacheRead + cacheWrite + output
        guard total > 0 else { return nil }

        // KIMI reports inputOther separately from cache reads.  Keep the
        // uncached input normalized while retaining cache fields for the
        // headline total, hit-rate calculation, and price estimate.
        return TokenBreakdown(
            input: inputOther,
            output: output,
            total: total,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            reasoning: 0,
            inputIncludesCache: false
        )
    }

    private static func number(in object: [String: Any], keys: [String]) -> Double {
        let wanted = Set(keys.map(LocalData.normalizedKey))
        for (key, value) in object where wanted.contains(LocalData.normalizedKey(key)) {
            if let number = LocalData.number(value), number.isFinite {
                return max(number, 0)
            }
        }
        return 0
    }
}

enum KimiPricing {
    private struct Price {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    // Official Kimi API list prices, in CNY per one million tokens.  KIMI
    // Work itself consumes the shared membership credit pool, so this is a
    // comparable estimate rather than a statement of the subscription bill.
    private static let k3 = Price(input: 20, output: 100, cacheRead: 2, cacheWrite: 20)
    private static let k26 = Price(input: 6.5, output: 27, cacheRead: 1.1, cacheWrite: 6.5)

    static func estimatedCost(model: String, tokens: TokenBreakdown) -> Double? {
        guard let price = price(for: model) else { return nil }

        let totalInput = max(tokens.input + tokens.cacheRead + tokens.cacheWrite, 0)
        let cachedInput = min(max(tokens.cacheRead, 0), totalInput)
        let cacheWrite = min(max(tokens.cacheWrite, 0), max(totalInput - cachedInput, 0))
        let uncachedInput = max(totalInput - cachedInput - cacheWrite, 0)
        return uncachedInput / 1_000_000 * price.input
            + cachedInput / 1_000_000 * price.cacheRead
            + cacheWrite / 1_000_000 * price.cacheWrite
            + max(tokens.output, 0) / 1_000_000 * price.output
    }

    private static func price(for rawModel: String) -> Price? {
        let slug = rawModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "/")
            .last
            .map(String.init) ?? ""

        if slug == "k3"
            || slug == "kimi-k3"
            || slug == "k3-agent"
            || slug == "k3-agent-swarm"
            || slug == "k3-swarm" {
            return k3
        }
        if slug == "k2.6"
            || slug == "k2-6"
            || slug == "kimi-k2.6"
            || slug == "kimi-k2-6"
            || slug == "k2d6-agent" {
            return k26
        }
        return nil
    }

    static func displayName(_ rawModel: String?) -> String {
        guard let rawModel else { return "未知" }
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未知" }
        let slug = trimmed.lowercased().split(separator: "/").last.map(String.init) ?? trimmed.lowercased()

        switch slug {
        case "k3", "kimi-k3", "k3-agent":
            return "Kimi K3"
        case "k3-agent-swarm", "k3-swarm":
            return "Kimi K3 Swarm"
        case "k2.6", "k2-6", "kimi-k2.6", "kimi-k2-6", "k2d6-agent":
            return "Kimi K2.6"
        case "unknown", "null", "nil", "none", "default", "<synthetic>":
            return "未知"
        default:
            return CodexPricing.displayName(trimmed)
        }
    }
}

enum KimiUsageScanner {
    static func scan() -> KimiUsageScanResult {
        let sessionFiles = wireFiles()
        let records = LocalData.jsonLines(
            under: [AppPaths.kimiDesktopSessions],
            maxFiles: 500,
            maxLinesPerFile: 100_000
        )
        let grouped = Dictionary(grouping: records) { $0.fileURL.path }

        var summary = LocalUsageSummary()
        var sessionCounts = KimiSessionCounts()
        var responseCount = 0
        var tokenResponseCount = 0
        var latestDate: Date?
        var latestModel: String?
        var unpricedModels: Set<String> = []
        var fallbackKeys: Set<String> = []

        for path in grouped.keys.sorted() {
            let fileRecords = grouped[path, default: []].sorted { $0.lineNumber < $1.lineNumber }
            var currentModel: String?
            var hasAuthoritativeUsage = false
            var fallbackEvents: [(event: KimiUsageEvent, key: String)] = []

            for record in fileRecords {
                guard let object = record.object as? [String: Any] else { continue }
                let type = LocalData.string(object["type"])?.lowercased() ?? ""

                if type == "llm.request" {
                    currentModel = model(in: object, fallback: currentModel)
                    continue
                }
                if type == "config.update" {
                    currentModel = model(in: object, fallback: currentModel)
                    continue
                }

                if type == "usage.record" {
                    hasAuthoritativeUsage = true
                    responseCount += 1
                    let event = makeEvent(
                        object: object,
                        usage: object["usage"],
                        currentModel: currentModel,
                        fallbackDate: record.fallbackDate
                    )
                    add(
                        event,
                        fileURL: record.fileURL,
                        summary: &summary,
                        sessionCounts: &sessionCounts,
                        tokenResponseCount: &tokenResponseCount,
                        unpricedModels: &unpricedModels,
                        latestDate: &latestDate,
                        latestModel: &latestModel
                    )
                    continue
                }

                guard type == "context.append_loop_event",
                      let loopEvent = object["event"] as? [String: Any],
                      LocalData.string(loopEvent["type"])?.lowercased() == "step.end",
                      let usage = loopEvent["usage"] else {
                    continue
                }

                let identity = LocalData.string(
                    loopEvent["uuid"]
                        ?? loopEvent["messageId"]
                        ?? loopEvent["message_id"]
                        ?? loopEvent["id"]
                )
                let key = identity.map { "id:\($0)" } ?? "line:\(record.fileURL.path)#\(record.lineNumber)"
                let date = LocalData.date(
                    loopEvent["time"]
                        ?? loopEvent["timestamp"]
                        ?? loopEvent["createdAt"]
                ) ?? eventDate(in: object, fallback: record.fallbackDate)
                let event = makeEvent(
                    object: loopEvent,
                    usage: usage,
                    currentModel: currentModel,
                    fallbackDate: date
                )
                fallbackEvents.append((event, key))
            }

            // Older KIMI Desktop builds did not write usage.record.  Only
            // fall back when the file has no authoritative records at all.
            if !hasAuthoritativeUsage {
                for candidate in fallbackEvents {
                    guard fallbackKeys.insert(candidate.key).inserted else { continue }
                    responseCount += 1
                    add(
                        candidate.event,
                        fileURL: URL(fileURLWithPath: path),
                        summary: &summary,
                        sessionCounts: &sessionCounts,
                        tokenResponseCount: &tokenResponseCount,
                        unpricedModels: &unpricedModels,
                        latestDate: &latestDate,
                        latestModel: &latestModel
                    )
                }
            }
        }

        return KimiUsageScanResult(
            summary: summary,
            responseCount: responseCount,
            tokenResponseCount: tokenResponseCount,
            hasSessionFiles: !sessionFiles.isEmpty,
            latestModel: latestModel,
            unpricedModels: unpricedModels.sorted(),
            sessionCounts: sessionCounts
        )
    }

    private static func add(
        _ event: KimiUsageEvent,
        fileURL: URL,
        summary: inout LocalUsageSummary,
        sessionCounts: inout KimiSessionCounts,
        tokenResponseCount: inout Int,
        unpricedModels: inout Set<String>,
        latestDate: inout Date?,
        latestModel: inout String?
    ) {
        summary.add(
            date: event.date,
            tokens: event.tokens,
            requests: 1,
            cost: event.cost ?? 0,
            model: event.model
        )

        if event.tokens?.hasTokens == true {
            tokenResponseCount += 1
            if event.cost == nil {
                unpricedModels.insert(event.model)
            }
        }

        sessionCounts.insert(
            date: event.date,
            sessionID: sessionID(for: fileURL)
        )
        if latestDate == nil || event.date > latestDate! {
            latestDate = event.date
            latestModel = event.model
        }
    }

    private static func makeEvent(
        object: [String: Any],
        usage: Any?,
        currentModel: String?,
        fallbackDate: Date
    ) -> KimiUsageEvent {
        let rawModel = model(in: object, fallback: currentModel) ?? "unknown"
        let displayModel = KimiPricing.displayName(rawModel)
        let tokens = KimiTokenParser.breakdown(in: usage)
        let cost = tokens.flatMap { KimiPricing.estimatedCost(model: rawModel, tokens: $0) }
        return KimiUsageEvent(
            date: eventDate(in: object, fallback: fallbackDate),
            model: displayModel,
            tokens: tokens,
            cost: cost
        )
    }

    private static func eventDate(in object: [String: Any], fallback: Date) -> Date {
        LocalData.date(
            object["time"]
                ?? object["timestamp"]
                ?? object["createdAt"]
                ?? object["created_at"]
                ?? object["updatedAt"]
                ?? object["updated_at"]
        ) ?? fallback
    }

    private static func model(in object: [String: Any], fallback: String?) -> String? {
        for key in ["model", "modelAlias", "model_alias", "modelName", "model_name"] {
            if let value = LocalData.string(object[key]), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return fallback
    }

    private static func sessionID(for fileURL: URL) -> String {
        let components = fileURL.standardizedFileURL.pathComponents
        if let agentsIndex = components.lastIndex(of: "agents"), agentsIndex > 0 {
            return components[..<agentsIndex].joined(separator: "/")
        }
        return fileURL.standardizedFileURL.path
    }

    private static func wireFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: AppPaths.kimiDesktopSessions.path),
              let enumerator = FileManager.default.enumerator(
                  at: AppPaths.kimiDesktopSessions,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsPackageDescendants]
              ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.lastPathComponent == "wire.jsonl" else { return nil }
            return url
        }
    }
}

enum KimiUsageMetrics {
    static func make(scan: KimiUsageScanResult) -> [UsageMetric] {
        var metrics = UsageMetrics.localMetrics(
            summary: scan.summary,
            includeMoney: true,
            moneyUnit: "CNY"
        )

        let sessions: [(UsageWindow, Int)] = [
            (.today, scan.sessionCounts.count(for: .today)),
            (.yesterday, scan.sessionCounts.count(for: .yesterday)),
            (.weekly, scan.sessionCounts.count(for: .weekly)),
            (.lastWeek, scan.sessionCounts.count(for: .lastWeek)),
            (.monthly, scan.sessionCounts.count(for: .monthly)),
            (.lastMonth, scan.sessionCounts.count(for: .lastMonth)),
            (.yearly, scan.sessionCounts.count(for: .yearly))
        ]
        for (window, count) in sessions where count > 0 {
            metrics.append(UsageMetric(
                key: "sessions-\(window.rawValue)",
                title: "会话数",
                kind: .requests,
                window: window,
                used: Double(count),
                limit: nil,
                remaining: nil,
                unit: "个",
                source: .local,
                resetAt: nil,
                note: "按 KIMI Desktop wire 会话去重"
            ))
        }
        return metrics
    }
}

struct KimiQuotaResult {
    let metrics: [UsageMetric]
    let planName: String?
    let accountName: String
}

enum KimiQuotaService {
    private static let subscriptionEndpoint = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.membership.v2.MembershipService/GetSubscription")!
    private static let statsEndpoint = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.membership.v2.MembershipService/GetSubscriptionStats")!

    static func fetch() async -> KimiQuotaResult? {
        guard let config = LocalData.loadJSON(at: AppPaths.kimiDesktopConfig) as? [String: Any],
              let credentials = config["credentials"] as? [String: Any],
              let kimiWeb = credentials["kimiWeb"] as? [String: Any],
              let accessToken = LocalData.string(kimiWeb["accessToken"]),
              let userID = LocalData.string(kimiWeb["userId"]),
              !accessToken.isEmpty,
              !userID.isEmpty else {
            return nil
        }

        let headers = [
            "Authorization": "Bearer \(accessToken)",
            "x-msh-user-id": userID,
            "User-Agent": "Kimi Desktop",
            "R-Timezone": TimeZone.autoupdatingCurrent.identifier
        ]
        async let subscriptionRequest = try? HTTPJSON.post(
            url: subscriptionEndpoint,
            body: [:],
            headers: headers
        )
        async let statsRequest = try? HTTPJSON.post(
            url: statsEndpoint,
            body: [:],
            headers: headers
        )

        let subscription = await subscriptionRequest
        let stats = await statsRequest
        let subscriptionObject = subscription?.statusCode == 200
            ? subscription?.object as? [String: Any]
            : nil
        let statsObject = stats?.statusCode == 200
            ? stats?.object as? [String: Any]
            : nil
        return makeResult(subscription: subscriptionObject, stats: statsObject)
    }

    private static func makeResult(
        subscription: [String: Any]?,
        stats: [String: Any]?
    ) -> KimiQuotaResult? {
        guard subscription != nil || stats != nil else { return nil }

        let subscriptionDetails = subscription?["subscription"] as? [String: Any]
        let goods = subscriptionDetails?["goods"] as? [String: Any]
        let planName = string(goods, keys: ["title", "name"])
            ?? string(subscriptionDetails, keys: ["membershipLevel", "level"])
        var membershipReset = LocalData.date(
            subscriptionDetails?["currentEndTime"]
                ?? subscriptionDetails?["current_end_time"]
                ?? subscriptionDetails?["nextBillingTime"]
                ?? subscriptionDetails?["next_billing_time"]
        )

        let subscriptionBalance = balance(in: stats) ?? balance(in: subscription)
        var metrics: [UsageMetric] = []
        if let subscriptionBalance {
            membershipReset = subscriptionBalance.expireTime ?? membershipReset
            let used = min(max(subscriptionBalance.usedRatio * 100, 0), 100)
            metrics.append(UsageMetric(
                key: "kimi-membership-monthly",
                title: "KIMI · 月度额度",
                kind: .quota,
                window: .monthly,
                used: used,
                limit: 100,
                remaining: 100 - used,
                unit: "%",
                source: .server,
                resetAt: membershipReset,
                note: "KIMI 会员共享月度额度 · 按实际 Token 消耗扣减"
            ))
        }

        if let stats {
            if let fiveHour = rateLimit(
                stats["ratelimitCode5h"] as? [String: Any],
                key: "kimi-code-5h",
                window: .fiveHours,
                title: "Kimi Code · 5 小时额度"
            ) {
                metrics.append(fiveHour)
            }
            if let weekly = rateLimit(
                stats["ratelimitCode7d"] as? [String: Any],
                key: "kimi-code-7d",
                window: .weekly,
                title: "Kimi Code · 7 天额度"
            ) {
                metrics.append(weekly)
            }
        }

        guard !metrics.isEmpty else { return nil }
        let accountName = planName.map { "KIMI Desktop · \($0)" } ?? "KIMI Desktop"
        return KimiQuotaResult(
            metrics: metrics,
            planName: planName,
            accountName: accountName
        )
    }

    private struct MembershipBalance {
        let usedRatio: Double
        let expireTime: Date?
    }

    private static func balance(in object: [String: Any]?) -> MembershipBalance? {
        guard let object else { return nil }

        if let direct = object["subscriptionBalance"] as? [String: Any],
           let balance = parseBalance(direct) {
            return balance
        }
        if let rawBalances = object["balances"] as? [Any] {
            let candidates = rawBalances.compactMap { $0 as? [String: Any] }
            if let matching = candidates.first(where: isSharedMembershipBalance),
               let balance = parseBalance(matching) {
                return balance
            }
            if let balance = candidates.lazy.compactMap(parseBalance).first {
                return balance
            }
        }
        return nil
    }

    private static func isSharedMembershipBalance(_ object: [String: Any]) -> Bool {
        let feature = string(object, keys: ["feature"])?.lowercased() ?? ""
        let type = string(object, keys: ["type"])?.lowercased() ?? ""
        let unit = string(object, keys: ["unit"])?.lowercased() ?? ""
        return unit.contains("credit")
            && (feature.contains("omni") || type.contains("subscription"))
    }

    private static func parseBalance(_ object: [String: Any]) -> MembershipBalance? {
        guard let rawRatio = number(object, keys: ["amountUsedRatio", "amount_used_ratio"]),
              rawRatio.isFinite else { return nil }
        return MembershipBalance(
            usedRatio: min(max(rawRatio, 0), 1),
            expireTime: LocalData.date(
                object["expireTime"]
                    ?? object["expire_time"]
                    ?? object["expiresAt"]
                    ?? object["expires_at"]
            )
        )
    }

    private static func rateLimit(
        _ object: [String: Any]?,
        key: String,
        window: UsageWindow,
        title: String
    ) -> UsageMetric? {
        guard let object,
              !(LocalData.number(object["enabled"]) == 0) else {
            return nil
        }
        // The official stats endpoint omits ratio when a window has not been
        // used in the current period.  An enabled window with no ratio is a
        // fresh 0%-used window, not missing data.
        let rawRatio = number(object, keys: ["ratio"]) ?? 0
        guard rawRatio.isFinite else { return nil }
        let used = min(max(rawRatio * 100, 0), 100)
        return UsageMetric(
            key: key,
            title: title,
            kind: .quota,
            window: window,
            used: used,
            limit: 100,
            remaining: 100 - used,
            unit: "%",
            source: .server,
            resetAt: LocalData.date(object["resetTime"] ?? object["reset_time"]),
            note: "KIMI Desktop 官方接口 · Kimi Code 专属限额"
        )
    }

    private static func string(_ object: [String: Any]?, keys: [String]) -> String? {
        guard let object else { return nil }
        let wanted = Set(keys.map(LocalData.normalizedKey))
        for (key, value) in object where wanted.contains(LocalData.normalizedKey(key)) {
            if let string = LocalData.string(value), !string.isEmpty { return string }
        }
        return nil
    }

    private static func number(_ object: [String: Any], keys: [String]) -> Double? {
        let wanted = Set(keys.map(LocalData.normalizedKey))
        for (key, value) in object where wanted.contains(LocalData.normalizedKey(key)) {
            if let number = LocalData.number(value) { return number }
        }
        return nil
    }
}
