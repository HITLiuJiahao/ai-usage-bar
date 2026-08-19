import Foundation

struct QwenWorkCredentialCandidate {
    let id: String
    let name: String
    let token: String
}

struct QwenWorkQuotaResult {
    let metrics: [UsageMetric]
    let accountName: String?
    let userID: String?
    let planName: String?
}

/// Reads the same account-level quota that QwenWork shows in its Usage page.
/// QwenWork keeps its browser access token in Electron safeStorage, so this
/// adapter deliberately accepts an explicitly supplied token instead of
/// attempting to bypass that protection. The token can be stored through the
/// account settings view, or supplied as QWENWORK_ACCESS_TOKEN.
enum QwenWorkQuotaService {
    private static let endpoint = URL(string: "https://gateway.qwenwork.cn/api/v1/adapter/user/account-context?include=user,plan,quota,page,data_sharing")!

    static func credentialCandidates() -> [QwenWorkCredentialCandidate] {
        var candidates: [QwenWorkCredentialCandidate] = []
        var seenTokens: Set<String> = []

        if let environmentToken = ProcessInfo.processInfo.environment["QWENWORK_ACCESS_TOKEN"],
           let candidate = makeCandidate(
               id: "environment",
               name: "QwenWork 环境凭据",
               token: environmentToken,
               seenTokens: &seenTokens
           ) {
            candidates.append(candidate)
        }

        for account in LocalAccountStore.accounts(for: .qwenWork) {
            guard let token = CredentialKeychain.load(for: account),
                  let candidate = makeCandidate(
                      id: account.id.uuidString,
                      name: account.name,
                      token: token,
                      seenTokens: &seenTokens
                  ) else { continue }
            candidates.append(candidate)
        }

        // QwenWork writes this sidecar only when Electron safeStorage is not
        // available. It is useful for portable/dev installations, but the
        // encrypted auth-v2.dat file is intentionally not treated as JSON.
        for url in AppPaths.qwenAuthFallbackCandidates {
            guard let object = LocalData.loadJSON(at: url) as? [String: Any],
                  let token = directString(in: object, keys: ["token", "access_token", "accessToken"]),
                  let candidate = makeCandidate(
                      id: "fallback-\(url.lastPathComponent)",
                      name: LocalData.accountName(in: object) ?? "QwenWork 当前账户",
                      token: token,
                      seenTokens: &seenTokens
                  ) else { continue }
            candidates.append(candidate)
        }

        return candidates
    }

