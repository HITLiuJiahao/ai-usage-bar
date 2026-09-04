import AppKit
import SwiftUI

private enum DashboardPeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear

    var id: String { rawValue }

    var title: String {
        L10n.periodTitle(rawValue)
    }

    var preferredWindows: [UsageWindow] {
        switch self {
        case .today: return [.today, .fiveHours, .daily]
        case .yesterday: return [.yesterday]
        case .thisWeek: return [.weekly]
        case .lastWeek: return [.lastWeek]
        case .thisMonth: return [.monthly, .billing]
        case .lastMonth: return [.lastMonth]
        case .thisYear: return [.yearly]
        }
    }

    var isLongRange: Bool {
        switch self {
        case .lastWeek, .lastMonth, .thisYear:
            return true
        case .today, .yesterday, .thisWeek, .thisMonth:
            return false
        }
    }

    func hasUsage(in account: AccountUsageSnapshot) -> Bool {
        account.metrics
            .filter { preferredWindows.contains($0.window) }
            .contains(where: \.hasActualUsage)
            || account.modelUsages.contains {
                preferredWindows.contains($0.window) && $0.hasUsage
            }
    }
}

private enum DashboardMotion {
    static let periodSelection = Animation.spring(
        response: 0.34,
        dampingFraction: 0.88,
        blendDuration: 0.05
    )

    static let periodContent = Animation.spring(
        response: 0.42,
        dampingFraction: 0.90,
        blendDuration: 0.05
    )

    static let longRangeContent = Animation.easeInOut(duration: 0.30)
}

enum DashboardLayout {
    static let referenceWidth: CGFloat = 1120
    // Return to the original desktop canvas. Keep the SwiftUI layout width
    // identical to the panel width so the rendered content and AppKit window
    // never disagree about their coordinate space.
    static let width: CGFloat = referenceWidth
    static let scale: CGFloat = 1
    // Keep the overview compact when more providers have activity in the
    // selected period. Additional cards remain in the scrollable grid.
    static let maximumVisibleModuleCount = 6
    // The balance row is part of the collapsed card, so the minimum card
    // height needs a little extra room beyond the token-only layout. Cards
    // can still grow naturally when a provider has more quota rows or model
    // details.
    static let cardHeight: CGFloat = 220
    static let gridSpacing: CGFloat = 12
    static let maximumPanelHeight: CGFloat = 900
    static let screenVerticalInset: CGFloat = 24

    private static let outerPadding: CGFloat = 16 * 2
    private static let headerHeight: CGFloat = 48
    private static let periodSelectorHeight: CGFloat = 50
    private static let stackSpacing: CGFloat = 10 * 3

    static func chromeHeight(footerHeight: CGFloat = 40) -> CGFloat {
        outerPadding
            + headerHeight
            + periodSelectorHeight
            + footerHeight
            + stackSpacing
    }

    static func maximumHeight(for visibleFrame: CGRect? = nil) -> CGFloat {
        let screenHeight = visibleFrame?.height
            ?? NSScreen.main?.visibleFrame.height
            ?? maximumPanelHeight
        return min(
            maximumPanelHeight,
            max(1, screenHeight - screenVerticalInset)
        )
    }

    // Cards are arranged as two natural-height columns. This avoids making a
    // short card as tall as a neighboring quota-heavy card while preserving
    // the original row-major provider order (even indexes on the left,
    // odd indexes on the right).
    static func gridHeight(forModuleCount count: Int, cardHeights: [CGFloat] = []) -> CGFloat {
        let normalizedCount = max(count, 0)
        guard normalizedCount > 0 else { return cardHeight }

        var columnHeights = [CGFloat.zero, CGFloat.zero]
        for index in 0..<normalizedCount {
            let measuredHeight = index < cardHeights.count
                ? cardHeights[index]
                : cardHeight
            let height = max(cardHeight, measuredHeight)
            let column = index % 2
            if columnHeights[column] > 0 {
                columnHeights[column] += gridSpacing
            }
            columnHeights[column] += height
        }
        return max(columnHeights[0], columnHeights[1])
    }

    static func contentHeight(
        forModuleCount count: Int,
        cardHeights: [CGFloat] = [],
        footerHeight: CGFloat = 40
    ) -> CGFloat {
        let gridHeight = gridHeight(forModuleCount: count, cardHeights: cardHeights)
        return chromeHeight(footerHeight: footerHeight) + gridHeight
    }

    static func height(forModuleCount count: Int, cardHeights: [CGFloat] = []) -> CGFloat {
        contentHeight(forModuleCount: count, cardHeights: cardHeights) * scale
    }

    static func fittingScale(
        forContentHeight contentHeight: CGFloat,
        visibleFrame suppliedVisibleFrame: CGRect? = nil
    ) -> CGFloat {
        _ = suppliedVisibleFrame
        _ = contentHeight
        return scale
    }

