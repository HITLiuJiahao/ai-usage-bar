import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case codex
    case chatGPT
    case qwenWork
    case zcode
    case openCode
    case doubaoWork
    case qianwenOffice
    case deepSeekHarness
    case workBuddy
    case miniMax

    var id: String { rawValue }

    // Keep the dashboard order stable for the two-column layout.
    static let trackedCases: [ProviderID] = [
        .codex, .qwenWork, .zcode, .doubaoWork,
        .workBuddy, .miniMax,
        .openCode, .qianwenOffice, .deepSeekHarness
    ]

    var displayName: String {
        L10n.providerName(self)
    }

    var shortName: String {
        L10n.providerName(self)
    }

    var symbolName: String {
        switch self {
        case .codex: return "terminal"
        case .chatGPT: return "bubble.left.and.bubble.right"
        case .qwenWork: return "sparkles"
        case .zcode: return "chevron.left.forwardslash.chevron.right"
        case .openCode: return "terminal.fill"
        case .doubaoWork: return "briefcase.fill"
        case .qianwenOffice: return "briefcase.fill"
        case .deepSeekHarness: return "brain.head.profile"
        case .workBuddy: return "person.2.wave.2"
        case .miniMax: return "hexagon"
        }
    }
}

enum ProviderState: Codable {
    case connected
    case partial
    case cached
    case unavailable

    var title: String {
        L10n.stateTitle(self)
    }
}

enum DataSource: Codable {
    case server
    case local
    case cached
    case unavailable

    var title: String {
        L10n.sourceTitle(self)
    }
}

enum MetricKind: Codable {
    case tokens
    case requests
    case duration
    case credits
    case money
    case quota
}

enum UsageWindow: String, Codable {
    case today
    case yesterday
    case fiveHours
    case daily
    case weekly
    case lastWeek
    case monthly
    case lastMonth
    case yearly
    case billing

    var title: String {
        L10n.windowTitle(self)
    }
}

struct UsageMetric: Identifiable, Codable {
    let key: String
    let title: String
    let kind: MetricKind
    let window: UsageWindow
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let unit: String
    let source: DataSource
    let resetAt: Date?
    let note: String?
    let inputTokens: Double?
    let outputTokens: Double?
    let cacheReadTokens: Double?
    let cacheWriteTokens: Double?
    let reasoningTokens: Double?
    /// Whether `inputTokens` already includes cache-read/cache-write tokens.
    /// This is needed for providers whose card follows Tokei's prompt-total
    /// presentation instead of exposing only the uncached input amount.
    let inputIncludesCache: Bool

    init(
        key: String,
        title: String,
        kind: MetricKind,
        window: UsageWindow,
        used: Double?,
        limit: Double?,
        remaining: Double?,
        unit: String,
        source: DataSource,
        resetAt: Date?,
        note: String?,
        inputTokens: Double? = nil,
        outputTokens: Double? = nil,
        cacheReadTokens: Double? = nil,
        cacheWriteTokens: Double? = nil,
        reasoningTokens: Double? = nil,
        inputIncludesCache: Bool = false
    ) {
        self.key = key
        self.title = title
        self.kind = kind
        self.window = window
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.unit = unit
        self.source = source
        self.resetAt = resetAt
        self.note = note
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.reasoningTokens = reasoningTokens
        self.inputIncludesCache = inputIncludesCache
    }

    var id: String { key }

    var progress: Double? {
        if let used, let limit, limit > 0 {
            return min(max(used / limit, 0), 1)
        }
        if let remaining, let limit, limit > 0 {
            return min(max(1 - remaining / limit, 0), 1)
        }
        return nil
    }

    /// Whether this metric represents actual activity in its time window.
    /// A remaining quota by itself is not activity, so an untouched plan can
    /// be omitted from the period dashboard just like Tokei does.
    var hasActualUsage: Bool {
        if let used, used > 0 { return true }
        return [inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, reasoningTokens]
            .contains { ($0 ?? 0) > 0 }
    }
}

struct ModelUsage: Identifiable, Codable {
    let name: String
    let window: UsageWindow
    var tokens = TokenBreakdown()
    var requests: Double = 0
    var credits: Double = 0
    var cost: Double = 0

    var id: String { "\(window.rawValue)-\(name)" }

    var hitRate: Double? {
        let denominator = tokens.inputIncludesCache
            ? tokens.input
            : tokens.input + tokens.cacheRead + tokens.cacheWrite
        guard denominator > 0 else { return nil }
        return min(max(tokens.cacheRead / denominator, 0), 1)
    }

    var hasUsage: Bool {
        tokens.hasTokens || requests > 0 || credits > 0 || cost > 0
    }

    init(name: String, window: UsageWindow) {
        self.name = ModelUsage.normalizedName(name)
        self.window = window
    }

    static func normalizedName(_ value: String?) -> String {
        guard let value else { return "未知" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未知" }
        let lowercased = trimmed.lowercased()
        if ["unknown", "null", "nil", "none", "default"].contains(lowercased) {
            return "未知"
        }
        return trimmed
    }

    mutating func add(
        tokens: TokenBreakdown?,
        requests: Double = 0,
        credits: Double = 0,
        cost: Double = 0
    ) {
        if let tokens {
            self.tokens.add(tokens)
        }
        self.requests += requests
        self.credits += credits
        self.cost += cost
    }
}

struct AccountUsageSnapshot: Identifiable, Codable {
    let id: String
    let provider: ProviderID
    let accountName: String
    let planName: String?
    let resetCreditsAvailableCount: Int?
    let resetCreditsExpiresAt: Date?
    let state: ProviderState
    let metrics: [UsageMetric]
    let updatedAt: Date
    let message: String?
    let source: DataSource
    let modelUsages: [ModelUsage]

    init(
        id: String,
        provider: ProviderID,
        accountName: String,
        planName: String? = nil,
        resetCreditsAvailableCount: Int? = nil,
        resetCreditsExpiresAt: Date? = nil,
        state: ProviderState,
        metrics: [UsageMetric],
        updatedAt: Date,
        message: String?,
        source: DataSource,
        modelUsages: [ModelUsage] = []
    ) {
        self.id = id
        self.provider = provider
        self.accountName = accountName
        self.planName = planName
        self.resetCreditsAvailableCount = resetCreditsAvailableCount
        self.resetCreditsExpiresAt = resetCreditsExpiresAt
        self.state = state
        self.metrics = metrics
        self.updatedAt = updatedAt
        self.message = message
        self.source = source
        self.modelUsages = modelUsages
    }
}

struct ProviderSnapshot: Identifiable, Codable {
    let provider: ProviderID
    let accounts: [AccountUsageSnapshot]
    let state: ProviderState
    let updatedAt: Date

    var id: String { provider.id }

    var metricCount: Int {
        accounts.reduce(0) { $0 + $1.metrics.count }
    }

    static func empty(for provider: ProviderID) -> ProviderSnapshot {
        let now = Date()
        return ProviderSnapshot(
            provider: provider,
            accounts: [
                AccountUsageSnapshot(
                    id: "\(provider.rawValue)-default",
                    provider: provider,
                    accountName: "当前账户",
                    state: .unavailable,
                    metrics: [],
                    updatedAt: now,
                    message: "等待首次读取",
                    source: .unavailable
                )
            ],
            state: .unavailable,
            updatedAt: now
        )
    }
}
