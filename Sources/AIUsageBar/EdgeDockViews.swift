import AppKit
import SwiftUI

struct ProviderLogo: View {
    let provider: ProviderID
    let size: CGFloat
    let fallbackColor: Color
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    init(
        provider: ProviderID,
        size: CGFloat = 24,
        fallbackColor: Color = .white
    ) {
        self.provider = provider
        self.size = size
        self.fallbackColor = fallbackColor
    }

    var body: some View {
        Group {
            if let image = Self.image(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: provider.symbolName)
                    .font(.system(size: size * 0.68, weight: .semibold))
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(
            L10n.providerName(provider, language: languageSettings.language)
        )
    }

    private static func image(for provider: ProviderID) -> NSImage? {
        guard let resourceName = resourceName(for: provider),
              let resourceURL = Bundle.main.url(
                  forResource: resourceName,
                  withExtension: "png",
                  subdirectory: "ProviderIcons"
              )
        else { return nil }

        return NSImage(contentsOf: resourceURL)
    }

    private static func resourceName(for provider: ProviderID) -> String? {
        switch provider {
        case .codex: return "provider-codex"
        case .qwenWork: return "provider-qwen-work"
        case .zcode: return "provider-zcode"
        case .doubaoWork: return "provider-doubao-work"
        case .workBuddy: return "provider-workbuddy"
        case .miniMax: return "provider-minimax"
        case .openCode: return "provider-open-code"
        case .qianwenOffice: return "provider-qianwen-office"
        case .deepSeekHarness: return "provider-deepseek-harness"
        default: return nil
        }
    }
}

/// WorkBuddy's own Credits glyph, copied from its bundled CreditsIcon
/// component so balance rows use the same visual language as the client.
struct WorkBuddyCreditsIcon: View {
    let size: CGFloat
    let color: Color

    // Keep the Credits glyph on the same visual scale as the SF Symbols used
    // by the cost and activity metrics. The SVG's artwork fills more of its
    // viewBox than a dollar-sign symbol fills its font box, so letting the
    // image occupy the whole badge makes it look oversized.
    private var glyphSize: CGFloat {
        min(size * 0.50, 11)
    }

    var body: some View {
        Group {
            if let image = Self.officialImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .foregroundStyle(color)
                    .frame(width: glyphSize, height: glyphSize)
            } else {
                Image(systemName: "seal.fill")
                    .font(.system(size: glyphSize * 0.72, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: glyphSize, height: glyphSize)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(L10n.text(.credits))
    }

    private static let officialImage: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "workbuddy-credits",
            withExtension: "svg",
            subdirectory: "ProviderIcons"
        ),
        let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        return image
    }()
}

struct UsageMetricIconBadge: View {
    let symbol: String
    let size: CGFloat
    let color: Color

    private var glyphSize: CGFloat {
        min(size * 0.50, 11)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ResetCreditIcon: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        UsageMetricIconBadge(
            symbol: "arrow.clockwise",
            size: size,
            color: color
        )
        .accessibilityLabel(L10n.text(.resetCreditsAvailable))
    }
}

enum EdgeDockLayout {
    static let railWidth: CGFloat = 82
    static let detailWidth: CGFloat = 286
    // Leave enough vertical room for the direct period selector and detail footer.
    static let panelHeight: CGFloat = 680
    static let panelSpacing: CGFloat = 9
    static let panelPadding: CGFloat = 10
    // Keep the first and last provider items inside the two large edge arcs.
    // Without these insets the collapsed rail starts underneath the upper
    // shoulder and the Codex icon is clipped by the surface mask.
    static let railTopInset: CGFloat = 60
    static let railBottomInset: CGFloat = 36
    // The reference edge is a quarter-circle whose radius is close to the
    // collapsed rail width, rather than a conventional small card radius.
    static var surfaceCornerRadius: CGFloat { collapsedWidth }
    static let edgeOverlap: CGFloat = 1

    static var collapsedWidth: CGFloat {
        railWidth + panelPadding * 2
    }

    static var expandedWidth: CGFloat {
        detailWidth + panelSpacing + railWidth + panelPadding * 2
    }

    static let maximumVisibleProviderCount = 6
}

struct EdgeDockView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var providerOrder = ProviderOrderStore.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let onSizeChange: (CGSize) -> Void
    let onOpenDashboard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeProvider: ProviderID?