    static func fittingSize(
        forModuleCount count: Int,
        cardHeights: [CGFloat] = [],
        visibleFrame: CGRect? = nil
    ) -> CGSize {
        let contentHeight = contentHeight(forModuleCount: count, cardHeights: cardHeights)
        return CGSize(
            width: width,
            height: min(contentHeight, maximumHeight(for: visibleFrame))
        )
    }
}

private struct DashboardCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct DashboardPopover: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var providerOrder = ProviderOrderStore.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    private let visibleFrame: CGRect?
    let onSizeChange: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: DashboardPeriod = .today
    @State private var periodTransitionIsLongRange = false
    @State private var measuredCardHeights: [String: CGFloat] = [:]
    @Namespace private var periodSelectionNamespace

    init(
        store: UsageStore,
        visibleFrame: CGRect? = nil,
        onSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.store = store
        self.visibleFrame = visibleFrame
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DashboardPalette.background
                .ignoresSafeArea()
            RadialGradient(
                colors: [
                    DashboardPalette.accent.opacity(0.18),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 420
            )
            .blur(radius: 12)
            .ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(red: 0.38, green: 0.92, blue: 0.82).opacity(0.12),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 360
            )
            .blur(radius: 18)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                dashboardHeader
                periodSelector

                ScrollViewReader { proxy in
                    ScrollView(
                        .vertical,
                        showsIndicators: dashboardGridContentHeight > dashboardGridViewportHeight + 0.5
                    ) {
                        dashboardGrid
                            .id("dashboard-grid-top")
                    }
                    .frame(height: dashboardGridViewportHeight, alignment: .top)
                    .onChange(of: period) { _ in
                        DispatchQueue.main.async {
                            if reduceMotion {
                                proxy.scrollTo("dashboard-grid-top", anchor: .top)
                            } else {
                                withAnimation(DashboardMotion.periodSelection) {
                                    proxy.scrollTo("dashboard-grid-top", anchor: .top)
                                }
                            }
                        }
                    }
                }

                dashboardFooter
                    .frame(height: dashboardFooterHeight, alignment: .top)
            }
            .padding(16)
            .frame(
                width: DashboardLayout.referenceWidth,
                height: dashboardContentHeight,
                alignment: .topLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .preferredColorScheme(.dark)
        .frame(width: dashboardWidth, height: dashboardHeight)
        .onAppear {
            reportDashboardSize()
        }
        .onChange(of: visibleSnapshots.count) { _ in
            reportDashboardSize()
        }
        .onChange(of: period) { _ in
            reportDashboardSize()
        }
        .onPreferenceChange(DashboardCardHeightPreferenceKey.self) { heights in
            updateMeasuredCardHeights(heights)
        }
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        return providerOrder.orderedSnapshots(store.snapshots).filter { snapshot in
            snapshot.accounts.contains { period.hasUsage(in: $0) }
        }
    }

    private var dashboardScale: CGFloat {
        DashboardLayout.scale
    }

    private var dashboardWidth: CGFloat {
        DashboardLayout.width
    }

    private var dashboardHeight: CGFloat {
        dashboardContentHeight * dashboardScale
    }

    private var dashboardMaximumHeight: CGFloat {
        DashboardLayout.maximumHeight(for: visibleFrame)
    }

    private var dashboardFooterHeight: CGFloat {
        hiddenProviderNames.isEmpty ? 24 : 46
    }

    private var dashboardGridContentHeight: CGFloat {
        let cardHeights = visibleSnapshots.map {
            measuredCardHeights[$0.id] ?? DashboardLayout.cardHeight
        }
        return DashboardLayout.gridHeight(
            forModuleCount: visibleSnapshots.count,
            cardHeights: cardHeights
        )
    }

    private var dashboardContentHeight: CGFloat {
        DashboardLayout.chromeHeight(footerHeight: dashboardFooterHeight)
            + dashboardGridViewportHeight
    }

    private var dashboardGridViewportHeight: CGFloat {
        let visibleCardSnapshots = Array(
            visibleSnapshots.prefix(DashboardLayout.maximumVisibleModuleCount)
        )
        let cardHeights = visibleCardSnapshots.map {
            measuredCardHeights[$0.id] ?? DashboardLayout.cardHeight
        }
        let naturalViewportHeight = DashboardLayout.gridHeight(
            forModuleCount: visibleCardSnapshots.count,
            cardHeights: cardHeights
        )
        let availableHeight = dashboardMaximumHeight
            - DashboardLayout.chromeHeight(footerHeight: dashboardFooterHeight)
        return min(naturalViewportHeight, max(1, availableHeight))
    }

    private var dashboardGrid: some View {
        HStack(alignment: .top, spacing: DashboardLayout.gridSpacing) {
            dashboardColumn(leftColumnSnapshots)
            dashboardColumn(rightColumnSnapshots)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(
            reduceMotion
                ? nil
                : (periodTransitionIsLongRange
                    ? DashboardMotion.longRangeContent
                    : DashboardMotion.periodContent),
            value: period
        )
    }

    private var leftColumnSnapshots: [ProviderSnapshot] {
        visibleSnapshots.enumerated().compactMap { index, snapshot in
            index.isMultiple(of: 2) ? snapshot : nil
        }
    }

    private var rightColumnSnapshots: [ProviderSnapshot] {
        visibleSnapshots.enumerated().compactMap { index, snapshot in
            index.isMultiple(of: 2) ? nil : snapshot
        }
    }

    private func dashboardColumn(_ snapshots: [ProviderSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: DashboardLayout.gridSpacing) {
            ForEach(snapshots) { snapshot in
                dashboardCard(snapshot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func dashboardCard(_ snapshot: ProviderSnapshot) -> some View {
        DashboardProviderCard(snapshot: snapshot, period: period)
            .frame(maxWidth: .infinity, minHeight: DashboardLayout.cardHeight, alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DashboardCardHeightPreferenceKey.self,
                        value: [snapshot.id: proxy.size.height]
                    )
                }
            )
            .transition(providerCardTransition)
    }

    private func reportDashboardSize() {
        let size = CGSize(width: dashboardWidth, height: dashboardHeight)
        DispatchQueue.main.async {
            onSizeChange(size)
        }
    }

    private func updateMeasuredCardHeights(_ heights: [String: CGFloat]) {
        let visibleIDs = Set(visibleSnapshots.map(\.id))
        var normalized: [String: CGFloat] = [:]
        for (id, height) in heights where visibleIDs.contains(id) {
            normalized[id] = (height * 2).rounded() / 2
        }

        guard normalized != measuredCardHeights else { return }
        measuredCardHeights = normalized
        reportDashboardSize()
    }

    private var hiddenProviderNames: [String] {
        guard store.lastRefreshAt != nil else { return [] }
        return providerOrder.orderedSnapshots(store.snapshots)
            .filter { snapshot in
                !snapshot.accounts.contains { period.hasUsage(in: $0) }
            }
            .map { $0.provider.displayName }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(DashboardPalette.accent.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "gauge.medium")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(DashboardPalette.accent)
            }
            .frame(width: 48, height: 48)
            .aiLiquidGlass(
                tint: DashboardPalette.accent.opacity(0.18),
                in: Circle(),
                interactive: true
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 9) {
                    Text("AI Usage Bar")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    DashboardRefreshButton(store: store)
                    DashboardUpdatePrompt()
                }
                Text(L10n.text(.overviewSubtitle, language: languageSettings.language))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let lastRefreshAt = store.lastRefreshAt {
                    Text("\(L10n.text(.updated, language: languageSettings.language)) \(lastRefreshAt, format: .dateTime.hour().minute().second())")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                Text(L10n.text(.reading, language: languageSettings.language))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text(
                    L10n.text(
                        store.connectedCount > 0 ? .localDataConnected : .waitingForData,
                        language: languageSettings.language
                    )
                )
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
            }

            DashboardIconButton(
                symbol: "gearshape",
                help: L10n.text(.accountSettings, language: languageSettings.language)
            ) {
                SettingsWindowController.shared.show()
            }
        }
    }

    private var periodSelector: some View {
        HStack(spacing: 3) {
            ForEach(DashboardPeriod.allCases) { value in
                Button {
                    guard period != value else { return }
                    let isLongRangeTransition = period.isLongRange || value.isLongRange
                    if reduceMotion {
                        periodTransitionIsLongRange = false
                        period = value
                    } else {
                        withAnimation(DashboardMotion.periodSelection) {
                            periodTransitionIsLongRange = isLongRangeTransition
                            period = value
                        }
                    }
                } label: {
                    Text(value.title)
                        .font(.system(size: 15, weight: period == value ? .semibold : .medium))
                        .foregroundStyle(period == value ? .white : .white.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if period == value {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.white.opacity(0.13))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(
                                        id: "period-selection",
                                        in: periodSelectionNamespace
                                    )
                            }
                        }
                        .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(5)
        .aiLiquidGlass(
            tint: Color.white.opacity(0.10),
            cornerRadius: 16,
            interactive: true
        )
    }

    private var providerCardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        if periodTransitionIsLongRange {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .center)),
            removal: .opacity
        )
    }

    private var dashboardFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(DashboardPalette.success)
                    .frame(width: 6, height: 6)
                Text(L10n.text(.refreshEvery30Seconds, language: languageSettings.language))
                Text("·")
                    .foregroundStyle(.white.opacity(0.22))
                Text(L10n.text(.sourceFootnote, language: languageSettings.language))
                Spacer()
                Text(
                    L10n.text(
                        store.isRefreshing
                            ? .updating
                            : (store.refreshError == nil ? .localFirst : .retryLater),
                        language: languageSettings.language
                    )
                )
                    .foregroundStyle(.white.opacity(0.45))
            }

            if !hiddenProviderNames.isEmpty {
                Text(
                    "\(L10n.text(.noUsageInPeriod, language: languageSettings.language))：\(hiddenProviderNames.joined(separator: " · "))"
                )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(2)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.48))
    }
}

