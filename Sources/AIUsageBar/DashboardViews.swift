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
        switch self {
        case .today: return "今日"
        case .yesterday: return "昨日"
        case .thisWeek: return "本周"
        case .lastWeek: return "上周"
        case .thisMonth: return "本月"
        case .lastMonth: return "上月"
        case .thisYear: return "本年"
        }
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
}

enum DashboardLayout {
    static let referenceWidth: CGFloat = 1120
    // Return to the original desktop canvas. Keep the SwiftUI layout width
    // identical to the panel width so the rendered content and AppKit window
    // never disagree about their coordinate space.
    static let width: CGFloat = referenceWidth
    static let scale: CGFloat = 1
    // The balance row is part of the collapsed card, so the minimum row
    // height needs a little extra room beyond the token-only layout.
    static let cardHeight: CGFloat = 240
    static let gridSpacing: CGFloat = 12

    // Two provider cards share one row. Keep one row as the minimum so an
    // empty or still-loading dashboard does not collapse into a tiny popover.
    static func contentHeight(forModuleCount count: Int, cardHeights: [CGFloat] = []) -> CGFloat {
        let rowCount = max(1, (max(count, 0) + 1) / 2)
        var gridHeight: CGFloat = 0
        for row in 0..<rowCount {
            let firstIndex = row * 2
            let firstHeight = firstIndex < cardHeights.count ? cardHeights[firstIndex] : cardHeight
            let secondIndex = firstIndex + 1
            let secondHeight = secondIndex < cardHeights.count ? cardHeights[secondIndex] : cardHeight
            gridHeight += max(cardHeight, max(firstHeight, secondHeight))
        }
        gridHeight += CGFloat(max(rowCount - 1, 0)) * gridSpacing
        let outerPadding: CGFloat = 16 * 2
        let headerHeight: CGFloat = 48
        let periodSelectorHeight: CGFloat = 50
        let footerHeight: CGFloat = 40
        let stackSpacing: CGFloat = 10 * 3
        return outerPadding + headerHeight + periodSelectorHeight + footerHeight + stackSpacing + gridHeight
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
        _ = visibleFrame
        return CGSize(width: width, height: contentHeight)
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
    let onSizeChange: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: DashboardPeriod = .today
    @State private var measuredCardHeights: [String: CGFloat] = [:]
    @Namespace private var periodSelectionNamespace

    init(
        store: UsageStore,
        onSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.store = store
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DashboardPalette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                dashboardHeader
                periodSelector

                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: DashboardLayout.gridSpacing, alignment: .leading),
                                GridItem(.flexible(), spacing: DashboardLayout.gridSpacing, alignment: .leading)
                            ],
                            alignment: .leading,
                            spacing: DashboardLayout.gridSpacing
                        ) {
                            ForEach(visibleSnapshots) { snapshot in
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
                        }
                        .animation(
                            reduceMotion ? nil : DashboardMotion.periodContent,
                            value: period
                        )
                    }
                }

            dashboardFooter
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
            measuredCardHeights = [:]
            reportDashboardSize()
        }
        .onChange(of: period) { _ in
            measuredCardHeights = [:]
            reportDashboardSize()
        }
        .onPreferenceChange(DashboardCardHeightPreferenceKey.self) { heights in
            updateMeasuredCardHeights(heights)
        }
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        return store.snapshots.filter { snapshot in
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

    private var dashboardContentHeight: CGFloat {
        let cardHeights = visibleSnapshots.map {
            measuredCardHeights[$0.id] ?? DashboardLayout.cardHeight
        }
        return DashboardLayout.contentHeight(
            forModuleCount: visibleSnapshots.count,
            cardHeights: cardHeights
        )
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
        return store.snapshots
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 9) {
                    Text("AI Usage Bar")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    DashboardRefreshButton(store: store)
                }
                Text("Codex · ZCode · MiniMax Code · WorkBuddy · DeepSeek Harness · QwenWork · Token、模型与用量")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let lastRefreshAt = store.lastRefreshAt {
                    Text("更新 \(lastRefreshAt, format: .dateTime.hour().minute().second())")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                Text("正在读取")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text(store.connectedCount > 0 ? "本机 AI 数据已接入" : "等待本机数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
            }

            DashboardIconButton(symbol: "gearshape", help: "账户设置") {
                SettingsWindowController.shared.show()
            }
        }
    }

    private var periodSelector: some View {
        HStack(spacing: 3) {
            ForEach(DashboardPeriod.allCases) { value in
                Button {
                    guard period != value else { return }
                    if reduceMotion {
                        period = value
                    } else {
                        withAnimation(DashboardMotion.periodSelection) {
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
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var providerCardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
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
                Text("每 30 秒自动刷新")
                Text("·")
                    .foregroundStyle(.white.opacity(0.22))
                Text("Token/额度按实际来源；成本仅对有 Token 与价格表的数据估算")
                Spacer()
                Text(
                    store.isRefreshing
                        ? "更新中"
                        : (store.refreshError == nil ? "本机优先" : "稍后重试")
                )
                    .foregroundStyle(.white.opacity(0.45))
            }

            if !hiddenProviderNames.isEmpty {
                Text("本时段未检测到使用：\(hiddenProviderNames.joined(separator: " · "))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(2)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.48))
    }
}

private struct BalancePresentation {
    let metric: UsageMetric
    let title: String
    let valueText: String
    let percentText: String?
    let remainingFraction: Double?
    let resetAt: Date?
    let planName: String?
}

private struct DashboardProviderCard: View {
    let snapshot: ProviderSnapshot
    let period: DashboardPeriod
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

    private var balanceMetric: UsageMetric? {
        let candidates = account.metrics.filter { $0.kind == .quota }
        let preferredWindows: [UsageWindow]
        switch snapshot.provider {
        case .codex, .miniMax, .chatGPT, .zcode:
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
            if let match = matches.first { return match }
        }
        return candidates.first
    }

    private var balancePresentation: BalancePresentation? {
        guard let metric = balanceMetric else { return nil }

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
            valueText = "\(NumberFormat.compact(remaining)) \(metric.unit)"
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
        if metric.unit.lowercased().contains("credit") {
            return "Credits 剩余"
        }
        switch metric.window {
        case .weekly, .lastWeek:
            return "周剩余"
        case .fiveHours:
            return "5 小时剩余"
        case .daily, .today:
            return "每日剩余"
        case .billing, .monthly:
            return "订阅剩余"
        case .lastMonth:
            return "上月剩余"
        default:
            return "余额"
        }
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
        metric(kind: .tokens) ?? metric(kind: .quota) ?? metric(kind: .credits) ?? metric(kind: .requests)
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
        snapshot.provider == .deepSeekHarness ? "CNY" : "USD"
    }

    private var stats: [DashboardStat] {
        [
            DashboardStat(
                symbol: costUnit == "CNY" ? "yensign.circle" : "dollarsign.circle",
                title: "成本估算",
                value: costEstimate.map { NumberFormat.currency($0, unit: costUnit) } ?? "—"
            ),
            DashboardStat(
                symbol: "circle",
                title: "缓存命中",
                value: cacheHitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                usesCacheHitIcon: true,
                progress: cacheHitRate
            ),
            DashboardStat(
                symbol: "arrow.down",
                title: "输入",
                value: inputTokens.map(NumberFormat.compact) ?? "—"
            ),
            DashboardStat(
                symbol: "arrow.up",
                title: "输出",
                value: outputTokens.map(NumberFormat.compact) ?? "—"
            )
        ]
    }

    @ViewBuilder
    private var balanceSection: some View {
        if let balance = balancePresentation {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
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

                HStack {
                    Text("plan")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                    Spacer(minLength: 4)
                    Text(balance.planName ?? "—")
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DashboardPalette.cardBackground(for: snapshot.provider),
                            DashboardPalette.cardBackground(for: snapshot.provider).opacity(0.64)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DashboardPalette.color(for: snapshot.provider).opacity(0.55), lineWidth: 1.2)
        )
        .shadow(color: DashboardPalette.color(for: snapshot.provider).opacity(0.10), radius: 16, y: 6)
    }

    private var cardHeader: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(DashboardPalette.color(for: snapshot.provider))
                .frame(width: 11, height: 11)
                .shadow(color: DashboardPalette.color(for: snapshot.provider), radius: 7)
            Text(snapshot.provider.displayName)
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
                Text("等待数据")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(stats) { stat in
                DashboardStatView(stat: stat, accent: DashboardPalette.color(for: snapshot.provider))
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isModelExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DashboardPalette.color(for: snapshot.provider))
                    Text("按模型 (\(modelUsages.count))")
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
                    Text("暂无可识别的模型明细")
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
            let unit = requestMetric?.title.contains("会话") == true ? "会话" : "请求"
            return "\(NumberFormat.compact(requests)) \(unit)"
        }
        if snapshot.accounts.count > 1 {
            return "\(snapshot.accounts.count) 账户"
        }
        return snapshot.state == .connected ? "OK" : "—"
    }

    private var statusSymbol: String {
        switch snapshot.state {
        case .connected: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .unavailable: return "minus.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .connected: return DashboardPalette.success
        case .partial: return DashboardPalette.warning
        case .unavailable: return .white.opacity(0.32)
        }
    }

    private var statusHelp: String {
        if let message = account.message, !message.isEmpty {
            return message
        }
        switch snapshot.state {
        case .connected: return "数据已正常读取"
        case .partial: return "部分数据可用"
        case .unavailable: return "暂未读取到数据"
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
        switch metric.kind {
        case .tokens: return "\(period.title)总量"
        case .requests: return "\(period.title)请求"
        case .duration: return "\(period.title)活跃"
        case .credits: return "\(period.title) Credits"
        case .money: return "\(period.title)成本"
        case .quota: return metric.remaining != nil ? "剩余额度" : "订阅额度"
        }
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
                Image(systemName: stat.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.13), in: Circle())
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

    private var primaryValue: String {
        if usage.tokens.total > 0 { return NumberFormat.compact(usage.tokens.total) }
        if usage.requests > 0 { return "\(NumberFormat.compact(usage.requests)) 次" }
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
                    ModelDetailChip(title: "输入 ↓", value: NumberFormat.compact(usage.tokens.input), accent: accent)
                }
                if usage.tokens.output > 0 {
                    ModelDetailChip(title: "输出 ↑", value: NumberFormat.compact(usage.tokens.output), accent: accent)
                }
                if usage.tokens.cacheRead > 0 {
                    ModelDetailChip(title: "缓存读 ⚡", value: NumberFormat.compact(usage.tokens.cacheRead), accent: accent)
                }
                if usage.tokens.cacheWrite > 0 {
                    ModelDetailChip(title: "缓存写", value: NumberFormat.compact(usage.tokens.cacheWrite), accent: accent)
                }
                if usage.tokens.reasoning > 0 {
                    ModelDetailChip(title: "推理 🧠", value: NumberFormat.compact(usage.tokens.reasoning), accent: accent)
                }
                if usage.hitRate == nil, usage.requests > 0 {
                    ModelDetailChip(title: "请求", value: "\(NumberFormat.compact(usage.requests)) 次", accent: accent)
                }
                if usage.credits > 0 {
                    ModelDetailChip(title: "Credits", value: NumberFormat.compact(usage.credits), accent: accent)
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
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DashboardRefreshButton: View {
    @ObservedObject var store: UsageStore

    private var accent: Color {
        store.refreshError == nil ? DashboardPalette.accent : DashboardPalette.warning
    }

    private var title: String {
        if store.isRefreshing { return "同步中" }
        if store.refreshError != nil { return "重试" }
        return "更新"
    }

    var body: some View {
        Button {
            store.refresh()
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.27),
                                Color.white.opacity(0.08),
                                accent.opacity(0.14)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                Capsule()
                    .stroke(accent.opacity(store.isRefreshing ? 0.56 : 0.22), lineWidth: 1)

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
            }
            .frame(width: 92, height: 29)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("立即更新本机用量")
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
        case .chatGPT: return Color(red: 0.35, green: 0.82, blue: 0.72)
        case .qwenWork: return Color(red: 0.42, green: 0.69, blue: 1.0)
        case .zcode: return Color(red: 0.34, green: 0.78, blue: 0.92)
        case .qianwenOffice: return Color(red: 0.33, green: 0.80, blue: 0.88)
        case .deepSeekHarness: return Color(red: 0.86, green: 0.48, blue: 0.72)
        case .workBuddy: return Color(red: 0.43, green: 0.84, blue: 0.75)
        case .miniMax: return Color(red: 0.72, green: 0.57, blue: 1.0)
        }
    }

    static func cardBackground(for provider: ProviderID) -> Color {
        color(for: provider).opacity(0.11)
    }
}
