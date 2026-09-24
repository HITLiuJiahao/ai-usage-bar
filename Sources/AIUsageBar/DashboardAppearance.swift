import AppKit
import SwiftUI

enum DashboardColorPreset: String, CaseIterable, Identifiable {
    case followSystem
    case deepBlue
    case fogWhite
    case graphite
    case lavender

    var id: String { rawValue }
}

enum DashboardVisualStyle: String, CaseIterable, Identifiable {
    case glass
    case softSolid
    case minimal

    var id: String { rawValue }
}

final class DashboardAppearanceSettings: ObservableObject {
    static let shared = DashboardAppearanceSettings()

    private enum Key {
        static let preset = "aiUsageBar.dashboardColorPreset"
        static let style = "aiUsageBar.dashboardVisualStyle"
        static let accent = "aiUsageBar.dashboardCustomAccent"
    }

    @Published var preset: DashboardColorPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: Key.preset) }
    }

    @Published var style: DashboardVisualStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Key.style) }
    }

    @Published private(set) var customAccentHex: String? {
        didSet {
            if let customAccentHex {
                UserDefaults.standard.set(customAccentHex, forKey: Key.accent)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.accent)
            }
        }
    }

    private init() {
        preset = DashboardColorPreset(
            rawValue: UserDefaults.standard.string(forKey: Key.preset) ?? ""
        ) ?? .deepBlue
        style = DashboardVisualStyle(
            rawValue: UserDefaults.standard.string(forKey: Key.style) ?? ""
        ) ?? .glass
        customAccentHex = Self.normalizedHex(UserDefaults.standard.string(forKey: Key.accent))
    }

    var customAccent: Color? {
        guard let customAccentHex, let rgb = Self.rgb(from: customAccentHex) else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    func setCustomAccent(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
        let red = Int((min(max(rgb.redComponent, 0), 1) * 255).rounded())
        let green = Int((min(max(rgb.greenComponent, 0), 1) * 255).rounded())
        let blue = Int((min(max(rgb.blueComponent, 0), 1) * 255).rounded())
        customAccentHex = String(format: "#%02X%02X%02X", red, green, blue)
    }

    func clearCustomAccent() { customAccentHex = nil }

    func restoreDefaults() {
        preset = .deepBlue
        style = .glass
        customAccentHex = nil
    }

    private static func normalizedHex(_ value: String?) -> String? {
        guard let value, rgb(from: value) != nil else { return nil }
        return value.uppercased()
    }

    private static func rgb(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 7, hex.first == "#",
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

struct DashboardTheme {
    let preset: DashboardColorPreset
    let style: DashboardVisualStyle
    let accent: Color

    init(settings: DashboardAppearanceSettings, systemColorScheme: ColorScheme) {
        self.init(
            preset: settings.preset,
            style: settings.style,
            customAccent: settings.customAccent,
            systemColorScheme: systemColorScheme
        )
    }

    init(
        preset selectedPreset: DashboardColorPreset,
        style: DashboardVisualStyle,
        customAccent: Color?,
        systemColorScheme: ColorScheme
    ) {
        preset = selectedPreset == .followSystem
            ? (systemColorScheme == .dark ? .deepBlue : .fogWhite)
            : selectedPreset
        self.style = style
        accent = customAccent ?? Self.presetAccent(for: preset)
    }

    static let defaultTheme = DashboardTheme(
        settings: .shared,
        systemColorScheme: .dark
    )

    var isDark: Bool { preset == .deepBlue || preset == .graphite }

    var ink: Color {
        switch preset {
        case .deepBlue, .graphite: return .white
        case .fogWhite: return Color(red: 0.10, green: 0.15, blue: 0.22)
        case .lavender: return Color(red: 0.17, green: 0.13, blue: 0.24)
        case .followSystem: return .white
        }
    }

    func text(_ opacity: Double) -> Color {
        ink.opacity(max(opacity, isDark ? 0.58 : 0.72))
    }

    var background: LinearGradient {
        let colors: [Color]
        switch preset {
        case .deepBlue, .followSystem:
            colors = [Color(red: 0.10, green: 0.11, blue: 0.16), Color(red: 0.14, green: 0.15, blue: 0.21)]
        case .fogWhite:
            colors = [Color(red: 0.97, green: 0.98, blue: 1.00), Color(red: 0.92, green: 0.95, blue: 0.98)]
        case .graphite:
            colors = [Color(red: 0.12, green: 0.14, blue: 0.17), Color(red: 0.19, green: 0.21, blue: 0.25)]
        case .lavender:
            colors = [Color(red: 0.98, green: 0.96, blue: 1.00), Color(red: 0.93, green: 0.90, blue: 0.98)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var glowOpacity: Double {
        switch style {
        case .glass: return isDark ? 0.18 : 0.10
        case .softSolid: return isDark ? 0.08 : 0.05
        case .minimal: return 0
        }
    }

    var surfaceFill: Color {
        if isDark {
            return preset == .graphite
                ? Color(red: 0.20, green: 0.22, blue: 0.26)
                : Color(red: 0.20, green: 0.23, blue: 0.30)
        }
        return .white
    }

    var subtleFill: Color { ink.opacity(isDark ? 0.07 : 0.055) }
    var edge: Color { ink.opacity(isDark ? 0.14 : 0.16) }
    var hairline: Color { ink.opacity(isDark ? 0.11 : 0.13) }
    var success: Color { isDark ? Color(red: 0.43, green: 0.84, blue: 0.75) : Color(red: 0.05, green: 0.48, blue: 0.37) }
    var warning: Color { isDark ? Color(red: 1.0, green: 0.66, blue: 0.30) : Color(red: 0.66, green: 0.36, blue: 0.03) }

    func cornerRadius(_ value: CGFloat) -> CGFloat {
        switch style {
        case .glass: return value
        case .softSolid: return max(11, value - 2)
        case .minimal: return max(8, value - 6)
        }
    }

    private static func presetAccent(for preset: DashboardColorPreset) -> Color {
        switch preset {
        case .deepBlue, .followSystem: return Color(red: 0.42, green: 0.69, blue: 1.00)
        case .fogWhite: return Color(red: 0.13, green: 0.40, blue: 0.79)
        case .graphite: return Color(red: 0.48, green: 0.76, blue: 0.91)
        case .lavender: return Color(red: 0.48, green: 0.31, blue: 0.75)
        }
    }
}

private struct DashboardThemeKey: EnvironmentKey {
    static let defaultValue = DashboardTheme.defaultTheme
}

extension EnvironmentValues {
    var dashboardTheme: DashboardTheme {
        get { self[DashboardThemeKey.self] }
        set { self[DashboardThemeKey.self] = newValue }
    }
}

private struct DashboardSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dashboardTheme) private var theme

    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: theme.cornerRadius(cornerRadius),
            style: .continuous
        )
        if theme.style == .glass && !reduceTransparency && contrast != .increased {
            content
                .aiLiquidGlass(tint: tint, in: shape, interactive: interactive)
                .overlay(shape.stroke(theme.edge, lineWidth: 0.8))
        } else if theme.style == .minimal && contrast != .increased {
            content
                .background {
                    shape.fill(theme.subtleFill)
                        .overlay {
                            if let tint { shape.fill(tint.opacity(0.55)) }
                        }
                }
                .overlay(shape.stroke(theme.edge, lineWidth: 1))
        } else {
            content
                .background {
                    shape.fill(theme.surfaceFill)
                        .overlay {
                            if let tint { shape.fill(tint) }
                        }
                }
                .overlay(shape.stroke(theme.edge, lineWidth: contrast == .increased ? 1.5 : 1))
                .shadow(
                    color: theme.style == .softSolid && contrast != .increased
                        ? .black.opacity(theme.isDark ? 0.17 : 0.07)
                        : .clear,
                    radius: 12,
                    y: 5
                )
        }
    }
}

extension View {
    func dashboardSurface(
        tint: Color? = nil,
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        modifier(DashboardSurfaceModifier(
            tint: tint,
            cornerRadius: cornerRadius,
            interactive: interactive
        ))
    }
}