private struct BalancePresentation: Identifiable {
    let metric: UsageMetric
    let title: String
    let valueText: String
    let percentText: String?
    let remainingFraction: Double?
    let resetAt: Date?
    let planName: String?

    var id: String { metric.id }
}

private struct DashboardProviderCard: View {
    let snapshot: ProviderSnapshot
    let period: DashboardPeriod
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @State private var isModelExpanded = false

    private var account: AccountUsageSnapshot {
        snapshot.accounts.first(where: { account in
            period.hasUsage(in: account)
        }) ?? snapshot.accounts.first(where: { account in
            account.metrics.contains { period.preferredWindows.contains($0.window) }
        }) ?? snapshot.accounts.first(where: { !$0.metrics.isEmpty }) ?? snapshot.accounts[0]
    }

    private var periodMetrics: [UsageMetric] {
        account.metrics.filter { period.preferredWindows.contains($0.window) }
    }

    private var balanceMetrics: [UsageMetric] {
        let candidates = account.metrics.filter { $0.kind == .quota }
        let preferredWindows: [UsageWindow]
        switch snapshot.provider {
        case .codex:
            // Codex has two independent subscription windows. Keep both
            // visible so the restored five-hour allowance is not hidden by
            // the weekly window.
            preferredWindows = [.fiveHours, .weekly, .billing]
        case .kimi:
            // KIMI Desktop exposes Kimi Code's independent rate limits along
            // with the monthly shared membership Credits balance.
            preferredWindows = [.fiveHours, .weekly, .monthly, .billing]
        case .miniMax, .chatGPT, .zcode, .openCode, .doubaoWork:
            preferredWindows = [.weekly, .fiveHours, .billing]
        case .workBuddy:
            preferredWindows = [.monthly, .billing, .weekly]
        case .qwenWork:
            preferredWindows = [.billing, .monthly, .weekly]
        case .qianwenOffice:
            preferredWindows = [.billing, .monthly, .weekly]
        case .deepSeekHarness:
            preferredWindows = [.billing, .monthly, .weekly]
        }

        var selected: [UsageMetric] = []
        for window in preferredWindows {
            let matches = candidates
                .filter { $0.window == window }
                .sorted { lhs, rhs in
                    // Prefer an aggregate quota over a model-specific row.
                    let lhsAggregate = !lhs.title.contains("·")
                    let rhsAggregate = !rhs.title.contains("·")
                    if lhsAggregate != rhsAggregate { return lhsAggregate }
                    return lhs.key < rhs.key
                }
            if snapshot.provider == .codex || snapshot.provider == .kimi {
                selected.append(contentsOf: matches.filter { candidate in
                    !selected.contains(where: { $0.id == candidate.id })
                })
            } else if let match = matches.first {
                return [match]
            }
        }
        return selected.isEmpty ? candidates.first.map { [$0] } ?? [] : selected
    }