    init(
        store: UsageStore,
        onSizeChange: @escaping (CGSize) -> Void = { _ in },
        onOpenDashboard: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onSizeChange = onSizeChange
        self.onOpenDashboard = onOpenDashboard
    }

    var body: some View {
        HStack(alignment: .center, spacing: EdgeDockLayout.panelSpacing) {
            if let activeSnapshot {
                EdgeDockDetailView(
                    snapshot: activeSnapshot,
                    onOpenDashboard: onOpenDashboard
                )
                .frame(width: EdgeDockLayout.detailWidth, height: EdgeDockLayout.panelHeight - 20)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
            }

            EdgeDockRail(
                snapshots: providerOrder.orderedSnapshots(store.snapshots),
                activeProvider: activeProvider,
                onHover: { provider, inside in
                    guard inside else { return }
                    activate(provider)
                },
                onSelect: activate,
                onOpenDashboard: onOpenDashboard
            )
            .frame(width: EdgeDockLayout.railWidth, height: EdgeDockLayout.panelHeight - 20)
        }
        .padding(EdgeDockLayout.panelPadding)
        .frame(width: panelWidth, height: EdgeDockLayout.panelHeight)
        .background(
            EdgeDockPalette.background
                .opacity(0.46)
                .clipShape(surfaceShape)
        )
        .clipShape(surfaceShape)
        .overlay(
            surfaceShape
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .aiLiquidGlass(
            tint: Color.white.opacity(0.10),
            in: surfaceShape
        )
        .preferredColorScheme(.dark)
        .onAppear {
            reportSize()
        }
        .onChange(of: activeProvider) { _ in
            reportSize()
        }
    }

    private var activeSnapshot: ProviderSnapshot? {
        guard let activeProvider else { return nil }
        return store.snapshots.first(where: { $0.provider == activeProvider })
    }

    private var surfaceShape: EdgeDockSurfaceShape {
        EdgeDockSurfaceShape(
            cornerRadius: EdgeDockLayout.surfaceCornerRadius,
            isExpanded: activeSnapshot != nil
        )
    }

    private var panelWidth: CGFloat {
        activeSnapshot == nil ? EdgeDockLayout.collapsedWidth : EdgeDockLayout.expandedWidth
    }

    private func activate(_ provider: ProviderID?) {
        if reduceMotion {
            activeProvider = provider
        } else {
            withAnimation(EdgeDockMotion.panel) {
                activeProvider = provider
            }
        }
    }

    private func reportSize() {
        let size = CGSize(width: panelWidth, height: EdgeDockLayout.panelHeight)
        DispatchQueue.main.async {
            onSizeChange(size)
        }
    }
}

private struct EdgeDockRail: View {
    let snapshots: [ProviderSnapshot]
    let activeProvider: ProviderID?
    let onHover: (ProviderID, Bool) -> Void
    let onSelect: (ProviderID) -> Void
    let onOpenDashboard: () -> Void
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(
                .vertical,
                showsIndicators: snapshots.count > EdgeDockLayout.maximumVisibleProviderCount
            ) {
                VStack(spacing: 5) {
                    ForEach(snapshots) { snapshot in
                        EdgeDockProviderItem(
                            snapshot: snapshot,
                            isSelected: activeProvider == snapshot.provider,
                            onHover: { inside in
                                onHover(snapshot.provider, inside)
                            },
                            onSelect: {
                                onSelect(snapshot.provider)
                            }
                        )
                    }
                }
                .padding(.top, EdgeDockLayout.railTopInset)
                .padding(.bottom, EdgeDockLayout.railBottomInset)
            }
            // A ScrollView can otherwise choose its content's ideal height
            // inside the fixed rail. Constrain it to the space above the
            // fixed controls so the seventh provider and later ones really
            // become scrollable instead of being clipped by the panel.
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
                .padding(.horizontal, 8)

            HStack(spacing: 9) {
                EdgeDockIconButton(
                    symbol: "rectangle.grid.2x2",
                    help: L10n.text(.openFullOverview, language: languageSettings.language),
                    action: onOpenDashboard
                )
                EdgeDockIconButton(
                    symbol: "gearshape",
                    help: L10n.text(.accountSettings, language: languageSettings.language),
                    action: { SettingsWindowController.shared.show() }
                )
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 2)
    }
}

