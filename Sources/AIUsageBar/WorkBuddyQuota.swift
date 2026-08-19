import Foundation

struct WorkBuddyQuotaResult {
    let metric: UsageMetric
    let packageName: String?
}

enum WorkBuddyQuotaService {
    private static let endpoint = URL(string: "https://www.codebuddy.cn/v2/billing/meter/get-user-resource")!

    private struct ResourcePackage {
        let name: String?
        let remaining: Double
        let limit: Double
        let expiresAt: Date?
        let isExpired: Bool
    }

    static func fetch(now: Date = Date()) async -> WorkBuddyQuotaResult? {
        guard let auth = LocalData.loadJSON(at: AppPaths.workBuddyAuthFile) as? [String: Any],
              let authObject = auth["auth"] as? [String: Any],
              let token = LocalData.string(authObject["accessToken"]),
              !token.isEmpty else { return nil }

        do {
            let result = try await HTTPJSON.post(
                url: endpoint,
                body: [:],
                headers: [
                    "Authorization": "Bearer \(token)",
                    "User-Agent": "WorkBuddy",
                    "Content-Type": "application/json"
                ]
            )
            guard result.statusCode == 200,
                  let accounts = accountRecords(in: result.object),
                  !accounts.isEmpty else { return nil }

            let packages = accounts.compactMap { makePackage(from: $0, now: now) }
            let activePackages = packages.filter { !$0.isExpired }
            var total = activePackages.reduce(0) { $0 + $1.limit }
            var remaining = activePackages.reduce(0) { $0 + $1.remaining }
            guard total > 0 else { return nil }

            // WorkBuddy may return a fractional precise value alongside its
            // rounded integer field. Keep the exact value, then clamp the
            // aggregate once to avoid a package with inconsistent fields
            // making the progress bar exceed 100%.
            remaining = min(max(remaining, 0), total)
            total = max(total, remaining)

            let availablePackages = activePackages
                .filter { $0.remaining > 0 }
                .sorted { lhs, rhs in
                    switch (lhs.expiresAt, rhs.expiresAt) {
                    case let (left?, right?):
                        if left != right { return left < right }
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    default:
                        break
                    }
                    return lhs.remaining > rhs.remaining
                }
            let packageName = availablePackages.first?.name
            let resetAt = availablePackages.first?.expiresAt

            let used = min(max(total - remaining, 0), total)
            return WorkBuddyQuotaResult(
                metric: UsageMetric(
                    key: "workbuddy-cycle-credits",
                    title: "订阅 Credits",
                    kind: .quota,
                    window: .monthly,
                    used: used,
                    limit: total,
                    remaining: max(total - used, 0),
                    unit: "Credits",
                    source: .server,
                    resetAt: resetAt,
                    note: "CodeBuddy get-user-resource · 有效资源包余额"
                ),
                packageName: packageName
            )
        } catch {
            return nil
        }
    }

    private static func makePackage(from account: [String: Any], now: Date) -> ResourcePackage? {
        let unit = directString(in: account, keys: ["capacityunit", "originunit"])?.lowercased()
        if let unit, !unit.isEmpty, unit != "credit", unit != "credits" {
            return nil
        }

        let capacitySize = directNumber(
            in: account,
            keys: ["capacitysizeprecise", "capacitysize"]
        ) ?? 0
        let capacityRemain = directNumber(
            in: account,
            keys: ["capacityremainprecise", "capacityremain"]
        ) ?? 0
        let cycleSize = directNumber(
            in: account,
            keys: ["cyclecapacitysizeprecise", "cyclecapacitysize"]
        ) ?? 0
        let cycleRemain = directNumber(
            in: account,
            keys: ["cyclecapacityremainprecise", "cyclecapacityremain"]
        ) ?? 0
        let cycleUsed = directNumber(
            in: account,
            keys: ["cyclecapacityusedprecise", "cyclecapacityused"]
        ) ?? 0

        // This mirrors the official resource-package behavior used by
        // WorkBuddy clients: once a cycle has usage, CycleCapacityRemain is
        // authoritative; for an untouched cycle, CapacityRemain is the
        // usable package balance.
        let effectiveRemaining = cycleRemain > 0 || cycleUsed > 0
            ? cycleRemain
            : capacityRemain
        let effectiveLimit = cycleSize > 0 ? cycleSize : capacitySize
        let limit = max(effectiveLimit, effectiveRemaining)
        guard limit > 0 else { return nil }

        let remaining = min(max(effectiveRemaining, 0), limit)
        let expiresAt = firstDate(
            in: account,
            keys: ["expiredtime", "deductionendtime", "cycleendtime", "endtime"]
        )
        return ResourcePackage(
            name: directString(in: account, keys: ["packagename", "dealname", "productname"]),
            remaining: expiresAt.map { $0 < now } == true ? 0 : remaining,
            limit: limit,
            expiresAt: expiresAt,
            isExpired: expiresAt.map { $0 < now } == true
        )
    }

    private static func accountRecords(in value: Any) -> [[String: Any]]? {
        var result: [[String: Any]]?
        LocalData.walk(value) { child, _ in
            guard result == nil, let object = child as? [String: Any] else { return }
            for (key, value) in object where LocalData.normalizedKey(key) == "accounts" {
                if let array = value as? [[String: Any]], !array.isEmpty {
                    result = array
                    return
                }
                if let array = value as? [Any] {
                    let records = array.compactMap { $0 as? [String: Any] }
                    if !records.isEmpty {
                        result = records
                        return
                    }
                }
            }
        }
        return result
    }

    private static func directNumber(in object: [String: Any], keys: [String]) -> Double? {
        for requestedKey in keys {
            let normalizedRequestedKey = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalizedRequestedKey {
                if let number = LocalData.number(value) { return number }
            }
        }
        return nil
    }

    private static func directString(in object: [String: Any], keys: [String]) -> String? {
        for requestedKey in keys {
            let normalizedRequestedKey = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalizedRequestedKey {
                if let string = LocalData.string(value), !string.isEmpty { return string }
            }
        }
        return nil
    }

    private static func firstDate(in object: [String: Any], keys: [String]) -> Date? {
        for requestedKey in keys {
            let normalizedRequestedKey = LocalData.normalizedKey(requestedKey)
            for (key, value) in object where LocalData.normalizedKey(key) == normalizedRequestedKey {
                if let date = parseDate(LocalData.string(value)) ?? LocalData.date(value) {
                    return date
                }
            }
        }
        return nil
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.date(from: value)
    }
}