    private var balancePresentations: [BalancePresentation] {
        balanceMetrics.map(balancePresentation(for:))
    }

    private var resetCreditsAvailableCount: Int? {
        guard snapshot.provider == .codex,
              let count = account.resetCreditsAvailableCount,
              count > 0 else {
            return nil
        }
        return count
    }

    private var resetCreditsExpiresAt: Date? {
        guard resetCreditsAvailableCount != nil else { return nil }
        return account.resetCreditsExpiresAt
    }

    private func balancePresentation(for metric: UsageMetric) -> BalancePresentation {
        let remainingFraction: Double?
        if let remaining = metric.remaining, let limit = metric.limit, limit > 0 {
            remainingFraction = min(max(remaining / limit, 0), 1)
        } else if let used = metric.used, let limit = metric.limit, limit > 0 {
            remainingFraction = min(max(1 - used / limit, 0), 1)
        } else {
            remainingFraction = nil
        }

        let percentText = remainingFraction.map { "\(Int(($0 * 100).rounded()))%" }
        let valueText: String
        if metric.unit == "%", let remaining = metric.remaining {
            valueText = "\(NumberFormat.compact(remaining))%"
        } else if let remaining = metric.remaining {
            valueText = "\(NumberFormat.compact(remaining)) \(L10n.localizedUnit(metric.unit, language: languageSettings.language))"
        } else {
            valueText = "—"
        }

        return BalancePresentation(
            metric: metric,
            title: balanceTitle(for: metric),
            valueText: valueText,
            percentText: percentText,
            remainingFraction: remainingFraction,
            resetAt: metric.resetAt,
            planName: account.planName ?? planName(from: metric)
        )
    }

    private func balanceTitle(for metric: UsageMetric) -> String {
        L10n.balanceTitle(for: metric, language: languageSettings.language)
    }

