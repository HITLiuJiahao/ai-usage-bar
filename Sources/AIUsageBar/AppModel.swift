import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot] = ProviderID.trackedCases.map(ProviderSnapshot.empty)
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var refreshError: String?

    private let refreshInterval: TimeInterval = 30
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshInFlight = false
    private var refreshPending = false
    private var forceQuotaRefreshPending = false
    private var retryCount = 0

    init() {
        if let cachedSnapshots = UsageSnapshotCache.load() {
            snapshots = ProviderID.trackedCases.map { provider in
                cachedSnapshots.first(where: { $0.provider == provider })
                    ?? ProviderSnapshot.empty(for: provider)
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
    }

    func refresh(forceQuota: Bool = false) {
        if forceQuota {
            forceQuotaRefreshPending = true
        }
        if refreshInFlight {
            // Do not start a second scan while one is active. Remember the
            // request and run exactly one follow-up pass when this one ends.
            refreshPending = true
            return
        }

        refreshInFlight = true
        refreshPending = false
        isRefreshing = true
        refreshTask = Task { [weak self] in
            await self?.refreshLoop()
        }
    }

    private func refreshLoop() async {
        retryCount = 0

        while true {
            refreshPending = false
            let forceQuota = forceQuotaRefreshPending
            forceQuotaRefreshPending = false
            let hasUsableData = await performRefreshPass(forceCodexQuota: forceQuota)

            // Match Tokei's initial-load retry behavior. Providers return a
            // snapshot instead of throwing, so a retry is useful only when
            // the whole first pass produced no usable data.
            if !hasUsableData && !refreshPending && !Task.isCancelled && retryCount < 3 {
                retryCount += 1
                refreshError = L10n.readFailedRetry(count: retryCount)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                continue
            }

            if refreshPending && !Task.isCancelled {
                continue
            }

            break
        }

        if !Task.isCancelled {
            lastRefreshAt = Date()
        }
        refreshInFlight = false
        isRefreshing = false
        refreshTask = nil
    }

    private func performRefreshPass(forceCodexQuota: Bool) async -> Bool {
        refreshError = nil
        let providers = ProviderRegistry.all

        // Each provider is independent. Fetch them concurrently so a slow
        // network endpoint cannot hold back local log based providers.
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            for provider in providers {
                group.addTask(priority: .utility) {
                    await provider.fetch(forceRefresh: forceCodexQuota && provider.id == .codex)
                }
            }

            for await snapshot in group {
                guard let index = snapshots.firstIndex(where: { $0.provider == snapshot.provider }) else {
                    continue
                }

                // Keep the last usable result when a local source is empty or
                // temporarily unavailable. Closing a client must not erase
                // the historical usage already shown by the dashboard.
                let previous = snapshots[index]
                if snapshot.provider != .doubaoWork,
                   previous.metricCount > 0,
                   (snapshot.metricCount == 0 || snapshot.state == .unavailable) {
                    snapshots[index] = UsageSnapshotCache.rebasedForCurrentDay(previous)
                    continue
                }
                snapshots[index] = snapshot
            }
        }

        UsageSnapshotCache.save(snapshots)

        let hasUsableData = snapshots.contains { snapshot in
            snapshot.state != .unavailable && snapshot.metricCount > 0
        }
        if !hasUsableData {
            refreshError = L10n.text(.usageUnavailable)
        }
        return hasUsableData
    }

    var connectedCount: Int {
        snapshots.filter { $0.state != .unavailable }.count
    }

    var codexFiveHoursRemainingPercent: Int? {
        codexRemainingPercent(for: .fiveHours)
    }

    var codexWeeklyRemainingPercent: Int? {
        codexRemainingPercent(for: .weekly)
    }

    /// Prefer the short rolling window when the account exposes it. Some
    /// Codex plans expose only the seven-day window, so the status item must
    /// fall back instead of going blank for those accounts.
    var codexStatusQuota: (window: UsageWindow, remaining: Int)? {
        for window in [UsageWindow.fiveHours, .weekly] {
            if let remaining = codexRemainingPercent(for: window) {
                return (window, remaining)
            }
        }
        return nil
    }

    private func codexRemainingPercent(for window: UsageWindow) -> Int? {
        let quotaMetric = snapshots
            .first(where: { $0.provider == .codex })?
            .accounts
            .flatMap(\.metrics)
            .first(where: { metric in
                metric.kind == .quota && metric.window == window
            })
        guard let remaining = quotaMetric?.remaining, remaining.isFinite else {
            return nil
        }
        return Int(min(max(remaining, 0), 100).rounded())
    }

    var criticalPercent: Int? {
        let values = snapshots.flatMap { snapshot in
            snapshot.accounts.flatMap { account in
                account.metrics.compactMap { metric -> Double? in
                    guard let progress = metric.progress else { return nil }
                    return progress
                }
            }
        }
        guard let highest = values.max() else { return nil }
        return Int((highest * 100).rounded())
    }
}
