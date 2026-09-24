import SwiftUI

enum AppearanceCopy {
    enum Key: String {
        case title, palette, style, accent, usePreset, restore, preview
        case followSystem, deepBlue, fogWhite, graphite, lavender
        case glass, softSolid, minimal
    }

    private static let strings: [AppLanguage: [Key: String]] = [
        .simplifiedChinese: [
            .title: "控制面板外观", .palette: "配色", .style: "风格", .accent: "自选强调色",
            .usePreset: "使用预设颜色", .restore: "恢复默认", .preview: "示例预览",
            .followSystem: "跟随系统", .deepBlue: "深蓝", .fogWhite: "雾白",
            .graphite: "石墨", .lavender: "淡紫", .glass: "玻璃",
            .softSolid: "柔和实体", .minimal: "极简"
        ],
        .traditionalChinese: [
            .title: "控制面板外觀", .palette: "配色", .style: "風格", .accent: "自選強調色",
            .usePreset: "使用預設顏色", .restore: "恢復預設", .preview: "範例預覽",
            .followSystem: "跟隨系統", .deepBlue: "深藍", .fogWhite: "霧白",
            .graphite: "石墨", .lavender: "淡紫", .glass: "玻璃",
            .softSolid: "柔和實體", .minimal: "極簡"
        ],
        .english: [
            .title: "Dashboard Appearance", .palette: "Color palette", .style: "Style", .accent: "Custom accent",
            .usePreset: "Use preset color", .restore: "Restore defaults", .preview: "Example preview",
            .followSystem: "Follow System", .deepBlue: "Deep Blue", .fogWhite: "Fog White",
            .graphite: "Graphite", .lavender: "Lavender", .glass: "Glass",
            .softSolid: "Soft Solid", .minimal: "Minimal"
        ],
        .japanese: [
            .title: "ダッシュボードの外観", .palette: "配色", .style: "スタイル", .accent: "カスタムアクセント",
            .usePreset: "標準色を使用", .restore: "初期設定に戻す", .preview: "プレビュー",
            .followSystem: "システムに合わせる", .deepBlue: "ディープブルー", .fogWhite: "フォグホワイト",
            .graphite: "グラファイト", .lavender: "ラベンダー", .glass: "ガラス",
            .softSolid: "ソフト", .minimal: "ミニマル"
        ],
        .korean: [
            .title: "대시보드 모양", .palette: "색상", .style: "스타일", .accent: "사용자 지정 강조색",
            .usePreset: "기본 색상 사용", .restore: "기본값 복원", .preview: "예시 미리보기",
            .followSystem: "시스템 설정 따르기", .deepBlue: "딥 블루", .fogWhite: "포그 화이트",
            .graphite: "그래파이트", .lavender: "라벤더", .glass: "유리",
            .softSolid: "부드러운 단색", .minimal: "미니멀"
        ],
        .spanish: [
            .title: "Aspecto del panel", .palette: "Colores", .style: "Estilo", .accent: "Color de acento personalizado",
            .usePreset: "Usar color predefinido", .restore: "Restablecer", .preview: "Vista previa",
            .followSystem: "Seguir el sistema", .deepBlue: "Azul oscuro", .fogWhite: "Blanco niebla",
            .graphite: "Grafito", .lavender: "Lavanda", .glass: "Cristal",
            .softSolid: "Sólido suave", .minimal: "Minimalista"
        ],
        .french: [
            .title: "Apparence du tableau de bord", .palette: "Palette", .style: "Style", .accent: "Couleur d’accent personnalisée",
            .usePreset: "Utiliser la couleur prédéfinie", .restore: "Rétablir les valeurs par défaut", .preview: "Aperçu",
            .followSystem: "Suivre le système", .deepBlue: "Bleu profond", .fogWhite: "Blanc brume",
            .graphite: "Graphite", .lavender: "Lavande", .glass: "Verre",
            .softSolid: "Uni doux", .minimal: "Minimal"
        ],
        .german: [
            .title: "Dashboard-Darstellung", .palette: "Farbschema", .style: "Stil", .accent: "Eigene Akzentfarbe",
            .usePreset: "Voreingestellte Farbe verwenden", .restore: "Standard wiederherstellen", .preview: "Vorschau",
            .followSystem: "Systemeinstellung", .deepBlue: "Dunkelblau", .fogWhite: "Nebelweiß",
            .graphite: "Graphit", .lavender: "Lavendel", .glass: "Glas",
            .softSolid: "Sanft", .minimal: "Minimal"
        ],
        .italian: [
            .title: "Aspetto del pannello", .palette: "Colori", .style: "Stile", .accent: "Colore accento personalizzato",
            .usePreset: "Usa colore predefinito", .restore: "Ripristina predefiniti", .preview: "Anteprima",
            .followSystem: "Segui il sistema", .deepBlue: "Blu profondo", .fogWhite: "Bianco nebbia",
            .graphite: "Grafite", .lavender: "Lavanda", .glass: "Vetro",
            .softSolid: "Tinta unita", .minimal: "Minimale"
        ],
        .portugueseBrazil: [
            .title: "Aparência do painel", .palette: "Cores", .style: "Estilo", .accent: "Cor de destaque personalizada",
            .usePreset: "Usar cor predefinida", .restore: "Restaurar padrões", .preview: "Prévia",
            .followSystem: "Seguir o sistema", .deepBlue: "Azul escuro", .fogWhite: "Branco névoa",
            .graphite: "Grafite", .lavender: "Lavanda", .glass: "Vidro",
            .softSolid: "Sólido suave", .minimal: "Minimalista"
        ],
        .russian: [
            .title: "Оформление панели", .palette: "Цвета", .style: "Стиль", .accent: "Свой цвет акцента",
            .usePreset: "Цвет по умолчанию", .restore: "Сбросить настройки", .preview: "Предпросмотр",
            .followSystem: "Как в системе", .deepBlue: "Тёмно-синий", .fogWhite: "Туманно-белый",
            .graphite: "Графит", .lavender: "Лавандовый", .glass: "Стекло",
            .softSolid: "Мягкий", .minimal: "Минимализм"
        ]
    ]