    private func planName(from metric: UsageMetric) -> String? {
        guard let note = metric.note,
              let range = note.range(of: "套餐：") else { return nil }
        let value = note[range.upperBound...]
            .split(separator: "·", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private var modelUsages: [ModelUsage] {
        account.modelUsages
            .filter { period.preferredWindows.contains($0.window) }
            .filter(\.hasUsage)
            .sorted { lhs, rhs in
                let lhsValue = max(lhs.tokens.total, max(lhs.requests, max(lhs.credits, lhs.cost)))
                let rhsValue = max(rhs.tokens.total, max(rhs.requests, max(rhs.credits, rhs.cost)))
                if lhsValue == rhsValue { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
                return lhsValue > rhsValue
            }
    }

    private var primaryMetric: UsageMetric? {
        if snapshot.provider == .kimi {
            // KIMI's quota rows are supplementary account information. Keep
            // the headline aligned with the other activity cards by showing
            // local usage for the selected period instead of a quota balance.
            if let localTokens = metric(kind: .tokens) {
                return localTokens
            }
            if let localRequests = metric(kind: .requests) {
                return localRequests
            }
            return UsageMetric(
                key: "kimi-primary-total",
                title: "Token",
                kind: .tokens,
                window: period.preferredWindows.first ?? .today,
                used: 0,
                limit: nil,
                remaining: nil,
                unit: "tokens",
                source: .local,
                resetAt: nil,
                note: "所选时间范围暂无本地用量"
            )
        }
        return metric(kind: .tokens) ?? metric(kind: .quota) ?? metric(kind: .credits) ?? metric(kind: .requests)
    }

    private var requestMetric: UsageMetric? {
        metric(kind: .requests)
    }

    private var quotaMetric: UsageMetric? {
        metric(kind: .quota)
    }

    private var subscriptionQuotaMetric: UsageMetric? {
        if let quotaMetric {
            return quotaMetric
        }
        // Account-level subscription quotas are not tied to 今日/昨日/etc.
        // Keep them available as a secondary card stat when the selected
        // period is showing local activity from the same account.
        return account.metrics.first {
            $0.kind == .quota && $0.source == .server
        }
    }

    private var inputTokens: Double? {
        periodMetrics.compactMap(\.inputTokens).max()
    }

    private var outputTokens: Double? {
        periodMetrics.compactMap(\.outputTokens).max()
    }

    private var cacheReadTokens: Double? {
        periodMetrics.compactMap(\.cacheReadTokens).max()
    }

    private var cacheWriteTokens: Double? {
        periodMetrics.compactMap(\.cacheWriteTokens).max()
    }

    private var cacheHitRate: Double? {
        guard let inputTokens, let cacheReadTokens else { return nil }
        let inputIncludesCache = periodMetrics.contains { $0.inputIncludesCache }
        let denominator = inputIncludesCache
            ? inputTokens
            : inputTokens + cacheReadTokens + (cacheWriteTokens ?? 0)
        guard denominator > 0 else { return nil }
        return min(
            max(cacheReadTokens / denominator, 0),
            1
        )
    }

    private var costEstimate: Double? {
        if let reportedCost = metric(kind: .money)?.used, reportedCost > 0 {
            return reportedCost
        }
        let modelCost = modelUsages.reduce(0) { $0 + $1.cost }
        return modelCost > 0 ? modelCost : nil
    }

    private var costUnit: String {
        snapshot.provider == .deepSeekHarness || snapshot.provider == .kimi ? "CNY" : "USD"
    }

    private var stats: [DashboardStat] {
        [
            DashboardStat(
                symbol: costUnit == "CNY" ? "yensign" : "dollarsign",
                title: L10n.text(.estimatedCost, language: languageSettings.language),
                value: costEstimate.map { NumberFormat.currency($0, unit: costUnit) } ?? "—"
            ),
            DashboardStat(
                symbol: "circle",
                title: L10n.text(.cacheHit, language: languageSettings.language),
                value: cacheHitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                usesCacheHitIcon: true,
                progress: cacheHitRate
            ),
            DashboardStat(
                symbol: "arrow.down",
                title: L10n.text(.input, language: languageSettings.language),
                value: inputTokens.map(NumberFormat.compact) ?? "—"
            ),
            DashboardStat(
                symbol: "arrow.up",
                title: L10n.text(.output, language: languageSettings.language),
                value: outputTokens.map(NumberFormat.compact) ?? "—"
            )
        ]
    }

    @ViewBuilder
    private var balanceSection: some View {
        if !balancePresentations.isEmpty || resetCreditsAvailableCount != nil {
            VStack(alignment: .leading, spacing: 3) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)

                ForEach(balancePresentations) { balance in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            if balance.metric.unit.localizedCaseInsensitiveContains("credit") {
                                Group {
                                    if snapshot.provider == .workBuddy {
                                        WorkBuddyCreditsIcon(
                                            size: 22,
                                            color: DashboardPalette.color(for: snapshot.provider)
                                        )
                                    } else {
                                        UsageMetricIconBadge(
                                            symbol: "dollarsign",
                                            size: 22,
                                            color: DashboardPalette.color(for: snapshot.provider)
                                        )
                                    }
                                }
                                .frame(width: 22, height: 22)
                            }
                            Text(balance.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.68))
                            Spacer(minLength: 4)
                            Text(balance.valueText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                            if let percentText = balance.percentText, balance.metric.unit != "%" {
                                Text(percentText)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(DashboardPalette.color(for: snapshot.provider))
                            }
                            if let resetAt = balance.resetAt {
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.28))
                                Text(resetAt, formatter: Self.balanceDateFormatter)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }

                        if let remainingFraction = balance.remainingFraction {
                            ProgressView(value: remainingFraction, total: 1)
                                .progressViewStyle(.linear)
                                .tint(DashboardPalette.color(for: snapshot.provider))
                                .scaleEffect(x: 1, y: 0.72, anchor: .center)
                        }
                    }
                }

                if let resetCreditsAvailableCount {
                    HStack(spacing: 8) {
                        ResetCreditIcon(
                            size: 22,
                            color: DashboardPalette.color(for: snapshot.provider)
                        )
                        Text(
                            L10n.resetCreditsAvailableText(
                                count: resetCreditsAvailableCount,
                                language: languageSettings.language
                            )
                        )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                        Spacer(minLength: 4)
                        if let resetCreditsExpiresAt {
                            HStack(spacing: 4) {
                                Text(L10n.text(.resetCreditsExpiresAt, language: languageSettings.language))
                                Text(resetCreditsExpiresAt, formatter: Self.balanceDateFormatter)
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        }
                    }
                    .padding(.top, 2)
                }

                HStack {
                    Text(L10n.text(.plan, language: languageSettings.language))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                    Spacer(minLength: 4)
                    Text(balancePresentations.first?.planName ?? "—")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            DashboardPalette.color(for: snapshot.provider).opacity(0.18),
                            in: Capsule()
                        )
                }
            }
            .padding(.top, 2)
        }
    }

    private static let balanceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Spacer(minLength: 2)
            primaryValue
            Spacer(minLength: 2)
            statGrid
            Spacer(minLength: 2)
            modelSection
            balanceSection
        }
        .padding(11)
        .aiLiquidGlass(
            tint: DashboardPalette.color(for: snapshot.provider).opacity(0.18),
            cornerRadius: 20
        )
    }

    private var cardHeader: some View {
        HStack(spacing: 9) {
            ProviderLogo(
                provider: snapshot.provider,
                size: 25,
                fallbackColor: DashboardPalette.color(for: snapshot.provider)
            )
            Text(L10n.providerName(snapshot.provider, language: languageSettings.language))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(badgeText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardPalette.color(for: snapshot.provider))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(DashboardPalette.color(for: snapshot.provider).opacity(0.16), in: Capsule())
            Spacer(minLength: 4)
            Image(systemName: statusSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .help(statusHelp)
        }
    }

    private var primaryValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let primaryMetric {
                Text(primaryValueText(primaryMetric))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                Text(primaryLabel(primaryMetric))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .contentTransition(.opacity)
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text(L10n.text(.waitingForData, language: languageSettings.language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(stats) { stat in
                DashboardStatView(stat: stat, accent: DashboardPalette.color(for: snapshot.provider))
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isModelExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DashboardPalette.color(for: snapshot.provider))
                    Text("\(L10n.text(.byModel, language: languageSettings.language)) (\(modelUsages.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer(minLength: 4)
                    Image(systemName: isModelExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isModelExpanded {
                if modelUsages.isEmpty {
                    Text(L10n.text(.noModelDetails, language: languageSettings.language))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.40))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(modelUsages) { usage in
                            ModelUsageRow(
                                usage: usage,
                                accent: DashboardPalette.color(for: snapshot.provider),
                                currencyUnit: costUnit
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
    }

    private var badgeText: String {
        if let requests = requestMetric?.used {
            let unit = requestMetric?.title.contains("会话") == true
                ? L10n.text(.sessions, language: languageSettings.language)
                : L10n.text(.requests, language: languageSettings.language)
            return "\(NumberFormat.compact(requests)) \(unit)"
        }
        if snapshot.accounts.count > 1 {
            return "\(snapshot.accounts.count) \(L10n.text(.accountUnit, language: languageSettings.language))"
        }
        switch snapshot.state {
        case .connected: return "OK"
        case .cached: return L10n.text(.historical, language: languageSettings.language)
        case .partial, .unavailable: return "—"
        }
    }

    private var statusSymbol: String {
        switch snapshot.state {
        case .connected: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .cached: return "clock.fill"
        case .unavailable: return "minus.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .connected: return DashboardPalette.success
        case .partial: return DashboardPalette.warning
        case .cached: return .purple
        case .unavailable: return .white.opacity(0.32)
        }
    }

    private var statusHelp: String {
        if let message = account.message, !message.isEmpty {
            return message
        }
        switch snapshot.state {
        case .connected: return L10n.text(.dataRead, language: languageSettings.language)
        case .partial: return L10n.text(.partialData, language: languageSettings.language)
        case .cached: return L10n.text(.cachedHistory, language: languageSettings.language)
        case .unavailable: return L10n.text(.noData, language: languageSettings.language)
        }
    }

    private func metric(kind: MetricKind) -> UsageMetric? {
        for window in period.preferredWindows {
            if let value = account.metrics.first(where: { $0.kind == kind && $0.window == window }) {
                return value
            }
        }
        return nil
    }

    private func primaryValueText(_ metric: UsageMetric) -> String {
        if metric.kind == .quota, let remaining = metric.remaining {
            if metric.unit == "%" {
                return "\(NumberFormat.compact(remaining))%"
            }
            return NumberFormat.compact(remaining)
        }
        if let used = metric.used {
            if metric.kind == .money { return NumberFormat.currency(used, unit: metric.unit) }
            return NumberFormat.compact(used)
        }
        if let remaining = metric.remaining {
            return NumberFormat.compact(remaining)
        }
        return "—"
    }

    private func primaryLabel(_ metric: UsageMetric) -> String {
        L10n.primaryLabel(
            periodRawValue: period.rawValue,
            kind: metric.kind,
            language: languageSettings.language
        )
    }

}

private struct DashboardStat: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let value: String
    let usesCacheHitIcon: Bool
    let progress: Double?

    init(
        symbol: String,
        title: String,
        value: String,
        usesCacheHitIcon: Bool = false,
        progress: Double? = nil
    ) {
        self.id = title
        self.symbol = symbol
        self.title = title
        self.value = value
        self.usesCacheHitIcon = usesCacheHitIcon
        self.progress = progress
    }
}

private struct DashboardStatView: View {
    let stat: DashboardStat
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            if stat.usesCacheHitIcon {
                CacheHitIcon(accent: accent, progress: stat.progress ?? 0)
                    .frame(width: 26, height: 26)
            } else {
                UsageMetricIconBadge(
                    symbol: stat.symbol,
                    size: 26,
                    color: accent
                )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                Text(stat.value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.opacity)
            }
        }
    }
}

private struct CacheHitIcon: View {
    let accent: Color
    let progress: Double

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 3)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            accent.opacity(0.78),
                            accent,
                            accent.opacity(0.48),
                            accent.opacity(0.78)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: clampedProgress >= 0.999 ? .butt : .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 21, height: 21)
        .shadow(color: accent.opacity(0.16), radius: 2)
    }
}