    static func fetch(token: String) async -> QwenWorkQuotaResult? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }

        let clientVersion = qwenWorkVersion()
        let headers = [
            "Accept": "application/json",
            "Authorization": "Bearer \(trimmed)",
            "User-Agent": "qwenwork/\(clientVersion)",
            "X-Request-Id": UUID().uuidString,
            "X-QwenWork-Version": clientVersion,
            "X-QwenWork-Release-Version": clientVersion,
            "X-QwenWork-Build": clientVersion,
            "X-QwenWork-Platform": "darwin",
            "X-QwenWork-Arch": qwenWorkArchitecture,
            "X-QwenWork-Channel": "stable"
        ]

        do {
            let result = try await HTTPJSON.get(url: endpoint, headers: headers)
            guard (200..<300).contains(result.statusCode) else { return nil }
            return parse(result.object)
        } catch {
            return nil
        }
    }

    private static func parse(_ value: Any) -> QwenWorkQuotaResult? {
        guard let root = value as? [String: Any] else { return nil }
        let context = normalizedContext(root)
        let quota = directObject(in: context, keys: ["quota"])
            ?? directObject(in: root, keys: ["quota"])
        guard let quota else { return nil }

        // This mirrors QwenWork's own account-context adapter: quota must have
        // a remaining value, while user_quota is the personal plan bucket.
        guard directNumber(in: quota, keys: ["remaining"]) != nil
            || directObject(in: quota, keys: ["user_quota", "userQuota"]).flatMap({
                directNumber(in: $0, keys: ["remaining"])
            }) != nil else { return nil }

        var metrics: [UsageMetric] = []
        let userQuota = directObject(in: quota, keys: ["user_quota", "userQuota"]) ?? quota
        let quotaExpiration = firstDate(
            in: quota,
            keys: ["expires_at", "expiresAt", "expiration", "expire_at", "end_at", "endAt"]
        )
        if let metric = makeMetric(
            object: userQuota,
            key: "qwenwork-user-credits",
            title: "订阅 Credits",
            note: "QwenWork 官方 account-context · quota.user_quota",
            inheritedResetAt: quotaExpiration
        ) {
            metrics.append(metric)
        }

        if let addOn = directObject(in: quota, keys: ["add_on_quota", "addOnQuota"]),
           let metric = makeMetric(
               object: addOn,
               key: "qwenwork-add-on-credits",
               title: "加购 Credits",
               note: "QwenWork 官方 account-context · quota.add_on_quota",
               inheritedResetAt: quotaExpiration
           ) {
            metrics.append(metric)
        }

        if let shared = directObject(in: quota, keys: ["org_resource_package", "orgResourcePackage", "shared_quota", "sharedQuota"]),
           let metric = makeMetric(
               object: shared,
               key: "qwenwork-shared-credits",
               title: "共享 Credits",
               note: "QwenWork 官方 account-context · quota.org_resource_package",
               inheritedResetAt: quotaExpiration
           ) {
            metrics.append(metric)
        }

        guard !metrics.isEmpty else { return nil }
        let user = directObject(in: context, keys: ["user"])
        let plan = directObject(in: context, keys: ["plan"])
        let accountName = directString(
            in: user ?? context,
            keys: ["name", "username", "email", "nickname", "display_name", "displayName"]
        )
        let userID = directString(in: user ?? context, keys: ["id", "user_id", "userId"])
        let planName = directString(in: plan ?? [:], keys: ["name", "tier", "plan_name", "planName"])

        return QwenWorkQuotaResult(
            metrics: metrics,
            accountName: accountName,
            userID: userID,
            planName: planName
        )
    }

    private static func normalizedContext(_ root: [String: Any]) -> [String: Any] {
        var context = directObject(in: root, keys: ["data"]) ?? root
        if let user = directObject(in: context, keys: ["user"]) {
            for (key, value) in user where context[key] == nil {
                context[key] = value
            }
        }
        return context
    }

    private static func makeMetric(
        object: [String: Any],
        key: String,
        title: String,
        note: String,
        inheritedResetAt: Date? = nil
    ) -> UsageMetric? {
        let rawTotal = directNumber(in: object, keys: ["total", "cap"])
        let rawUsed = directNumber(in: object, keys: ["used"])
        let rawRemaining = directNumber(in: object, keys: ["remaining"])
        let remaining: Double
        if let rawRemaining, rawRemaining.isFinite {
            remaining = max(rawRemaining, 0)
        } else if let rawTotal, rawTotal.isFinite, let rawUsed, rawUsed.isFinite {
            remaining = max(rawTotal - rawUsed, 0)
        } else {
            return nil
        }
        let inferredUsed = rawUsed ?? max((rawTotal ?? 0) - remaining, 0)
        let total = max(rawTotal ?? 0, inferredUsed + remaining)
        guard total > 0 || remaining > 0 || inferredUsed > 0 else { return nil }

        let used = min(max(inferredUsed, 0), max(total, inferredUsed + remaining))
        let resetAt = firstDate(
            in: object,
            keys: ["expires_at", "expiresAt", "expiration", "expire_at", "end_at", "endAt"]
        ) ?? inheritedResetAt
        return UsageMetric(
            key: key,
            title: title,
            kind: .quota,
            window: .billing,
            used: used,
            limit: max(total, used + remaining),
            remaining: remaining,
            unit: directString(in: object, keys: ["unit"]) ?? "Credits",
            source: .server,
            resetAt: resetAt,
            note: note
        )
    }

    private static func makeCandidate(
        id: String,
        name: String,
        token: String,
        seenTokens: inout Set<String>
    ) -> QwenWorkCredentialCandidate? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), seenTokens.insert(trimmed).inserted else {
            return nil
        }
        return QwenWorkCredentialCandidate(id: id, name: name, token: trimmed)
    }

    private static func qwenWorkVersion() -> String {
        if let status = LocalData.loadJSON(at: AppPaths.qwenStatusSnapshot),
           let version = LocalData.firstString(in: status, keys: Set(["version"])),
           !version.isEmpty {
            return version
        }
        return "unknown"
    }

    private static func directObject(in object: [String: Any], keys: [String]) -> [String: Any]? {
        for requestedKey in keys {
            let normalized = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalized {
                if let nested = value as? [String: Any] { return nested }
            }
        }
        return nil
    }

    private static func directNumber(in object: [String: Any], keys: [String]) -> Double? {
        for requestedKey in keys {
            let normalized = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalized {
                if let number = LocalData.number(value), number.isFinite { return number }
            }
        }
        return nil
    }

    private static func directString(in object: [String: Any], keys: [String]) -> String? {
        for requestedKey in keys {
            let normalized = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalized {
                if let string = LocalData.string(value), !string.isEmpty { return string }
            }
        }
        return nil
    }

    private static func firstDate(in object: [String: Any], keys: [String]) -> Date? {
        for requestedKey in keys {
            let normalized = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalized {
                if let date = LocalData.date(value) { return date }
            }
        }
        return nil
    }

    private static let qwenWorkArchitecture: String = {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x64"
        #else
        return "unknown"
        #endif
    }()
}
