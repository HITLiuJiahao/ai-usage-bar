import Foundation

struct TokenBreakdown: Codable {
    var input: Double = 0
    var output: Double = 0
    var total: Double = 0
    var cacheRead: Double = 0
    var cacheWrite: Double = 0
    var reasoning: Double = 0
    /// Some provider cards (notably DeepSeek Harness) present prompt tokens
    /// as non-cached input plus cache reads. Keep this bit alongside the
    /// normalized fields so a cache-hit denominator does not add cache reads
    /// for a second time.
    var inputIncludesCache: Bool = false

    var hasTokens: Bool {
        input > 0 || output > 0 || total > 0 || cacheRead > 0 || cacheWrite > 0 || reasoning > 0
    }

    mutating func add(_ other: TokenBreakdown) {
        input += other.input
        output += other.output
        total += other.total
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
        reasoning += other.reasoning
        inputIncludesCache = inputIncludesCache || other.inputIncludesCache
    }
}

struct UsageBucket {
    var tokens = TokenBreakdown()
    var requests: Double = 0
    var credits: Double = 0
    var cost: Double = 0
    var models: [String: ModelUsage] = [:]
    var sessions: Set<String> = []

    mutating func add(
        tokens: TokenBreakdown?,
        requests: Double = 0,
        credits: Double = 0,
        cost: Double = 0,
        model: String? = nil,
        window: UsageWindow? = nil,
        sessionID: String? = nil
    ) {
        if let tokens {
            self.tokens.add(tokens)
        }
        self.requests += requests
        self.credits += credits
        self.cost += cost
        if let sessionID, !sessionID.isEmpty {
            sessions.insert(sessionID)
        }
        if let window {
            let name = ModelUsage.normalizedName(model)
            var modelUsage = models[name] ?? ModelUsage(name: name, window: window)
            modelUsage.add(tokens: tokens, requests: requests, credits: credits, cost: cost)
            models[name] = modelUsage
        }
    }
}

struct LocalUsageSummary {
    var today = UsageBucket()
    var yesterday = UsageBucket()
    var thisWeek = UsageBucket()
    var lastWeek = UsageBucket()
    var month = UsageBucket()
    var lastMonth = UsageBucket()
    var year = UsageBucket()
    var lastActivity: Date?

    var hasUsage: Bool {
        [today, yesterday, thisWeek, lastWeek, month, lastMonth, year].contains {
            $0.tokens.hasTokens || $0.requests > 0 || $0.credits > 0 || $0.cost > 0
        }
    }

    mutating func add(
        date: Date,
        tokens: TokenBreakdown?,
        requests: Double = 0,
        credits: Double = 0,
        cost: Double = 0,
        model: String? = nil,
        sessionID: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let now = Date()
        if date > now.addingTimeInterval(60) {
            return
        }
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        // Tokei defines a week as Monday through Sunday, independent of the
        // user's locale first weekday setting.
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
        let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) ?? startOfWeek
        let components = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: components) ?? startOfDay
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
        let yearComponents = calendar.dateComponents([.year], from: now)
        let startOfYear = calendar.date(from: yearComponents) ?? startOfMonth
        if date >= startOfDay {
            today.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .today, sessionID: sessionID)
        }
        if date >= startOfYesterday && date < startOfDay {
            yesterday.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .yesterday, sessionID: sessionID)
        }
        if date >= startOfWeek && date < startOfTomorrow {
            thisWeek.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .weekly, sessionID: sessionID)
        }
        if date >= startOfLastWeek && date < startOfWeek {
            lastWeek.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .lastWeek, sessionID: sessionID)
        }
        if date >= startOfMonth {
            month.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .monthly, sessionID: sessionID)
        }
        if date >= startOfLastMonth && date < startOfMonth {
            lastMonth.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .lastMonth, sessionID: sessionID)
        }
        if date >= startOfYear {
            year.add(tokens: tokens, requests: requests, credits: credits, cost: cost, model: model, window: .yearly, sessionID: sessionID)
        }
        if lastActivity == nil || date > lastActivity! {
            lastActivity = date
        }
    }
}