private struct ModelUsageRow: View {
    let usage: ModelUsage
    let accent: Color
    let currencyUnit: String
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    private var primaryValue: String {
        if usage.tokens.total > 0 { return NumberFormat.compact(usage.tokens.total) }
        if usage.requests > 0 {
            return "\(NumberFormat.compact(usage.requests)) \(L10n.text(.requestUnit, language: languageSettings.language))"
        }
        if usage.credits > 0 { return NumberFormat.compact(usage.credits) }
        if usage.cost > 0 { return NumberFormat.currency(usage.cost, unit: currencyUnit) }
        return "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
                Circle()
                    .fill(accent.opacity(0.85))
                    .frame(width: 7, height: 7)
                Text(usage.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(primaryValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                if let hitRate = usage.hitRate {
                    Text("\(Int((hitRate * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                if usage.cost > 0 {
                    Text(NumberFormat.currency(usage.cost, unit: currencyUnit))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 5) {
                if usage.tokens.input > 0 {
                    ModelDetailChip(
                        title: "\(L10n.text(.input, language: languageSettings.language)) ↓",
                        value: NumberFormat.compact(usage.tokens.input),
                        accent: accent
                    )
                }
                if usage.tokens.output > 0 {
                    ModelDetailChip(
                        title: "\(L10n.text(.output, language: languageSettings.language)) ↑",
                        value: NumberFormat.compact(usage.tokens.output),
                        accent: accent
                    )
                }
                if usage.tokens.cacheRead > 0 {
                    ModelDetailChip(
                        title: "\(L10n.text(.cacheRead, language: languageSettings.language)) ⚡",
                        value: NumberFormat.compact(usage.tokens.cacheRead),
                        accent: accent
                    )
                }
                if usage.tokens.cacheWrite > 0 {
                    ModelDetailChip(
                        title: L10n.text(.cacheWrite, language: languageSettings.language),
                        value: NumberFormat.compact(usage.tokens.cacheWrite),
                        accent: accent
                    )
                }
                if usage.tokens.reasoning > 0 {
                    ModelDetailChip(
                        title: "\(L10n.text(.reasoning, language: languageSettings.language)) 🧠",
                        value: NumberFormat.compact(usage.tokens.reasoning),
                        accent: accent
                    )
                }
                if usage.hitRate == nil, usage.requests > 0 {
                    ModelDetailChip(
                        title: L10n.text(.requests, language: languageSettings.language),
                        value: "\(NumberFormat.compact(usage.requests)) \(L10n.text(.requestUnit, language: languageSettings.language))",
                        accent: accent
                    )
                }
                if usage.credits > 0 {
                    ModelDetailChip(
                        title: L10n.text(.credits, language: languageSettings.language),
                        value: NumberFormat.compact(usage.credits),
                        accent: accent
                    )
                }
            }
            .lineLimit(1)
        }
    }
}

private struct ModelDetailChip: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(value)
                .fontWeight(.bold)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.70))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(accent.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.8))
    }
}