private struct EdgeDockProviderItem: View {
    let snapshot: ProviderSnapshot
    let isSelected: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    private var summary: EdgeDockSummary {
        EdgeDockData.summary(for: snapshot)
    }

    private var accent: Color {
        EdgeDockPalette.color(for: snapshot.provider)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(isSelected ? 0.36 : 0.27))

                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)

                    if let progress = summary.progress {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                accent,
                                style: StrokeStyle(
                                    lineWidth: 4,
                                    lineCap: progress > 0.995 ? .butt : .round
                                )
                            )
                            .rotationEffect(.degrees(-90))
                    } else {
                        Circle()
                            .stroke(
                                accent.opacity(snapshot.state == .unavailable ? 0.24 : 0.62),
                                lineWidth: 4
                            )
                    }

                    ProviderLogo(
                        provider: snapshot.provider,
                        size: 24,
                        fallbackColor: accent
                    )
                    .clipShape(Circle())
                    .opacity(snapshot.state == .unavailable ? 0.50 : 0.96)
                }
                .frame(width: 46, height: 46)
                .overlay(
                    Circle()
                        .stroke(isSelected ? accent.opacity(0.60) : Color.clear, lineWidth: 1)
                        .padding(-2)
                )

                Text(summary.valueText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(snapshot.state == .unavailable ? 0.42 : 0.96))
                    .frame(height: 16)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: EdgeDockLayout.railWidth - 8, height: 76)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .help(
            "\(L10n.providerName(snapshot.provider, language: languageSettings.language))：\(summary.accessibilityText)"
        )
    }
}

private enum EdgeDockActivityPeriod: String, CaseIterable, Identifiable, Equatable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisYear

    var id: String { rawValue }

    var window: UsageWindow {
        switch self {
        case .today: return .today
        case .yesterday: return .yesterday
        case .thisWeek: return .weekly
        case .lastWeek: return .lastWeek
        case .thisYear: return .yearly
        }
    }

    func title(language: AppLanguage) -> String {
        L10n.periodTitle(rawValue, language: language)
    }
}

private struct EdgeDockDetailView: View {
    let snapshot: ProviderSnapshot
    let onOpenDashboard: () -> Void
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activityPeriod: EdgeDockActivityPeriod = .today
    @Namespace private var activityPeriodSelectionNamespace

    private var accent: Color {
        EdgeDockPalette.color(for: snapshot.provider)
    }

    private var account: AccountUsageSnapshot {
        snapshot.accounts.first ?? AccountUsageSnapshot(
            id: "edge-dock-empty",
            provider: snapshot.provider,
            accountName: L10n.text(.currentAccount, language: languageSettings.language),
            state: .unavailable,
            metrics: [],
            updatedAt: snapshot.updatedAt,
            message: nil,
            source: .unavailable
        )
    }

    private var quotaMetrics: [UsageMetric] {
        EdgeDockData.quotaMetrics(for: snapshot)
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

    private var activityMetrics: [UsageMetric] {
        let preferredKinds: [MetricKind] = [.tokens, .requests, .money, .credits]
        return preferredKinds.compactMap { kind in
            account.metrics.first {
                $0.window == activityPeriod.window
                    && $0.kind == kind
                    && $0.hasActualUsage
            }
        }
    }

    private var modelUsages: [ModelUsage] {
        var seenModelKeys = Set<String>()
        let sorted = account.modelUsages
            .filter { $0.window == activityPeriod.window && $0.hasUsage }
            .sorted { lhs, rhs in
                let lhsValue = EdgeDockData.modelUsageValue(lhs)
                let rhsValue = EdgeDockData.modelUsageValue(rhs)
                if lhsValue != rhsValue {
                    return lhsValue > rhsValue
                }

                let lhsWindow = EdgeDockData.modelWindowPriority(lhs.window)
                let rhsWindow = EdgeDockData.modelWindowPriority(rhs.window)
                if lhsWindow != rhsWindow {
                    return lhsWindow < rhsWindow
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .filter { usage in
                seenModelKeys.insert(Self.modelKey(for: usage.name)).inserted
            }

        return Array(sorted.prefix(4))
    }

    private static func modelKey(for name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .padding(.vertical, 12)

            activityPeriodSelector

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    hero

                    if !quotaMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            sectionTitle(L10n.text(.balance, language: languageSettings.language))
                            ForEach(quotaMetrics) { metric in
                                EdgeDockQuotaRow(
                                    metric: metric,
                                    accent: accent,
                                    provider: snapshot.provider
                                )
                            }
                        }
                    }

                    if let resetCreditsAvailableCount {
                        HStack(spacing: 8) {
                            ResetCreditIcon(size: 24, color: accent)
                            Text(
                                L10n.resetCreditsAvailableText(
                                    count: resetCreditsAvailableCount,
                                    language: languageSettings.language
                                )
                            )
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.68))
                            Spacer(minLength: 4)
                            if let resetCreditsExpiresAt {
                                HStack(spacing: 3) {
                                    Text(L10n.text(.resetCreditsExpiresAt, language: languageSettings.language))
                                    Text(resetCreditsExpiresAt, formatter: Self.resetCreditDateFormatter)
                                }
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            }
                        }
                    }