struct JSONLineRecord {
    let fileURL: URL
    let lineNumber: Int
    let object: Any
    let fallbackDate: Date
}

enum LocalData {
    static var currentMonthStart: Date {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        return calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? calendar.startOfDay(for: now)
    }

    static var currentYearStart: Date {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        return calendar.date(
            from: calendar.dateComponents([.year], from: now)
        ) ?? calendar.startOfDay(for: now)
    }

    static var previousMonthStart: Date {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    static func parseJSON(data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func parseJSON(string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        return parseJSON(data: data)
    }

    static func loadJSON(at url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseJSON(data: data)
    }

    static func embeddedJSON(_ value: Any?) -> Any? {
        if let value {
            if let string = value as? String {
                return parseJSON(string: string)
            }
            return value
        }
        return nil
    }

    static func walk(
        _ value: Any,
        path: [String] = [],
        visit: (Any, [String]) -> Void
    ) {
        visit(value, path)
        if let object = value as? [String: Any] {
            for (key, child) in object {
                walk(child, path: path + [key], visit: visit)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                walk(child, path: path + [String(index)], visit: visit)
            }
        }
    }

    static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(trimmed) {
                return dateFromUnix(number)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: trimmed) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: trimmed)
        }
        if let value = number(value) {
            return dateFromUnix(value)
        }
        return nil
    }

    static func dateFromUnix(_ raw: Double) -> Date? {
        guard raw.isFinite, raw > 0 else { return nil }
        let seconds: Double
        if raw > 100_000_000_000_000 {
            seconds = raw / 1_000_000
        } else if raw > 100_000_000_000 {
            seconds = raw / 1_000
        } else {
            seconds = raw
        }
        return Date(timeIntervalSince1970: seconds)
    }

    static func firstNumber(
        in value: Any,
        keys: Set<String>,
        preferPath: String? = nil
    ) -> Double? {
        if let object = value as? [String: Any],
           let result = directNumber(in: object, keys: keys) {
            return result
        }
        var candidates: [(score: Int, value: Double)] = []
        walk(value) { child, path in
            guard let object = child as? [String: Any] else { return }
            for (key, value) in object {
                let normalized = normalizedKey(key)
                guard keys.contains(normalized), let number = number(value) else { continue }
                var score = 0
                if let preferPath, path.joined(separator: ".").localizedCaseInsensitiveContains(preferPath) {
                    score += 10
                }
                candidates.append((score, number))
            }
        }
        return candidates.max { lhs, rhs in lhs.score < rhs.score }?.value
    }

    static func firstString(in value: Any, keys: Set<String>) -> String? {
        if let object = value as? [String: Any],
           let result = directString(in: object, keys: keys) {
            return result
        }
        var result: String?
        walk(value) { child, _ in
            guard result == nil, let object = child as? [String: Any] else { return }
            for (key, value) in object where keys.contains(normalizedKey(key)) {
                if let string = string(value), !string.isEmpty {
                    result = string
                    break
                }
            }
        }
        return result
    }

    static func firstObject(in value: Any, keys: Set<String>) -> [String: Any]? {
        var result: [String: Any]?
        walk(value) { child, _ in
            guard result == nil, let object = child as? [String: Any] else { return }
            for (key, value) in object where keys.contains(normalizedKey(key)) {
                if let nested = value as? [String: Any] {
                    result = nested
                    break
                }
            }
        }
        return result
    }

    static func firstDate(in value: Any, keys: Set<String>) -> Date? {
        if let object = value as? [String: Any],
           let result = directDate(in: object, keys: keys) {
            return result
        }
        var result: Date?
        walk(value) { child, _ in
            guard result == nil, let object = child as? [String: Any] else { return }
            for (key, value) in object where keys.contains(normalizedKey(key)) {
                if let date = date(value) {
                    result = date
                    break
                }
            }
        }
        return result
    }

    static func accountName(in value: Any) -> String? {
        firstString(
            in: value,
            keys: [
                "accountname", "subusername", "username", "email",
                "nickname", "displayname", "userid", "useremail"
            ]
        )
    }

    static func modelName(in value: Any) -> String? {
        firstString(
            in: value,
            keys: [
                "model", "modelname", "modelid", "modelslug",
                "modelalias", "modeltype", "modelkey", "engine"
            ]
        )
    }

    static func tokenBreakdown(in value: Any) -> TokenBreakdown? {
        if let object = value as? [String: Any] {
            var preferred: [[String: Any]] = []
            if let providerData = object["providerData"] as? [String: Any] {
                if let rawUsage = providerData["rawUsage"] as? [String: Any] {
                    preferred.append(rawUsage)
                }
                if let usage = providerData["usage"] as? [String: Any] {
                    preferred.append(usage)
                }
            }
            if let message = object["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                preferred.append(usage)
            }
            if let usage = object["usage"] as? [String: Any] {
                preferred.append(usage)
            }
            if let result = preferred.lazy.compactMap({ parseTokenDictionary($0) }).first {
                return result
            }
            if let result = parseTokenDictionary(object) {
                return result
            }
        }
        var candidates: [(score: Int, value: TokenBreakdown)] = []
        walk(value) { child, path in
            guard let object = child as? [String: Any] else { return }
            guard let breakdown = parseTokenDictionary(object) else { return }

            let joinedPath = path.joined(separator: ".").lowercased()
            var score = 0
            if joinedPath.contains("rawusage") { score += 8 }
            if joinedPath.contains("usage") { score += 4 }
            if joinedPath.contains("providerdata") { score += 2 }
            if joinedPath.contains("message") { score += 1 }
            candidates.append((score, breakdown))
        }
        return candidates.max { lhs, rhs in lhs.score < rhs.score }?.value
    }

    private static func directNumber(in object: [String: Any], keys: Set<String>) -> Double? {
        for (key, value) in object where keys.contains(normalizedKey(key)) {
            if let result = number(value) { return result }
        }
        for child in object.values {
            guard let nested = child as? [String: Any] else { continue }
            for (key, value) in nested where keys.contains(normalizedKey(key)) {
                if let result = number(value) { return result }
            }
        }
        return nil
    }

    private static func directString(in object: [String: Any], keys: Set<String>) -> String? {
        for (key, value) in object where keys.contains(normalizedKey(key)) {
            if let result = string(value), !result.isEmpty { return result }
        }
        for child in object.values {
            guard let nested = child as? [String: Any] else { continue }
            for (key, value) in nested where keys.contains(normalizedKey(key)) {
                if let result = string(value), !result.isEmpty { return result }
            }
        }
        return nil
    }

    private static func directDate(in object: [String: Any], keys: Set<String>) -> Date? {
        for (key, value) in object where keys.contains(normalizedKey(key)) {
            if let result = date(value) { return result }
        }
        for child in object.values {
            guard let nested = child as? [String: Any] else { continue }
            for (key, value) in nested where keys.contains(normalizedKey(key)) {
                if let result = date(value) { return result }
            }
        }
        return nil
    }

    private static func parseTokenDictionary(_ object: [String: Any]) -> TokenBreakdown? {
        let names = Set(object.keys.map(normalizedKey))
        let tokenNames: Set<String> = [
            "inputtokens", "inputtoken", "outputtokens", "outputtoken",
            "totaltokens", "totaltoken", "prompttokens", "prompttoken",
            "completiontokens", "completiontoken", "cachereadinputtokens",
            "cachereadtoken", "cachecreationinputtokens", "cachecreationtoken",
            "cachedtokens", "cachewritetokens", "cachewritetoken",
            "reasoningtokens", "reasoningoutputtokens", "thoughts", "thinkingtokens"
        ]
        guard !names.isDisjoint(with: tokenNames) else { return nil }

        func valueFor(_ names: Set<String>) -> Double {
            for (key, value) in object where names.contains(normalizedKey(key)) {
                if let result = number(value) { return max(result, 0) }
            }
            return 0
        }

        let input = valueFor(["inputtokens", "inputtoken", "prompttokens", "prompttoken"])
        let output = valueFor(["outputtokens", "outputtoken", "completiontokens", "completiontoken"])
        let explicitTotal = valueFor(["totaltokens", "totaltoken"])
        let total = explicitTotal > 0 ? explicitTotal : input + output
        let cacheRead = valueFor(["cachereadinputtokens", "cachereadtoken", "cachedtokens"])
        let cacheWrite = valueFor(["cachecreationinputtokens", "cachecreationtoken", "cachewritetokens", "cachewritetoken"])
        let reasoning = valueFor(["reasoningtokens", "reasoningoutputtokens", "thoughts", "thinkingtokens"])
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

    static func jsonLines(
        under roots: [URL],
        maxFiles: Int = 500,
        maxLinesPerFile: Int = 20_000,
        modifiedAfter: Date? = nil
    ) -> [JSONLineRecord] {
        var candidates: [(url: URL, modifiedAt: Date)] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) {
                for case let url as URL in enumerator {
                    guard url.pathExtension.lowercased() == "jsonl" else { continue }
                    let modifiedAt = (try? url.resourceValues(forKeys: keys).contentModificationDate)
                        ?? Date.distantPast
                    if let modifiedAfter, modifiedAt < modifiedAfter { continue }
                    candidates.append((url, modifiedAt))
                }
            }
        }

        let urls = candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFiles)
            .map(\.url)

        var records: [JSONLineRecord] = []
        for url in urls {
            let fallbackDate = (try? url.resourceValues(forKeys: keys).contentModificationDate) ?? Date()
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
                if index >= maxLinesPerFile { break }
                guard let object = parseJSON(string: String(line)) else { continue }
                records.append(JSONLineRecord(
                    fileURL: url,
                    lineNumber: index + 1,
                    object: object,
                    fallbackDate: fallbackDate
                ))
            }
        }
        return records
    }
}

