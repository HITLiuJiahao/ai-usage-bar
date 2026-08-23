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

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.medium")
            if let percent = store.criticalPercent {
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .help("AI 使用概览")
    }
}

struct UsagePopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.snapshots) { snapshot in
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
                Text("AI 使用概览")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(store.connectedCount > 0 ? "本机 AI 数据已接入" : "等待本机数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
            }
            .buttonStyle(.borderless)
            .help("立即刷新")
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("账户设置")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("每 30 秒自动刷新")
            Spacer()
            if store.isRefreshing {
                Text("更新中")
            } else if store.refreshError != nil {
                Text("稍后重试")
            } else if let lastRefreshAt = store.lastRefreshAt {
                Text(lastRefreshAt, style: .relative)
            } else {
                Text("首次读取中")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

struct ProviderCard: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.provider.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProviderPalette.color(for: snapshot.provider))
                    .frame(width: 22)
                Text(snapshot.provider.displayName)
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
                Text(account.message ?? "暂时没有可显示的指标")
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(metric.title)
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
                        Text("余 \(formatted(remaining))\(metric.unit == "%" ? "%" : "")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if let remaining = metric.remaining {
                    Text("余 \(formatted(remaining)) \(metric.unit)")
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
            return "\(formatted(used)) / \(formatted(limit)) \(metric.unit)"
        }
        if let used = metric.used {
            if metric.kind == .money { return NumberFormat.currency(used, unit: metric.unit) }
            return "\(formatted(used)) \(metric.unit)"
        }
        if let remaining = metric.remaining {
            return "余 \(formatted(remaining)) \(metric.unit)"
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

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(state.title)
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
        case .unavailable: return .secondary
        }
    }
}

struct SourceBadge: View {
    let source: DataSource

    var body: some View {
        Text(source.title)
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

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                ) {
                    Label("开机自启", systemImage: "power")
                }

                HStack(spacing: 6) {
                    Text(launchAtLogin.statusText)
                    Spacer()
                    if launchAtLogin.status == .requiresApproval {
                        Button("打开系统设置…") {
                            launchAtLogin.openLoginItemsSettings()
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
                Text("应用设置")
            } footer: {
                Text("启用后，登录 macOS 账户时会自动启动 AI Usage Bar，并继续在菜单栏运行。")
            }

            Section {
                let trackedAccounts = store.accounts.filter { ProviderID.trackedCases.contains($0.provider) }
                if trackedAccounts.isEmpty {
                    Text("还没有手动添加的账户。")
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
                Text("已配置账户")
            }

            Section {
                Picker("产品", selection: $store.provider) {
                    ForEach(ProviderID.trackedCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField("账户名称", text: $store.name)
                SecureField("API Key / Access Token", text: $store.credential)
                Button("添加账户") {
                    store.addAccount()
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("添加服务端账户")
            } footer: {
                Text("Codex 当前登录态会自动读取；QwenWork 的订阅 Credits 来自官方账户接口，本地日志补充请求和模型明细。需要读取官方额度时，可将 Access Token 保存到 macOS 钥匙串。")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 430)
        .padding(.top, 8)
    }
}