private struct DashboardIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40, height: 40)
                .aiLiquidGlass(
                    tint: Color.white.opacity(0.12),
                    in: Circle(),
                    interactive: true
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DashboardRefreshButton: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    private var accent: Color {
        store.refreshError == nil ? DashboardPalette.accent : DashboardPalette.warning
    }

    private var title: String {
        if store.isRefreshing { return L10n.text(.syncing, language: languageSettings.language) }
        if store.refreshError != nil { return L10n.text(.retry, language: languageSettings.language) }
        return L10n.text(.update, language: languageSettings.language)
    }

    var body: some View {
        Button {
            store.refresh(forceQuota: true)
        } label: {
            HStack(spacing: 6) {
                refreshGlyph

                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: true, vertical: false)
                    .id(title)
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
            .padding(.horizontal, 10)
            .frame(width: 92, height: 29)
            .contentShape(Capsule())
            .aiLiquidGlass(
                tint: accent.opacity(store.isRefreshing ? 0.24 : 0.12),
                cornerRadius: 15,
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .help(L10n.text(.immediateUpdate, language: languageSettings.language))
        .animation(.easeInOut(duration: 0.22), value: title)
    }

    @ViewBuilder
    private var refreshGlyph: some View {
        if store.isRefreshing {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                refreshGlyph(rotation: context.date.timeIntervalSinceReferenceDate * 180)
            }
        } else {
            refreshGlyph(rotation: 0)
        }
    }

    private func refreshGlyph(rotation: Double) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.12))
            Circle()
                .stroke(accent.opacity(0.28), lineWidth: 1)
            Circle()
                .trim(from: 0.06, to: 0.32)
                .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(rotation - 90))
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .rotationEffect(.degrees(store.isRefreshing ? rotation : 0))
        }
        .frame(width: 18, height: 18)
        .shadow(color: accent.opacity(store.isRefreshing ? 0.34 : 0.12), radius: store.isRefreshing ? 4 : 1)
    }
}

