import Foundation
import SwiftUI

struct CodexStatusQuota {
    /// The five-hour quota is the primary menu-bar number and ring.
    let fiveHourRemaining: Int?
    /// The weekly quota is shown as the five-dot secondary indicator.
    let weeklyRemaining: Int?

    var primaryRemaining: Int {
        fiveHourRemaining ?? weeklyRemaining ?? 0
    }

    var primaryWindow: UsageWindow {
        fiveHourRemaining == nil ? .weekly : .fiveHours
    }
}

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

        // Pricing files can be updated while the app is running. Refresh the
        // shared pricing catalog before providers start concurrently so every
        // local adapter uses the same price version for this pass.
        CodexPricing.refresh()

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
                    snapshots[index] = UsageSnapshotCache.cachedFallback(previous)
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

    /// Keep both Codex quota windows available to the menu bar. The five-hour
    /// quota is the primary number/ring, while the weekly quota is the
    /// secondary five-dot indicator. Plans without a five-hour bucket still
    /// fall back to their weekly quota instead of going blank.
    var codexStatusQuota: CodexStatusQuota? {
        let fiveHourRemaining = codexRemainingPercent(for: .fiveHours)
        let weeklyRemaining = codexRemainingPercent(for: .weekly)
        guard fiveHourRemaining != nil || weeklyRemaining != nil else { return nil }

        return CodexStatusQuota(
            fiveHourRemaining: fiveHourRemaining,
            weeklyRemaining: weeklyRemaining
        )
    }

    private func codexRemainingPercent(for window: UsageWindow) -> Int? {
        guard let remaining = codexAccounts
            .compactMap({ quotaMetric(in: $0, window: window)?.remaining })
            .first(where: { $0.isFinite }) else {
            return nil
        }
        return roundedRemainingPercent(remaining)
    }

    private var codexAccounts: [AccountUsageSnapshot] {
        snapshots.first(where: { $0.provider == .codex })?.accounts ?? []
    }

    private func quotaMetric(in account: AccountUsageSnapshot, window: UsageWindow) -> UsageMetric? {
        account.metrics.first { metric in
            metric.kind == .quota && metric.window == window
        }
    }

    private func roundedRemainingPercent(_ remaining: Double) -> Int {
        Int(min(max(remaining, 0), 100).rounded())
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