                    if !activityMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            sectionTitle(
                                scopedSectionTitle(
                                    L10n.text(.localActivity, language: languageSettings.language)
                                )
                            )
                            ForEach(activityMetrics) { metric in
                                EdgeDockActivityRow(
                                    metric: metric,
                                    accent: accent,
                                    provider: snapshot.provider
                                )
                            }
                        }
                    }

                    if !modelUsages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle(
                                scopedSectionTitle(
                                    L10n.text(.models, language: languageSettings.language)
                                )
                            )
                            ForEach(modelUsages) { usage in
                                EdgeDockModelRow(
                                    usage: usage,
                                    accent: accent,
                                    currencyUnit: snapshot.provider == .deepSeekHarness ? "CNY" : "USD"
                                )
                            }
                        }
                    }

                    if quotaMetrics.isEmpty && activityMetrics.isEmpty && modelUsages.isEmpty {
                        Text(account.message ?? L10n.text(.noUsage, language: languageSettings.language))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(
                    reduceMotion ? nil : EdgeDockMotion.periodContent,
                    value: activityPeriod
                )
            }

            Button(action: onOpenDashboard) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.grid.2x2")
                    Text(L10n.text(.openFullOverview, language: languageSettings.language))
                    Spacer()
                    Image(systemName: "arrow.left")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(15)
        .aiLiquidGlass(
            tint: accent.opacity(0.17),
            cornerRadius: 22
        )
    }

    private var activityPeriodSelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.text(.usageRange, language: languageSettings.language))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }

            HStack(spacing: 2) {
                ForEach(EdgeDockActivityPeriod.allCases) { period in
                    Button {
                        selectActivityPeriod(period)
                    } label: {
                        Text(period.title(language: languageSettings.language))
                            .font(.system(size: 10, weight: activityPeriod == period ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(activityPeriod == period ? .white : .white.opacity(0.54))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if activityPeriod == period {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(accent.opacity(0.22))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(accent.opacity(0.38), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(
                                            id: "edge-dock-period-selection",
                                            in: activityPeriodSelectionNamespace
                                        )
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .onHover { isHovering in
                        guard isHovering else { return }
                        selectActivityPeriod(period)
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.bottom, 2)
    }

    private func selectActivityPeriod(_ period: EdgeDockActivityPeriod) {
        guard activityPeriod != period else { return }
        if reduceMotion {
            activityPeriod = period
        } else {
            withAnimation(EdgeDockMotion.periodSelection) {
                activityPeriod = period
            }
        }
    }

    private func scopedSectionTitle(_ title: String) -> String {
        "\(title) · \(activityPeriod.title(language: languageSettings.language))"
    }

    private static let resetCreditDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private var detailHeader: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                ProviderLogo(
                    provider: snapshot.provider,
                    size: 20,
                    fallbackColor: accent
                )
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.providerName(snapshot.provider, language: languageSettings.language))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                Text(account.accountName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: statusSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let quota = EdgeDockData.primaryQuota(for: snapshot),
           let fraction = EdgeDockData.remainingFraction(for: quota) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(L10n.remainingLabel(for: quota, language: languageSettings.language))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }
        } else if let metric = activityMetrics.first {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    L10n.usedText(
                        for: metric,
                        currencyUnit: snapshot.provider == .deepSeekHarness ? "CNY" : "USD",
                        language: languageSettings.language
                    )
                )
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(L10n.metricTitle(metric, language: languageSettings.language))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }
        } else {
            Text("—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
            .textCase(.uppercase)
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
        case .connected: return EdgeDockPalette.success
        case .partial: return EdgeDockPalette.warning
        case .cached: return .purple
        case .unavailable: return .white.opacity(0.35)
        }
    }
}

private struct EdgeDockQuotaRow: View {
    let metric: UsageMetric
    let accent: Color
    let provider: ProviderID
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    private var fraction: Double? {
        EdgeDockData.remainingFraction(for: metric)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if metric.unit.localizedCaseInsensitiveContains("credit") {
                    if provider == .workBuddy {
                        WorkBuddyCreditsIcon(size: 20, color: accent)
                            .frame(width: 20, height: 20)
                            .background(accent.opacity(0.13), in: Circle())
                    } else {
                        UsageMetricIconBadge(
                            symbol: "dollarsign",
                            size: 20,
                            color: accent
                        )
                    }
                }
                Text(L10n.edgeQuotaTitle(for: metric, language: languageSettings.language))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                if let resetAt = metric.resetAt {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.28))
                    Text(
                        "\(L10n.text(.resetAt, language: languageSettings.language)) \(Self.resetDateFormatter.string(from: resetAt))"
                    )
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                Text(L10n.remainingText(for: metric, language: languageSettings.language))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                if let fraction, metric.unit != "%" {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                }
            }

            if let fraction {
                ProgressView(value: fraction, total: 1)
                    .progressViewStyle(.linear)
                    .tint(accent)
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)
            }
        }
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private struct EdgeDockActivityRow: View {
    let metric: UsageMetric
    let accent: Color
    let provider: ProviderID
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            if provider == .workBuddy && metric.kind == .credits {
                WorkBuddyCreditsIcon(size: 24, color: accent)
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.13), in: Circle())
            } else {
                UsageMetricIconBadge(
                    symbol: EdgeDockData.symbol(for: metric.kind),
                    size: 24,
                    color: accent
                )
            }

            Text(L10n.metricTitle(metric, language: languageSettings.language))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))

            Spacer(minLength: 4)

            Text(
                L10n.usedText(
                    for: metric,
                    currencyUnit: "USD",
                    language: languageSettings.language
                )
            )
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.90))
        }
    }
}