private struct DashboardUpdatePrompt: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    @ViewBuilder
    var body: some View {
        switch updater.state {
        case .available(let release):
            Button {
                updater.installUpdate()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(L10n.text(.update, language: languageSettings.language))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 10)
                .frame(height: 29)
                .contentShape(Capsule())
                .aiLiquidGlass(
                    tint: DashboardPalette.success.opacity(0.24),
                    cornerRadius: 15,
                    interactive: true
                )
            }
            .buttonStyle(.plain)
            .help(
                "\(L10n.text(.updateAvailable, language: languageSettings.language)) \(release.tag)"
            )
        case .downloading(let progress):
            updateProgress(
                text: L10n.text(.downloadingUpdate, language: languageSettings.language),
                progress: progress
            )
        case .installing:
            updateProgress(
                text: L10n.text(.installingUpdate, language: languageSettings.language),
                progress: nil
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func updateProgress(text: String, progress: Double?) -> some View {
        HStack(spacing: 6) {
            if let progress {
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(
                progress.map { "\(Int(($0 * 100).rounded()))%" } ?? text
            )
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .frame(height: 29)
        .aiLiquidGlass(
            tint: Color.white.opacity(0.10),
            cornerRadius: 15,
            interactive: false
        )
        .help(text)
    }
}

private enum DashboardPalette {
    static let background = LinearGradient(
        colors: [Color(red: 0.10, green: 0.11, blue: 0.16), Color(red: 0.14, green: 0.15, blue: 0.21)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accent = Color(red: 0.42, green: 0.69, blue: 1.0)
    static let success = Color(red: 0.43, green: 0.84, blue: 0.75)
    static let warning = Color(red: 1.0, green: 0.66, blue: 0.30)

    static func color(for provider: ProviderID) -> Color {
        switch provider {
        case .codex: return Color(red: 0.45, green: 0.78, blue: 1.0)
        case .kimi: return Color(red: 0.48, green: 0.62, blue: 1.0)
        case .chatGPT: return Color(red: 0.35, green: 0.82, blue: 0.72)
        case .qwenWork: return Color(red: 0.42, green: 0.69, blue: 1.0)
        case .zcode: return Color(red: 0.34, green: 0.78, blue: 0.92)
        case .openCode: return Color(red: 0.72, green: 0.76, blue: 0.88)
        case .doubaoWork: return Color(red: 0.98, green: 0.47, blue: 0.30)
        case .qianwenOffice: return Color(red: 0.33, green: 0.80, blue: 0.88)
        case .deepSeekHarness: return Color(red: 0.86, green: 0.48, blue: 0.72)
        case .workBuddy: return Color(red: 0.43, green: 0.84, blue: 0.75)
        case .miniMax: return Color(red: 0.72, green: 0.57, blue: 1.0)
        }
    }

}