    static func text(_ key: Key, language: AppLanguage) -> String {
        strings[language]?[key] ?? strings[.english]?[key] ?? key.rawValue
    }

    static func text(_ preset: DashboardColorPreset, language: AppLanguage) -> String {
        let key: Key
        switch preset {
        case .followSystem: key = .followSystem
        case .deepBlue: key = .deepBlue
        case .fogWhite: key = .fogWhite
        case .graphite: key = .graphite
        case .lavender: key = .lavender
        }
        return text(key, language: language)
    }

    static func text(_ style: DashboardVisualStyle, language: AppLanguage) -> String {
        let key: Key
        switch style {
        case .glass: key = .glass
        case .softSolid: key = .softSolid
        case .minimal: key = .minimal
        }
        return text(key, language: language)
    }
}

struct DashboardAppearanceSettingsSection: View {
    @ObservedObject private var settings = DashboardAppearanceSettings.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private var language: AppLanguage { languageSettings.language }
    private var theme: DashboardTheme {
        DashboardTheme(settings: settings, systemColorScheme: systemColorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppearanceCopy.text(.preview, language: language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DashboardAppearancePreview()

            Text(AppearanceCopy.text(.palette, language: language))
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 7) {
                ForEach(DashboardColorPreset.allCases) { preset in
                    presetButton(preset)
                }
            }

            Text(AppearanceCopy.text(.style, language: language))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(DashboardVisualStyle.allCases) { style in
                    styleButton(style)
                }
            }

            HStack(spacing: 14) {
                ColorPicker(
                    AppearanceCopy.text(.accent, language: language),
                    selection: Binding(
                        get: { settings.customAccent ?? theme.accent },
                        set: { settings.setCustomAccent($0) }
                    ),
                    supportsOpacity: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                if settings.customAccentHex != nil {
                    Button(AppearanceCopy.text(.usePreset, language: language)) {
                        settings.clearCustomAccent()
                    }
                    .buttonStyle(.link)
                }
            }

            HStack {
                Spacer()
                Button(AppearanceCopy.text(.restore, language: language)) {
                    settings.restoreDefaults()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }

    private func presetButton(_ preset: DashboardColorPreset) -> some View {
        let sample = DashboardTheme(
            preset: preset,
            style: settings.style,
            customAccent: nil,
            systemColorScheme: systemColorScheme
        )
        let selected = settings.preset == preset
        return Button {
            settings.preset = preset
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sample.background)
                    .overlay(alignment: .bottomLeading) {
                        Capsule()
                            .fill(sample.accent)
                            .frame(width: 30, height: 6)
                            .padding(7)
                    }
                    .frame(height: 29)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.primary.opacity(0.15), lineWidth: 1)
                    )
                Text(AppearanceCopy.text(preset, language: language))
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func styleButton(_ style: DashboardVisualStyle) -> some View {
        let selected = settings.style == style
        let symbol: String
        switch style {
        case .glass: symbol = "square.on.square"
        case .softSolid: symbol = "rectangle.fill"
        case .minimal: symbol = "rectangle"
        }
        return Button {
            settings.style = style
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(AppearanceCopy.text(style, language: language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct DashboardAppearancePreview: View {
    @ObservedObject private var settings = DashboardAppearanceSettings.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private var theme: DashboardTheme {
        DashboardTheme(settings: settings, systemColorScheme: systemColorScheme)
    }

    var body: some View {
        ZStack {
            theme.background
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    BrandPulseMark()
                        .frame(width: 24, height: 24)
                    Text("AI Usage Bar")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Circle().fill(theme.success).frame(width: 6, height: 6)
                    Text(L10n.text(.localDataConnected, language: languageSettings.language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.text(0.62))
                }

                HStack(spacing: 7) {
                    Text(L10n.periodTitle("today", language: languageSettings.language))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.accent.opacity(theme.isDark ? 0.20 : 0.13), in: Capsule())
                    Text(L10n.periodTitle("thisWeek", language: languageSettings.language))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.text(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(5)
                .dashboardSurface(tint: theme.accent.opacity(0.10), cornerRadius: 12)

                HStack(spacing: 9) {
                    ProviderLogo(provider: .codex, size: 25, fallbackColor: .blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Codex")
                            .font(.system(size: 12, weight: .bold))
                        Text(L10n.text(.input, language: languageSettings.language))
                            .font(.system(size: 10))
                            .foregroundStyle(theme.text(0.58))
                    }
                    Spacer()
                    Text("12.8K")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.ink)
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 30, height: 5)
                }
                .padding(10)
                .dashboardSurface(tint: Color.blue.opacity(0.14), cornerRadius: 15)
            }
            .padding(12)
        }
        .frame(height: 166)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(16), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius(16), style: .continuous)
                .stroke(theme.edge, lineWidth: 1)
        )
        .environment(\.dashboardTheme, theme)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}
