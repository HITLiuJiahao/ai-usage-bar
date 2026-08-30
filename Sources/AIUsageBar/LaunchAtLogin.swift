import AppKit
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginSettings: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published var errorMessage: String?

    init() {
        refresh()
    }

    var statusText: String {
        switch status {
        case .enabled:
            return L10n.text(.loginStatusEnabled)
        case .requiresApproval:
            return L10n.text(.loginStatusPending)
        case .notFound:
            return L10n.text(.loginStatusUnavailable)
        case .notRegistered:
            return L10n.text(.loginStatusDisabled)
        @unknown default:
            return L10n.text(.loginStatusUnknown)
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            errorMessage = enabled
                ? "开机自启开启失败：\(error.localizedDescription)"
                : "开机自启关闭失败：\(error.localizedDescription)"
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