enum SQLiteReader {
    static func query(
        databaseURL: URL,
        sql: String
    ) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databaseURL.path, sql]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            guard let parsed = LocalData.parseJSON(data: data) as? [[String: Any]] else {
                return []
            }
            return parsed
        } catch {
            return []
        }
    }
}

enum UsageMetrics {
    static func localMetrics(
        summary: LocalUsageSummary,
        includeCredits: Bool = false,
        includeMoney: Bool = false,
        moneyUnit: String = "USD"
    ) -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        let buckets: [(UsageWindow, UsageBucket)] = [
            (.today, summary.today),
            (.yesterday, summary.yesterday),
            (.weekly, summary.thisWeek),
            (.lastWeek, summary.lastWeek),
            (.monthly, summary.month),
            (.lastMonth, summary.lastMonth),
            (.yearly, summary.year)
        ]
        for (window, bucket) in buckets {
            if bucket.tokens.hasTokens {
                metrics.append(UsageMetric(
                    key: "tokens-\(window.rawValue)",
                    title: "Token",
                    kind: .tokens,
                    window: window,
                    used: bucket.tokens.total,
                    limit: nil,
                    remaining: nil,
                    unit: "tokens",
                    source: .local,
                    resetAt: nil,
                    note: "按本机日志汇总",
                    inputTokens: bucket.tokens.input,
                    outputTokens: bucket.tokens.output,
                    cacheReadTokens: bucket.tokens.cacheRead,
                    cacheWriteTokens: bucket.tokens.cacheWrite,
                    reasoningTokens: bucket.tokens.reasoning,
                    inputIncludesCache: bucket.tokens.inputIncludesCache
                ))
                if bucket.tokens.input > 0 || bucket.tokens.output > 0 {
                    metrics.append(UsageMetric(
                        key: "token-breakdown-\(window.rawValue)",
                        title: "输入 / 输出",
                        kind: .tokens,
                        window: window,
                        used: bucket.tokens.input + bucket.tokens.output,
                        limit: nil,
                        remaining: nil,
                        unit: "输入 \(NumberFormat.compact(bucket.tokens.input)) · 输出 \(NumberFormat.compact(bucket.tokens.output))",
                        source: .local,
                        resetAt: nil,
                        note: nil,
                        inputTokens: bucket.tokens.input,
                        outputTokens: bucket.tokens.output,
                        cacheReadTokens: bucket.tokens.cacheRead,
                        cacheWriteTokens: bucket.tokens.cacheWrite,
                        reasoningTokens: bucket.tokens.reasoning,
                        inputIncludesCache: bucket.tokens.inputIncludesCache
                    ))
                }
                if bucket.tokens.cacheRead > 0 {
                    metrics.append(UsageMetric(
                        key: "cache-\(window.rawValue)",
                        title: "缓存读取",
                        kind: .tokens,
                        window: window,
                        used: bucket.tokens.cacheRead,
                        limit: nil,
                        remaining: nil,
                        unit: "tokens",
                        source: .local,
                        resetAt: nil,
                        note: nil,
                        cacheReadTokens: bucket.tokens.cacheRead
                    ))
                }
            }
            let activityCount = bucket.sessions.isEmpty ? bucket.requests : Double(bucket.sessions.count)
            if activityCount > 0 {
                metrics.append(UsageMetric(
                    key: "requests-\(window.rawValue)",
                    title: bucket.sessions.isEmpty ? "请求次数" : "会话数",
                    kind: .requests,
                    window: window,
                    used: activityCount,
                    limit: nil,
                    remaining: nil,
                    unit: "次",
                    source: .local,
                    resetAt: nil,
                    note: bucket.sessions.isEmpty
                        ? "按可识别的用量记录计数"
                        : "按去重后的 Codex rollout 会话文件计数"
                ))
            }
            if includeCredits, bucket.credits > 0 {
                metrics.append(UsageMetric(
                    key: "credits-\(window.rawValue)",
                    title: "Credits",
                    kind: .credits,
                    window: window,
                    used: bucket.credits,
                    limit: nil,
                    remaining: nil,
                    unit: "credits",
                    source: .local,
                    resetAt: nil,
                    note: nil
                ))
            }
            if includeMoney, bucket.cost > 0 {
                metrics.append(UsageMetric(
                    key: "cost-\(window.rawValue)",
                    title: "金额",
                    kind: .money,
                    window: window,
                    used: bucket.cost,
                    limit: nil,
                    remaining: nil,
                    unit: moneyUnit,
                    source: .local,
                    resetAt: nil,
                    note: nil
                ))
            }
        }
        return metrics
    }

    static func modelUsages(summary: LocalUsageSummary) -> [ModelUsage] {
        let buckets: [(UsageWindow, UsageBucket)] = [
            (.today, summary.today),
            (.yesterday, summary.yesterday),
            (.weekly, summary.thisWeek),
            (.lastWeek, summary.lastWeek),
            (.monthly, summary.month),
            (.lastMonth, summary.lastMonth),
            (.yearly, summary.year)
        ]
        return buckets.flatMap { _, bucket in
            bucket.models.values.filter(\.hasUsage)
        }
    }
}

enum NumberFormat {
    static func compact(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "—" }
        let absolute = abs(value)
        if absolute >= 100_000_000 {
            return String(format: "%.1f亿", value / 100_000_000)
        }
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    static func currency(_ value: Double) -> String {
        currency(value, unit: "USD")
    }

    static func currency(_ value: Double, unit: String) -> String {
        let isCNY = unit.uppercased() == "CNY"
        let symbol = isCNY ? "¥" : "$"
        // DeepSeek's console presents CNY spend at two decimal places using
        // a truncated display value; keep the full precision in aggregation.
        let displayValue = isCNY
            ? (value * 100).rounded(.down) / 100
            : value
        return String(format: "%@%.2f", symbol, displayValue)
    }

    static func durationMinutes(_ value: Double) -> String {
        let minutes = max(Int(value.rounded()), 0)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h\(String(format: "%02d", remainder))"
    }
}
