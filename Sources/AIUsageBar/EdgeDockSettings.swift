import Combine
import Foundation

enum EdgeDockSide: String {
    case left
    case right
}

enum EdgeDockExpansionMode: String, CaseIterable, Identifiable {
    case right
    case left
    case both
    case disabled

    var id: String { rawValue }

    var localizationKey: L10n.Key {
        switch self {
        case .right: return .sidebarExpansionRight
        case .left: return .sidebarExpansionLeft
        case .both: return .sidebarExpansionBoth
        case .disabled: return .sidebarExpansionDisabled
        }
    }

    var preferredSide: EdgeDockSide {
        switch self {
        case .left: return .left
        case .right, .both, .disabled: return .right
        }
    }

    var isDisabled: Bool {
        self == .disabled
    }

    func allows(_ side: EdgeDockSide) -> Bool {
        switch self {
        case .right: return side == .right
        case .left: return side == .left
        case .both: return true
        case .disabled: return false
        }
    }
}

final class EdgeDockExpansionSettings: ObservableObject {
    static let shared = EdgeDockExpansionSettings()

    private static let defaultsKey = "aiUsageBar.edgeDockExpansionMode"

    @Published var mode: EdgeDockExpansionMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        mode = EdgeDockExpansionMode(
            rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        ) ?? .right
    }
}