private struct EdgeDockModelRow: View {
    let usage: ModelUsage
    let accent: Color
    let currencyUnit: String
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(accent.opacity(0.78))
                .frame(width: 6, height: 6)
            Text(usage.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(primaryValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private var primaryValue: String {
        if usage.tokens.total > 0 { return NumberFormat.compact(usage.tokens.total) }
        if usage.requests > 0 {
            return "\(NumberFormat.compact(usage.requests)) \(L10n.text(.requestUnit, language: languageSettings.language))"
        }
        if usage.credits > 0 { return NumberFormat.compact(usage.credits) }
        if usage.cost > 0 { return NumberFormat.currency(usage.cost, unit: currencyUnit) }
        return "—"
    }
}

private struct EdgeDockIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.065), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct EdgeDockSummary {
    let valueText: String
    let labelText: String?
    let progress: Double?
    let accessibilityText: String
}

private enum EdgeDockData {
    static func summary(for snapshot: ProviderSnapshot) -> EdgeDockSummary {
        if let quota = primaryQuota(for: snapshot),
           let fraction = remainingFraction(for: quota) {
            let percent = Int((fraction * 100).rounded())
            return EdgeDockSummary(
                valueText: "\(percent)%",
                labelText: nil,
                progress: fraction,
                accessibilityText: "\(L10n.text(.remaining)) \(percent)%"
            )
        }

        let account = snapshot.accounts.first
        if let requests = account?.metrics.first(where: { $0.kind == .requests && $0.hasActualUsage }),
           let value = requests.used {
            return EdgeDockSummary(
                valueText: NumberFormat.compact(value),
                labelText: L10n.text(.requests),
                progress: nil,
                accessibilityText: "\(NumberFormat.compact(value)) \(L10n.text(.requestUnit)) \(L10n.text(.requests))"
            )
        }
        if let tokens = account?.metrics.first(where: { $0.kind == .tokens && $0.hasActualUsage }),
           let value = tokens.used {
            return EdgeDockSummary(
                valueText: NumberFormat.compact(value),
                labelText: L10n.text(.token),
                progress: nil,
                accessibilityText: "\(NumberFormat.compact(value)) \(L10n.text(.token))"
            )
        }

        return EdgeDockSummary(
            valueText: "—",
            labelText: nil,
            progress: nil,
            accessibilityText: snapshot.state == .unavailable
                ? L10n.text(.noData)
                : L10n.text(.noUsage)
        )
    }

