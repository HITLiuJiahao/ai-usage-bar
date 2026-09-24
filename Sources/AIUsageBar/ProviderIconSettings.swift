import AppKit
import Combine
import SwiftUI

struct ProviderIconOption: Identifiable {
    let id: String
    let resourceName: String
    let titleKey: L10n.Key
}

/// Only providers with multiple bundled, official assets appear in Settings.
/// Add future variants here; the picker and every ProviderLogo then share the
/// same choice without any provider-specific view code.
enum ProviderIconCatalog {
    private static let codexOptions: [ProviderIconOption] = [
        ProviderIconOption(id: "openai", resourceName: "provider-codex", titleKey: .providerIconOpenAI),
        ProviderIconOption(id: "codex-light", resourceName: "provider-codex-light", titleKey: .providerIconCodexLight),
        ProviderIconOption(id: "codex-dark", resourceName: "provider-codex-dark", titleKey: .providerIconCodexDark)
    ]

    static var configurableProviders: [ProviderID] {
        ProviderID.trackedCases.filter { options(for: $0).count > 1 }
    }

    static func options(for provider: ProviderID) -> [ProviderIconOption] {
        switch provider {
        case .codex: return codexOptions
        default: return []
        }
    }

    static func resourceName(for provider: ProviderID, selectedID: String) -> String? {
        if let selected = options(for: provider).first(where: { $0.id == selectedID }) {
            return selected.resourceName
        }

        switch provider {
        case .codex: return "provider-codex"
        case .kimi: return "provider-kimi"
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

final class ProviderIconSettings: ObservableObject {
    static let shared = ProviderIconSettings()

    @Published private(set) var selectedIDs: [ProviderID: String]

    private init() {
        var saved: [ProviderID: String] = [:]
        for provider in ProviderIconCatalog.configurableProviders {
            let id = UserDefaults.standard.string(forKey: Self.defaultsKey(for: provider)) ?? ""
            if ProviderIconCatalog.options(for: provider).contains(where: { $0.id == id }) {
                saved[provider] = id
            }
        }
        selectedIDs = saved
    }

    func selectedID(for provider: ProviderID) -> String {
        selectedIDs[provider] ?? ProviderIconCatalog.options(for: provider).first?.id ?? ""
    }

    func select(_ id: String, for provider: ProviderID) {
        guard ProviderIconCatalog.options(for: provider).contains(where: { $0.id == id }),
              selectedID(for: provider) != id else { return }
        var updated = selectedIDs
        updated[provider] = id
        selectedIDs = updated
        UserDefaults.standard.set(id, forKey: Self.defaultsKey(for: provider))
    }

    private static func defaultsKey(for provider: ProviderID) -> String {
        "aiUsageBar.providerIcon.\(provider.rawValue)"
    }
}

struct ProviderIconSettingsSection: View {
    @ObservedObject private var iconSettings = ProviderIconSettings.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ProviderIconCatalog.configurableProviders) { provider in
                HStack(spacing: 10) {
                    ProviderLogo(
                        provider: provider,
                        size: 28,
                        fallbackColor: ProviderPalette.color(for: provider)
                    )
                    Text(L10n.providerName(provider, language: languageSettings.language))
                    Spacer(minLength: 12)
                    Picker(
                        L10n.providerName(provider, language: languageSettings.language),
                        selection: Binding(
                            get: { iconSettings.selectedID(for: provider) },
                            set: { iconSettings.select($0, for: provider) }
                        )
                    ) {
                        ForEach(ProviderIconCatalog.options(for: provider)) { option in
                            HStack(spacing: 7) {
                                ProviderLogo(
                                    provider: provider,
                                    size: 20,
                                    variantID: option.id,
                                    fallbackColor: ProviderPalette.color(for: provider)
                                )
                                Text(L10n.text(option.titleKey, language: languageSettings.language))
                            }
                            .tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }
        }
    }
}
