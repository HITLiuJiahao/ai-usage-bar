import Foundation
import Security
import SwiftUI

struct SavedAccount: Codable, Identifiable, Equatable {
    let id: UUID
    let provider: ProviderID
    var name: String
    var enabled: Bool

    init(id: UUID = UUID(), provider: ProviderID, name: String, enabled: Bool = true) {
        self.id = id
        self.provider = provider
        self.name = name
        self.enabled = enabled
    }
}

enum CredentialKeychain {
    private static let service = "com.aiusagebar.credentials.v1"

    static func save(_ value: String, for account: SavedAccount) throws {
        guard let data = value.data(using: .utf8), !value.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(for account: SavedAccount) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for account: SavedAccount) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum LocalAccountStore {
    private static let fileURL = AppPaths.appSupport.appendingPathComponent("accounts.json")

    private static func loadAccounts() -> [SavedAccount] {
        guard let data = try? Data(contentsOf: fileURL),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        // Ignore account records for providers removed from the application
        // without making the rest of the account file unreadable.
        return objects.compactMap { object in
            guard let rawProvider = object["provider"] as? String,
                  ProviderID(rawValue: rawProvider) != nil,
                  let accountData = try? JSONSerialization.data(withJSONObject: object),
                  let account = try? JSONDecoder().decode(SavedAccount.self, from: accountData)
            else { return nil }
            return account
        }
    }

    static func accounts(for provider: ProviderID? = nil) -> [SavedAccount] {
        let accounts = loadAccounts()
        return accounts.filter { account in
            account.enabled && (provider == nil || account.provider == provider)
        }
    }

    static func allAccounts() -> [SavedAccount] {
        loadAccounts()
    }

    static func save(_ accounts: [SavedAccount]) throws {
        try FileManager.default.createDirectory(
            at: AppPaths.appSupport,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(accounts).write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class AccountSettingsStore: ObservableObject {
    @Published var accounts: [SavedAccount] = LocalAccountStore.allAccounts()
    @Published var provider: ProviderID = .codex
    @Published var name = ""
    @Published var credential = ""
    @Published var errorMessage: String?

    func addAccount() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCredential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCredential.isEmpty else {
            errorMessage = "请填写账户名称和 API Key / Access Token。"
            return
        }
        let account = SavedAccount(provider: provider, name: trimmedName)
        do {
            try CredentialKeychain.save(trimmedCredential, for: account)
            accounts.append(account)
            try LocalAccountStore.save(accounts)
            name = ""
            credential = ""
            errorMessage = nil
        } catch {
            errorMessage = "保存账户失败：\(error.localizedDescription)"
            CredentialKeychain.delete(for: account)
        }
    }

    func toggle(_ account: SavedAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].enabled.toggle()
        do {
            try LocalAccountStore.save(accounts)
        } catch {
            errorMessage = "保存开关失败：\(error.localizedDescription)"
        }
    }

    func remove(_ account: SavedAccount) {
        accounts.removeAll { $0.id == account.id }
        CredentialKeychain.delete(for: account)
        do {
            try LocalAccountStore.save(accounts)
        } catch {
            errorMessage = "删除账户失败：\(error.localizedDescription)"
        }
    }
}