    static func primaryQuota(for snapshot: ProviderSnapshot) -> UsageMetric? {
        quotaMetrics(for: snapshot).first
    }

    static func quotaMetrics(for snapshot: ProviderSnapshot) -> [UsageMetric] {
        guard let account = snapshot.accounts.first else { return [] }
        let candidates = account.metrics.filter { $0.kind == .quota }
        let order: [UsageWindow]
        switch snapshot.provider {
        case .codex:
            order = [.fiveHours, .weekly, .billing, .monthly]
        case .miniMax, .zcode, .openCode, .doubaoWork:
            order = [.weekly, .fiveHours, .billing, .monthly]
        default:
            order = [.billing, .monthly, .weekly, .fiveHours]
        }

        var result: [UsageMetric] = []
        for window in order {
            for candidate in candidates where candidate.window == window {
                if !result.contains(where: { $0.id == candidate.id }) {
                    result.append(candidate)
                }
                if snapshot.provider != .codex { break }
            }
            if snapshot.provider != .codex, !result.isEmpty { break }
        }
        return result
    }

    static func remainingFraction(for metric: UsageMetric) -> Double? {
        if metric.unit == "%", let remaining = metric.remaining {
            return min(max(remaining / 100, 0), 1)
        }
        if let remaining = metric.remaining, let limit = metric.limit, limit > 0 {
            return min(max(remaining / limit, 0), 1)
        }
        if let used = metric.used, let limit = metric.limit, limit > 0 {
            return min(max(1 - used / limit, 0), 1)
        }
        return nil
    }

    static func symbol(for kind: MetricKind) -> String {
        switch kind {
        case .tokens: return "number"
        case .requests: return "arrow.up.right"
        case .duration: return "clock"
        case .credits: return "circle.dollarsign"
        case .money: return "dollarsign"
        case .quota: return "gauge.medium"
        }
    }

    static func modelUsageValue(_ usage: ModelUsage) -> Double {
        max(usage.tokens.total, max(usage.requests, max(usage.credits, usage.cost)))
    }

    static func modelWindowPriority(_ window: UsageWindow) -> Int {
        switch window {
        case .today: return 0
        case .yesterday: return 1
        case .fiveHours: return 2
        case .daily: return 3
        case .weekly: return 4
        case .lastWeek: return 5
        case .monthly: return 6
        case .lastMonth: return 7
        case .yearly: return 8
        case .billing: return 9
        }
    }
}

private enum EdgeDockMotion {
    static let periodSelection = Animation.spring(
        response: 0.30,
        dampingFraction: 0.88,
        blendDuration: 0.04
    )

    static let periodContent = Animation.easeInOut(duration: 0.20)

    static let panel = Animation.timingCurve(
        0.22,
        0.82,
        0.24,
        1.0,
        duration: 0.28
    )
}

private struct EdgeDockSurfaceShape: Shape {
    let cornerRadius: CGFloat
    let isExpanded: Bool

    func path(in rect: CGRect) -> Path {
        if isExpanded {
            return expandedPath(in: rect)
        }

        return collapsedPath(in: rect)
    }

