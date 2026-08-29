import Foundation

/// Persists the latest usable dashboard data without storing prompts, request
/// bodies, credentials, or raw provider logs.  The cache is a presentation
/// fallback only: a fresh local scan always replaces it when available.
enum UsageSnapshotCache {
    private struct Payload: Codable {
        let version: Int
        let snapshots: [ProviderSnapshot]
    }

    private static let version = 1

    static func load() -> [ProviderSnapshot]? {
        guard let data = try? Data(contentsOf: AppPaths.usageSnapshotCache),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else {
            return nil
        }

        let snapshotsByProvider = Dictionary(uniqueKeysWithValues: payload.snapshots.map {
            ($0.provider, $0)
        })
        let snapshots = ProviderID.trackedCases.compactMap { provider in
            snapshotsByProvider[provider]
                .map(Self.rebasedForCurrentDay)
                .map(\.cachedVersion)
        }
        return snapshots.isEmpty ? nil : snapshots
    }

    /// A cached daily aggregate is otherwise relabeled as today's usage after
    /// midnight when the provider cannot be scanned. Doubao Work is kept
    /// visible while its client is closed, so move a one-day-old cached
    /// aggregate to yesterday and never leave it under today's label.
    static func rebasedForCurrentDay(_ snapshot: ProviderSnapshot) -> ProviderSnapshot {
        guard snapshot.provider == .doubaoWork else { return snapshot }

        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let snapshotDay = calendar.startOfDay(for: snapshot.updatedAt)
        let dayDistance = calendar.dateComponents(
            [.day],
            from: snapshotDay,
            to: startOfToday
        ).day ?? 0
        guard dayDistance > 0 else { return snapshot }

        return ProviderSnapshot(
            provider: snapshot.provider,
            accounts: snapshot.accounts.map {
                rebasedAccount($0, moveToYesterday: dayDistance == 1)
            },
            state: snapshot.state,
            updatedAt: snapshot.updatedAt
        )
    }

    private static func rebasedAccount(
        _ account: AccountUsageSnapshot,
        moveToYesterday: Bool
    ) -> AccountUsageSnapshot {
        let dailyMetrics = account.metrics.filter { $0.window == .today }
        let metrics = account.metrics.filter {
            $0.window != .today && $0.window != .yesterday
        } + (moveToYesterday ? dailyMetrics.map { $0.rebased(to: .yesterday) } : [])

        let dailyModels = account.modelUsages.filter { $0.window == .today }
        let modelUsages = account.modelUsages.filter {
            $0.window != .today && $0.window != .yesterday
        } + (moveToYesterday ? dailyModels.map { $0.rebased(to: .yesterday) } : [])

        return AccountUsageSnapshot(
            id: account.id,
            provider: account.provider,
            accountName: account.accountName,
            planName: account.planName,
            state: account.state,
            metrics: metrics,
            updatedAt: account.updatedAt,
            message: account.message,
            source: account.source,
            modelUsages: modelUsages
        )
    }

    static func save(_ snapshots: [ProviderSnapshot]) {
        let usable = snapshots.filter { snapshot in
            snapshot.accounts.contains { !$0.metrics.isEmpty }
        }
        guard !usable.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(
                at: AppPaths.appSupport,
                withIntermediateDirectories: true
            )
            let payload = Payload(version: version, snapshots: usable)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: AppPaths.usageSnapshotCache, options: .atomic)
        } catch {
            // A cache failure must never make a provider scan fail.
        }
    }
}

private extension UsageMetric {
    func rebased(to window: UsageWindow) -> UsageMetric {
        UsageMetric(
            key: key.replacingOccurrences(of: "-today", with: "-\(window.rawValue)"),
            title: title,
            kind: kind,
            window: window,
            used: used,
            limit: limit,
            remaining: remaining,
            unit: unit,
            source: source,
            resetAt: resetAt,
            note: note,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            reasoningTokens: reasoningTokens,
            inputIncludesCache: inputIncludesCache
        )
    }

    var cachedVersion: UsageMetric {
        UsageMetric(
            key: key,
            title: title,
            kind: kind,
            window: window,
            used: used,
            limit: limit,
            remaining: remaining,
            unit: unit,
            source: .cached,
            resetAt: resetAt,
            note: note,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            reasoningTokens: reasoningTokens,
            inputIncludesCache: inputIncludesCache
        )
    }
}

private extension AccountUsageSnapshot {
    var cachedVersion: AccountUsageSnapshot {
        AccountUsageSnapshot(
            id: id,
            provider: provider,
            accountName: accountName,
            planName: planName,
            state: .cached,
            metrics: metrics.map(\.cachedVersion),
            updatedAt: updatedAt,
            message: [
                "目标应用当前未运行，以下为最近一次成功读取的用量。",
                message
            ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n"),
            source: .cached,
            modelUsages: modelUsages
        )
    }
}

private extension ModelUsage {
    func rebased(to window: UsageWindow) -> ModelUsage {
        var rebased = ModelUsage(name: name, window: window)
        rebased.tokens = tokens
        rebased.requests = requests
        rebased.credits = credits
        rebased.cost = cost
        return rebased
    }
}

private extension ProviderSnapshot {
    var cachedVersion: ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            accounts: accounts
                .filter { !$0.metrics.isEmpty }
                .map(\.cachedVersion),
            state: .cached,
            updatedAt: updatedAt
        )
    }
}
