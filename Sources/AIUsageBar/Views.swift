import AppKit
import SwiftUI

@main
struct AIUsageBarApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var statusBar: StatusBarController

    init() {
        let store = UsageStore()
        _store = StateObject(wrappedValue: store)
        _statusBar = StateObject(wrappedValue: StatusBarController(store: store))
    }

    var body: some Scene {
        Settings {
            AccountSettingsView()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.medium")
            if let percent = store.criticalPercent {
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .help(L10n.text(.overviewTitle, language: languageSettings.language))
    }
}

struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var providerOrder = ProviderOrderStore.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(providerOrder.orderedSnapshots(store.snapshots)) { snapshot in
                        ProviderCard(snapshot: snapshot)
                    }
                }
            }

            Divider()
                .padding(.top, 10)
            footer
                .padding(.top, 8)
        }
        .padding(14)
        .frame(width: 460, height: 660)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(.overviewTitle, language: languageSettings.language))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(
                    L10n.text(
                        store.connectedCount > 0 ? .localDataConnected : .waitingForData,
                        language: languageSettings.language
                    )
                )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh(forceQuota: true)
            } label: {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
            }
            .buttonStyle(.borderless)
            .help(L10n.text(.refreshNow, language: languageSettings.language))
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L10n.text(.accountSettings, language: languageSettings.language))
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(L10n.text(.refreshEvery30Seconds, language: languageSettings.language))
            Spacer()
            if store.isRefreshing {
                Text(L10n.text(.updating, language: languageSettings.language))
            } else if store.refreshError != nil {
                Text(L10n.text(.retryLater, language: languageSettings.language))
            } else if let lastRefreshAt = store.lastRefreshAt {
                Text(lastRefreshAt, style: .relative)
            } else {
                Text(L10n.text(.firstRead, language: languageSettings.language))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

struct ProviderCard: View {
    let snapshot: ProviderSnapshot
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ProviderLogo(
                    provider: snapshot.provider,
                    size: 22,
                    fallbackColor: ProviderPalette.color(for: snapshot.provider)
                )
                Text(L10n.providerName(snapshot.provider, language: languageSettings.language))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                StatusPill(state: snapshot.state)
            }

            ForEach(snapshot.accounts) { account in
                AccountBlock(account: account)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct AccountBlock: View {
    let account: AccountUsageSnapshot
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text(account.accountName)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                SourceBadge(source: account.source)
            }

            if account.metrics.isEmpty {
                Text(account.message ?? L10n.text(.noMetric, language: languageSettings.language))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(account.metrics) { metric in
                        MetricRow(metric: metric)
                    }
                }
            }

            if let message = account.message, !account.metrics.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MetricRow: View {
    let metric: UsageMetric
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(L10n.metricTitle(metric, language: languageSettings.language))
                        .font(.system(size: 12, weight: .medium))
                    Text(metric.window.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    SourceBadge(source: metric.source)
                    if let note = metric.note, metric.limit == nil, metric.remaining == nil {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let progress = metric.progress {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(progressColor(progress))
                        .frame(width: 100)
                    if let remaining = metric.remaining {
                        Text("\(L10n.text(.remaining, language: languageSettings.language)) \(formatted(remaining))\(metric.unit == "%" ? "%" : "")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if let remaining = metric.remaining {
                    Text("\(L10n.text(.remaining, language: languageSettings.language)) \(formatted(remaining)) \(L10n.localizedUnit(metric.unit, language: languageSettings.language))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var valueText: String {
        if let used = metric.used, let limit = metric.limit {
            if metric.kind == .money {
                return "\(NumberFormat.currency(used, unit: metric.unit)) / \(NumberFormat.currency(limit, unit: metric.unit))"
            }
            return "\(formatted(used)) / \(formatted(limit)) \(L10n.localizedUnit(metric.unit, language: languageSettings.language))"
        }
        if let used = metric.used {
            if metric.kind == .money { return NumberFormat.currency(used, unit: metric.unit) }
            return "\(formatted(used)) \(L10n.localizedUnit(metric.unit, language: languageSettings.language))"
        }
        if let remaining = metric.remaining {
            return "\(L10n.text(.remaining, language: languageSettings.language)) \(formatted(remaining)) \(L10n.localizedUnit(metric.unit, language: languageSettings.language))"
        }
        return "—"
    }

    private func formatted(_ value: Double) -> String {
        if metric.kind == .money { return NumberFormat.currency(value, unit: metric.unit) }
        return NumberFormat.compact(value)
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress >= 0.9 { return .red }
        if progress >= 0.7 { return .orange }
        return .accentColor
    }
}

struct StatusPill: View {
    let state: ProviderState
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(L10n.stateTitle(state, language: languageSettings.language))
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .partial: return .orange
        case .cached: return .purple
        case .unavailable: return .secondary
        }
    }
}

struct SourceBadge: View {
    let source: DataSource
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        Text(L10n.sourceTitle(source, language: languageSettings.language))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
    }

    private var color: Color {
        switch source {
        case .server: return .blue
        case .local: return .secondary
        case .cached: return .purple
        case .unavailable: return .orange
        }
    }
}

enum ProviderPalette {
    static func color(for provider: ProviderID) -> Color {
        switch provider {
        case .codex: return .green
        case .chatGPT: return .teal
        case .qwenWork: return .blue
        case .zcode: return .cyan
        case .openCode: return .gray
        case .doubaoWork: return .orange
        case .qianwenOffice: return .cyan
        case .deepSeekHarness: return .pink
        case .workBuddy: return .indigo
        case .miniMax: return .purple
        }
    }
}

struct AccountSettingsView: View {
    @StateObject private var store = AccountSettingsStore()
    @StateObject private var launchAtLogin = LaunchAtLoginSettings()
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                    ) {
                    Label {
                        Text(L10n.text(.launchAtLogin, language: languageSettings.language))
                    } icon: {
                        Image(systemName: "power")
                    }
                }

                HStack(spacing: 6) {
                    Text(launchAtLogin.statusText)
                    Spacer()
                    if launchAtLogin.status == .requiresApproval {
                        Button {
                            launchAtLogin.openLoginItemsSettings()
                        } label: {
                            Text(L10n.text(.openSystemSettings, language: languageSettings.language))
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.text(.appSettings, language: languageSettings.language))
            } footer: {
                Text(
                    languageSettings.language == .simplifiedChinese
                        ? "启用后，登录 macOS 账户时会自动启动 AI Usage Bar，并继续在菜单栏运行。"
                        : languageSettings.language == .english
                            ? "When enabled, AI Usage Bar starts automatically when you log in to macOS and continues running in the menu bar."
                            : languageSettings.language == .japanese
                                ? "有効にすると、macOSへのログイン時にAI Usage Barが自動起動し、メニューバーで実行されます。"
                                : "활성화하면 macOS에 로그인할 때 AI Usage Bar가 자동으로 시작되어 메뉴 막대에서 실행됩니다."
                )
            }

            Section {
                let trackedAccounts = store.accounts.filter { ProviderID.trackedCases.contains($0.provider) }
                if trackedAccounts.isEmpty {
                    Text(L10n.text(.noManualAccounts, language: languageSettings.language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trackedAccounts) { account in
                        HStack(spacing: 8) {
                            Toggle(
                                isOn: Binding(
                                    get: { account.enabled },
                                    set: { _ in store.toggle(account) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                    Text(account.provider.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button(role: .destructive) {
                                store.remove(account)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text(L10n.text(.configuredAccounts, language: languageSettings.language))
            }

            Section {
                Picker(selection: $store.provider) {
                    ForEach(ProviderID.trackedCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                } label: {
                    Text(L10n.text(.product, language: languageSettings.language))
                }
                TextField(
                    L10n.text(.accountName, language: languageSettings.language),
                    text: $store.name
                )
                SecureField(
                    L10n.text(.accessToken, language: languageSettings.language),
                    text: $store.credential
                )
                Button {
                    store.addAccount()
                } label: {
                    Text(L10n.text(.addAccount, language: languageSettings.language))
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.text(.addServerAccount, language: languageSettings.language))
            } footer: {
                Text(L10n.text(.credentialsFooter, language: languageSettings.language))
            }

            Section {
                SidebarOrderEditor()
            } header: {
                Text(L10n.text(.sidebarOrder, language: languageSettings.language))
            } footer: {
                Text(L10n.text(.sidebarOrderHelp, language: languageSettings.language))
            }

            Section {
                Picker(selection: Binding(
                    get: { languageSettings.language },
                    set: { languageSettings.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Text(L10n.text(.language, language: languageSettings.language))
                }
            } footer: {
                Text(L10n.text(.languageHelp, language: languageSettings.language))
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 700)
        .padding(.top, 8)
    }
}