    private func expandedPath(in rect: CGRect) -> Path {
        // Once the detail panel is open, keep its content inside a normal
        // rectangle. Only the two left corners get a small radius; the right
        // edge stays square and flush with the screen edge.
        let radius = min(cornerRadius, min(18, rect.height * 0.10))
        let quarterCircleFactor: CGFloat = 0.5522848
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control1: CGPoint(
                x: rect.minX + radius * (1 - quarterCircleFactor),
                y: rect.maxY
            ),
            control2: CGPoint(
                x: rect.minX,
                y: rect.maxY - radius * (1 - quarterCircleFactor)
            )
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control1: CGPoint(
                x: rect.minX,
                y: rect.minY + radius * (1 - quarterCircleFactor)
            ),
            control2: CGPoint(
                x: rect.minX + radius * (1 - quarterCircleFactor),
                y: rect.minY
            )
        )
        path.closeSubpath()
        return path
    }

    private func collapsedPath(in rect: CGRect) -> Path {
        // Both shoulders use the same pair of tangent quarter-circle arcs.
        // Mirroring the geometry at the bottom keeps the rail attached to the
        // screen edge with the same soft transition at both ends.
        let depth = min(cornerRadius, min(rect.width, rect.height * 0.32))
        let upperRadius = depth * 0.38
        let lowerRadius = depth - upperRadius
        let topInset = min(depth * 0.28, rect.height * 0.12)
        let topBoundaryX = rect.minX + depth
        let shoulderX = rect.minX + lowerRadius
        let shoulderY = rect.minY + topInset + upperRadius
        let lowerArcEndY = shoulderY + lowerRadius
        let bottomBoundaryX = topBoundaryX
        let bottomShoulderY = rect.maxY - topInset - upperRadius
        let bottomArcEndY = bottomShoulderY - lowerRadius
        let quarterCircleFactor: CGFloat = 0.5522848
        var path = Path()

        path.move(to: CGPoint(x: topBoundaryX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomBoundaryX, y: rect.maxY))

        // Mirrored upper quarter-circle: bottom edge to the shared shoulder.
        path.addLine(to: CGPoint(x: bottomBoundaryX, y: bottomShoulderY + upperRadius))
        path.addCurve(
            to: CGPoint(x: shoulderX, y: bottomShoulderY),
            control1: CGPoint(
                x: bottomBoundaryX,
                y: bottomShoulderY + upperRadius - quarterCircleFactor * upperRadius
            ),
            control2: CGPoint(
                x: shoulderX + quarterCircleFactor * upperRadius,
                y: bottomShoulderY
            )
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: bottomArcEndY),
            control1: CGPoint(
                x: shoulderX - quarterCircleFactor * lowerRadius,
                y: bottomShoulderY
            ),
            control2: CGPoint(
                x: rect.minX,
                y: bottomArcEndY + quarterCircleFactor * lowerRadius
            )
        )
        path.addLine(to: CGPoint(x: rect.minX, y: lowerArcEndY))

        // Lower quarter-circle: left vertical edge to the shared shoulder.
        path.addCurve(
            to: CGPoint(x: shoulderX, y: shoulderY),
            control1: CGPoint(
                x: rect.minX,
                y: lowerArcEndY - quarterCircleFactor * lowerRadius
            ),
            control2: CGPoint(
                x: shoulderX - quarterCircleFactor * lowerRadius,
                y: shoulderY
            )
        )

        // Upper quarter-circle: the shared shoulder to the screen-edge end.
        path.addCurve(
            to: CGPoint(x: topBoundaryX, y: rect.minY + topInset),
            control1: CGPoint(
                x: shoulderX + quarterCircleFactor * upperRadius,
                y: shoulderY
            ),
            control2: CGPoint(
                x: topBoundaryX,
                y: rect.minY + topInset + quarterCircleFactor * upperRadius
            )
        )
        path.addLine(to: CGPoint(x: topBoundaryX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private enum EdgeDockPalette {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.015, green: 0.018, blue: 0.028),
            Color(red: 0.035, green: 0.040, blue: 0.060)
        ],
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
        case .openCode: return Color(red: 0.72, green: 0.76, blue: 0.88)
        case .doubaoWork: return Color(red: 0.98, green: 0.47, blue: 0.30)
        case .qianwenOffice: return Color(red: 0.33, green: 0.80, blue: 0.88)
        case .deepSeekHarness: return Color(red: 0.86, green: 0.48, blue: 0.72)
        case .workBuddy: return Color(red: 0.43, green: 0.84, blue: 0.75)
        case .miniMax: return Color(red: 0.72, green: 0.57, blue: 1.0)
        }
    }
}
