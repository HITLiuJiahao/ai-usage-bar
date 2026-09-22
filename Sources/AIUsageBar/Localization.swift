import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"

    var id: String { rawValue }

    /// Keep language names in their native form so the selector stays easy
    /// to understand even before the user changes the app language.
    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portugueseBrazil: return "Português (Brasil)"
        case .russian: return "Русский"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()

    private static let defaultsKey = "aiUsageBar.appLanguage"

    @Published private(set) var language: AppLanguage

    private init() {
        language = Self.currentLanguage
    }

    static var currentLanguage: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: rawValue)
        else {
            // The existing UI is Simplified Chinese, so keep that as the
            // first-launch default instead of following the Mac locale.
            return .simplifiedChinese
        }
        return language
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        self.language = language
    }
}

enum L10n {
    enum Key: String, Hashable {
        case overviewTitle
        case overviewSubtitle
        case updated
        case reading
        case localDataConnected
        case waitingForData
        case accountSettings
        case refreshNow
        case refreshEvery30Seconds
        case updating
        case retryLater
        case firstRead
        case localFirst
        case sourceFootnote
        case noUsageInPeriod
        case openFullOverview
        case balance
        case localActivity
        case usageRange
        case models
        case noUsage
        case noMetric
        case resetAt
        case plan
        case byModel
        case noModelDetails
        case estimatedCost
        case cacheHit
        case input
        case output
        case cacheRead
        case cacheWrite
        case reasoning
        case requests
        case sessions
        case credits
        case activeTime
        case quota
        case remaining
        case remainingQuota
        case subscriptionQuota
        case historical
        case dataRead
        case partialData
        case cachedHistory
        case noData
        case syncing
        case retry
        case update
        case immediateUpdate
        case softwareUpdate
        case softwareUpdateHelp
        case checkForUpdates
        case updateAvailable
        case installUpdate
        case checkingForUpdates
        case downloadingUpdate
        case installingUpdate
        case upToDate
        case currentVersion
        case appSettings
        case launchAtLogin
        case loginStatusEnabled
        case loginStatusPending
        case loginStatusUnavailable
        case loginStatusDisabled
        case loginStatusUnknown
        case openSystemSettings
        case configuredAccounts
        case noManualAccounts
        case product
        case accountName
        case accessToken
        case addAccount
        case addServerAccount
        case credentialsFooter
        case sidebarOrder
        case sidebarOrderHelp
        case sidebarExpansion
        case sidebarExpansionHelp
        case sidebarExpansionRight
        case sidebarExpansionLeft
        case sidebarExpansionBoth
        case sidebarExpansionDisabled
        case dragToReorder
        case restoreDefault
        case moveUp
        case moveDown
        case language
        case languageHelp
        case settingsWindowTitle
        case menuRefresh
        case menuDashboard
        case menuSettings
        case menuQuit
        case token
        case inputOutput
        case today
        case yesterday
        case thisWeek
        case lastWeek
        case thisMonth
        case lastMonth
        case thisYear
        case fiveHours
        case daily
        case weekly
        case billing
        case availableCredits
        case resetCreditsAvailable
        case resetCreditsExpiresAt
        case subscriptionCredits
        case addOnCredits
        case sharedCredits
        case fiveHourQuota
        case weeklyQuota
        case dailyQuota
        case monthlyQuota
        case lastMonthQuota
        case requestUnit
        case sessionUnit
        case itemUnit
        case minuteUnit
        case unknownModel
        case usageUnavailable
        case currentAccount
        case accountUnit
    }

    private static let translations: [AppLanguage: [Key: String]] = [
        .simplifiedChinese: [
            .overviewTitle: "AI 使用概览",
            .overviewSubtitle: "Token、模型、用量、桌面宠物等特性",
            .updated: "更新",
            .reading: "正在读取",
            .localDataConnected: "本机 AI 数据已接入",
            .waitingForData: "等待本机数据",
            .accountSettings: "账户设置",
            .refreshNow: "立即刷新",
            .refreshEvery30Seconds: "每 30 秒自动刷新",
            .updating: "更新中",
            .retryLater: "稍后重试",
            .firstRead: "首次读取中",
            .localFirst: "本机优先",
            .sourceFootnote: "Token/额度按实际来源；成本仅对有 Token 与价格表的数据估算",
            .noUsageInPeriod: "本时段未检测到使用",
            .openFullOverview: "打开完整概览",
            .balance: "余额",
            .localActivity: "本地活动",
            .usageRange: "统计范围",
            .models: "模型",
            .noUsage: "暂时没有可显示的用量",
            .noMetric: "暂时没有可显示的指标",
            .resetAt: "重置于",
            .plan: "plan",
            .byModel: "按模型",
            .noModelDetails: "暂无可识别的模型明细",
            .estimatedCost: "成本估算",
            .cacheHit: "缓存命中",
            .input: "输入",
            .output: "输出",
            .cacheRead: "缓存读",
            .cacheWrite: "缓存写",
            .reasoning: "推理",
            .requests: "请求",
            .sessions: "会话",
            .credits: "Credits",
            .activeTime: "活跃时长",
            .quota: "额度",
            .remaining: "余",
            .remainingQuota: "剩余额度",
            .subscriptionQuota: "订阅额度",
            .historical: "历史",
            .dataRead: "数据已正常读取",
            .partialData: "部分数据可用",
            .cachedHistory: "目标应用当前未运行，显示最近一次成功读取的历史用量",
            .noData: "暂未读取到数据",
            .syncing: "同步中",
            .retry: "重试",
            .update: "更新",
            .immediateUpdate: "立即更新本机用量",
            .softwareUpdate: "软件更新",
            .softwareUpdateHelp: "启动时自动检查 GitHub Releases；有新版本时可直接下载、校验并重启应用。",
            .checkForUpdates: "检查更新",
            .updateAvailable: "发现新版本",
            .installUpdate: "下载并安装",
            .checkingForUpdates: "正在检查更新…",
            .downloadingUpdate: "正在下载更新…",
            .installingUpdate: "正在安装更新…",
            .upToDate: "已是最新版本",
            .currentVersion: "当前版本",
            .appSettings: "应用设置",
            .launchAtLogin: "开机自启",
            .loginStatusEnabled: "已启用",
            .loginStatusPending: "等待系统确认",
            .loginStatusUnavailable: "当前应用位置不可用",
            .loginStatusDisabled: "未启用",
            .loginStatusUnknown: "状态未知",
            .openSystemSettings: "打开系统设置…",
            .configuredAccounts: "已配置账户",
            .noManualAccounts: "还没有手动添加的账户。",
            .product: "产品",
            .accountName: "账户名称",
            .accessToken: "API Key / Access Token",
            .addAccount: "添加账户",
            .addServerAccount: "添加服务端账户",
            .credentialsFooter: "Codex 当前登录态会自动读取；QwenWork 的订阅 Credits 来自官方账户接口，本地日志补充请求和模型明细。需要读取官方额度时，可将 Access Token 保存到 macOS 钥匙串。",
            .sidebarOrder: "侧边栏 AI 工具顺序",
            .sidebarOrderHelp: "侧边栏和完整概览会按照这里的顺序显示。拖动工具，或使用右侧箭头调整位置。",
            .sidebarExpansion: "侧边栏展开位置",
            .sidebarExpansionHelp: "选择侧边栏从桌面哪一侧展开。选择“不允许侧边栏”后，点击菜单栏图标会直接打开完整概览。",
            .sidebarExpansionRight: "桌面右侧展开",
            .sidebarExpansionLeft: "桌面左侧展开",
            .sidebarExpansionBoth: "两侧均可展开",
            .sidebarExpansionDisabled: "不允许侧边栏",
            .dragToReorder: "拖动工具调整显示顺序",
            .restoreDefault: "恢复默认",
            .moveUp: "上移",
            .moveDown: "下移",
            .language: "语言",
            .languageHelp: "选择应用界面语言；修改后立即生效，并会在下次启动时保留。",
            .settingsWindowTitle: "AI Usage Bar 设置",
            .menuRefresh: "刷新用量",
            .menuDashboard: "打开完整概览",
            .menuSettings: "账户设置…",
            .menuQuit: "退出 AI Usage Bar",
            .token: "Token",
            .inputOutput: "输入 / 输出",
            .today: "今日",
            .yesterday: "昨日",
            .thisWeek: "本周",
            .lastWeek: "上周",
            .thisMonth: "本月",
            .lastMonth: "上月",
            .thisYear: "本年",
            .fiveHours: "5 小时",
            .daily: "每日",
            .weekly: "本周",
            .billing: "订阅周期",
            .availableCredits: "可用 Credits",
            .resetCreditsAvailable: "可用重置卡",
            .resetCreditsExpiresAt: "最早过期",
            .subscriptionCredits: "订阅 Credits",
            .addOnCredits: "加购 Credits",
            .sharedCredits: "共享 Credits",
            .fiveHourQuota: "5 小时额度",
            .weeklyQuota: "周额度",
            .dailyQuota: "每日额度",
            .monthlyQuota: "月度额度",
            .lastMonthQuota: "上月额度",
            .requestUnit: "次",
            .sessionUnit: "个",
            .itemUnit: "个",
            .minuteUnit: "分钟",
            .unknownModel: "未知",
            .usageUnavailable: "暂未读取到可用用量",
            .currentAccount: "当前账户",
            .accountUnit: "个账户"
        ],
        .english: [
            .overviewTitle: "AI Usage Overview",
            .overviewSubtitle: "tokens, models, usage, desktop pet, and more",
            .updated: "Updated",
            .reading: "Reading",
            .localDataConnected: "Local AI data connected",
            .waitingForData: "Waiting for local data",
            .accountSettings: "Account Settings",
            .refreshNow: "Refresh Now",
            .refreshEvery30Seconds: "Auto-refreshes every 30 seconds",
            .updating: "Updating",
            .retryLater: "Retry later",
            .firstRead: "Reading for the first time",
            .localFirst: "Local first",
            .sourceFootnote: "Tokens/quotas use their actual sources; costs are estimated only when tokens and prices are available",
            .noUsageInPeriod: "No usage detected in this period",
            .openFullOverview: "Open Full Overview",
            .balance: "Balance",
            .localActivity: "Local Activity",
            .usageRange: "Usage Range",
            .models: "Models",
            .noUsage: "No usage to display",
            .noMetric: "No metrics to display",
            .resetAt: "Resets",
            .plan: "plan",
            .byModel: "By Model",
            .noModelDetails: "No recognizable model details",
            .estimatedCost: "Estimated Cost",
            .cacheHit: "Cache Hit",
            .input: "Input",
            .output: "Output",
            .cacheRead: "Cache Read",
            .cacheWrite: "Cache Write",
            .reasoning: "Reasoning",
            .requests: "Requests",
            .sessions: "Sessions",
            .credits: "Credits",
            .activeTime: "Active Time",
            .quota: "Quota",
            .remaining: "Remaining",
            .remainingQuota: "Remaining Quota",
            .subscriptionQuota: "Subscription Quota",
            .historical: "History",
            .dataRead: "Data read successfully",
            .partialData: "Some data available",
            .cachedHistory: "The target app is not running; showing the last successful usage snapshot",
            .noData: "No data read yet",
            .syncing: "Syncing",
            .retry: "Retry",
            .update: "Update",
            .immediateUpdate: "Update local usage now",
            .softwareUpdate: "Software Update",
            .softwareUpdateHelp: "Checks GitHub Releases at launch. New versions can be downloaded, verified, and installed with an automatic restart.",
            .checkForUpdates: "Check for Updates",
            .updateAvailable: "Update Available",
            .installUpdate: "Download and Install",
            .checkingForUpdates: "Checking for updates…",
            .downloadingUpdate: "Downloading update…",
            .installingUpdate: "Installing update…",
            .upToDate: "You're up to date",
            .currentVersion: "Current version",
            .appSettings: "App Settings",
            .launchAtLogin: "Launch at Login",
            .loginStatusEnabled: "Enabled",
            .loginStatusPending: "Waiting for system approval",
            .loginStatusUnavailable: "App location is unavailable",
            .loginStatusDisabled: "Disabled",
            .loginStatusUnknown: "Unknown status",
            .openSystemSettings: "Open System Settings…",
            .configuredAccounts: "Configured Accounts",
            .noManualAccounts: "No manually added accounts.",
            .product: "Product",
            .accountName: "Account Name",
            .accessToken: "API Key / Access Token",
            .addAccount: "Add Account",
            .addServerAccount: "Add Server Account",
            .credentialsFooter: "Codex sign-in is read automatically; QwenWork subscription Credits come from its official account API, while local logs provide request and model details. Save an Access Token in the macOS Keychain when official quota access is needed.",
            .sidebarOrder: "Sidebar AI Tool Order",
            .sidebarOrderHelp: "The sidebar and full overview use this order. Drag a tool or use the arrows to reposition it.",
            .sidebarExpansion: "Sidebar Expansion",
            .sidebarExpansionHelp: "Choose which desktop edge can open the sidebar. When the sidebar is disabled, clicking the menu bar icon opens the full overview directly.",
            .sidebarExpansionRight: "Expand from the right edge",
            .sidebarExpansionLeft: "Expand from the left edge",
            .sidebarExpansionBoth: "Allow both sides",
            .sidebarExpansionDisabled: "Disable the sidebar",
            .dragToReorder: "Drag to reorder tools",
            .restoreDefault: "Restore Default",
            .moveUp: "Move Up",
            .moveDown: "Move Down",
            .language: "Language",
            .languageHelp: "Choose the app interface language. Changes apply immediately and are kept for the next launch.",
            .settingsWindowTitle: "AI Usage Bar Settings",
            .menuRefresh: "Refresh Usage",
            .menuDashboard: "Open Full Overview",
            .menuSettings: "Account Settings…",
            .menuQuit: "Quit AI Usage Bar",
            .token: "Token",
            .inputOutput: "Input / Output",
            .today: "Today",
            .yesterday: "Yesterday",
            .thisWeek: "This Week",
            .lastWeek: "Last Week",
            .thisMonth: "This Month",
            .lastMonth: "Last Month",
            .thisYear: "This Year",
            .fiveHours: "5 Hours",
            .daily: "Daily",
            .weekly: "This Week",
            .billing: "Billing Cycle",
            .availableCredits: "Available Credits",
            .resetCreditsAvailable: "reset available",
            .resetCreditsExpiresAt: "Earliest expiry",
            .subscriptionCredits: "Subscription Credits",
            .addOnCredits: "Add-on Credits",
            .sharedCredits: "Shared Credits",
            .fiveHourQuota: "5-hour Quota",
            .weeklyQuota: "Weekly Quota",
            .dailyQuota: "Daily Quota",
            .monthlyQuota: "Monthly Quota",
            .lastMonthQuota: "Last Month's Quota",
            .requestUnit: "requests",
            .sessionUnit: "sessions",
            .itemUnit: "items",
            .minuteUnit: "min",
            .unknownModel: "Unknown",
            .usageUnavailable: "No usable usage data yet",
            .currentAccount: "Current Account",
            .accountUnit: "accounts"
        ],
        .japanese: [
            .overviewTitle: "AI 使用状況",
            .overviewSubtitle: "トークン、モデル、使用量、デスクトップペットなどの機能",
            .updated: "更新",
            .reading: "読み込み中",
            .localDataConnected: "このMacのAIデータを接続済み",
            .waitingForData: "このMacのデータを待機中",
            .accountSettings: "アカウント設定",
            .refreshNow: "今すぐ更新",
            .refreshEvery30Seconds: "30秒ごとに自動更新",
            .updating: "更新中",
            .retryLater: "後でもう一度",
            .firstRead: "初回読み込み中",
            .localFirst: "ローカル優先",
            .sourceFootnote: "トークン/クォータは実際のソースを使用し、トークンと価格表がある場合のみコストを推定",
            .noUsageInPeriod: "この期間の使用は検出されませんでした",
            .openFullOverview: "完全な概要を開く",
            .balance: "残高",
            .localActivity: "ローカルアクティビティ",
            .usageRange: "集計期間",
            .models: "モデル",
            .noUsage: "表示できる使用量はありません",
            .noMetric: "表示できる指標はありません",
            .resetAt: "リセット",
            .plan: "プラン",
            .byModel: "モデル別",
            .noModelDetails: "認識できるモデル詳細はありません",
            .estimatedCost: "推定コスト",
            .cacheHit: "キャッシュヒット",
            .input: "入力",
            .output: "出力",
            .cacheRead: "キャッシュ読み取り",
            .cacheWrite: "キャッシュ書き込み",
            .reasoning: "推論",
            .requests: "リクエスト",
            .sessions: "セッション",
            .credits: "Credits",
            .activeTime: "アクティブ時間",
            .quota: "クォータ",
            .remaining: "残り",
            .remainingQuota: "残りクォータ",
            .subscriptionQuota: "サブスクリプションクォータ",
            .historical: "履歴",
            .dataRead: "データを正常に読み込みました",
            .partialData: "一部のデータを利用できます",
            .cachedHistory: "対象アプリは実行されていないため、最後に成功した使用状況を表示しています",
            .noData: "まだデータを読み込めません",
            .syncing: "同期中",
            .retry: "再試行",
            .update: "更新",
            .immediateUpdate: "ローカル使用量を今すぐ更新",
            .softwareUpdate: "ソフトウェアアップデート",
            .softwareUpdateHelp: "起動時にGitHub Releasesを確認します。新しいバージョンはダウンロード、検証、再起動まで自動で行えます。",
            .checkForUpdates: "アップデートを確認",
            .updateAvailable: "新しいバージョン",
            .installUpdate: "ダウンロードして更新",
            .checkingForUpdates: "アップデートを確認中…",
            .downloadingUpdate: "アップデートをダウンロード中…",
            .installingUpdate: "アップデートをインストール中…",
            .upToDate: "最新バージョンです",
            .currentVersion: "現在のバージョン",
            .appSettings: "アプリ設定",
            .launchAtLogin: "ログイン時に起動",
            .loginStatusEnabled: "有効",
            .loginStatusPending: "システムの確認待ち",
            .loginStatusUnavailable: "アプリの場所を利用できません",
            .loginStatusDisabled: "無効",
            .loginStatusUnknown: "不明な状態",
            .openSystemSettings: "システム設定を開く…",
            .configuredAccounts: "設定済みアカウント",
            .noManualAccounts: "手動で追加したアカウントはありません。",
            .product: "製品",
            .accountName: "アカウント名",
            .accessToken: "API Key / Access Token",
            .addAccount: "アカウントを追加",
            .addServerAccount: "サーバーアカウントを追加",
            .credentialsFooter: "Codexのログイン状態は自動的に読み取られます。QwenWorkのCreditsは公式アカウントAPIから取得し、ローカルログでリクエストとモデル詳細を補います。公式クォータが必要な場合はAccess TokenをmacOSキーチェーンに保存してください。",
            .sidebarOrder: "サイドバー AI ツールの順序",
            .sidebarOrderHelp: "サイドバーと完全な概要はこの順序で表示されます。ドラッグまたは矢印で並べ替えます。",
            .sidebarExpansion: "サイドバーの展開位置",
            .sidebarExpansionHelp: "サイドバーを開けるデスクトップの端を選択します。「サイドバーを許可しない」を選ぶと、メニューバーアイコンをクリックして完全な概要を直接開きます。",
            .sidebarExpansionRight: "デスクトップ右側から展開",
            .sidebarExpansionLeft: "デスクトップ左側から展開",
            .sidebarExpansionBoth: "両側から展開",
            .sidebarExpansionDisabled: "サイドバーを許可しない",
            .dragToReorder: "ドラッグして並べ替え",
            .restoreDefault: "デフォルトに戻す",
            .moveUp: "上へ",
            .moveDown: "下へ",
            .language: "言語",
            .languageHelp: "アプリの表示言語を選択します。変更はすぐに反映され、次回起動時も保持されます。",
            .settingsWindowTitle: "AI Usage Bar 設定",
            .menuRefresh: "使用量を更新",
            .menuDashboard: "完全な概要を開く",
            .menuSettings: "アカウント設定…",
            .menuQuit: "AI Usage Barを終了",
            .token: "トークン",
            .inputOutput: "入力 / 出力",
            .today: "今日",
            .yesterday: "昨日",
            .thisWeek: "今週",
            .lastWeek: "先週",
            .thisMonth: "今月",
            .lastMonth: "先月",
            .thisYear: "今年",
            .fiveHours: "5時間",
            .daily: "毎日",
            .weekly: "今週",
            .billing: "請求サイクル",
            .availableCredits: "利用可能なCredits",
            .resetCreditsAvailable: "利用可能なリセット",
            .resetCreditsExpiresAt: "最短の有効期限",
            .subscriptionCredits: "サブスクリプションCredits",
            .addOnCredits: "追加Credits",
            .sharedCredits: "共有Credits",
            .fiveHourQuota: "5時間クォータ",
            .weeklyQuota: "週間クォータ",
            .dailyQuota: "日次クォータ",
            .monthlyQuota: "月間クォータ",
            .lastMonthQuota: "先月のクォータ",
            .requestUnit: "件",
            .sessionUnit: "セッション",
            .itemUnit: "件",
            .minuteUnit: "分",
            .unknownModel: "不明",
            .usageUnavailable: "まだ利用可能な使用量データがありません",
            .currentAccount: "現在のアカウント",
            .accountUnit: "アカウント"
        ],
        .korean: [
            .overviewTitle: "AI 사용량 개요",
            .overviewSubtitle: "토큰, 모델, 사용량, 데스크톱 펫 등의 기능",
            .updated: "업데이트",
            .reading: "읽는 중",
            .localDataConnected: "로컬 AI 데이터 연결됨",
            .waitingForData: "로컬 데이터 대기 중",
            .accountSettings: "계정 설정",
            .refreshNow: "지금 새로 고침",
            .refreshEvery30Seconds: "30초마다 자동 새로 고침",
            .updating: "업데이트 중",
            .retryLater: "나중에 다시 시도",
            .firstRead: "처음 읽는 중",
            .localFirst: "로컬 우선",
            .sourceFootnote: "토큰/한도는 실제 출처를 사용하며 토큰과 가격표가 있을 때만 비용을 추정합니다",
            .noUsageInPeriod: "이 기간에 사용량이 감지되지 않았습니다",
            .openFullOverview: "전체 개요 열기",
            .balance: "잔액",
            .localActivity: "로컬 활동",
            .usageRange: "집계 기간",
            .models: "모델",
            .noUsage: "표시할 사용량이 없습니다",
            .noMetric: "표시할 지표가 없습니다",
            .resetAt: "재설정",
            .plan: "플랜",
            .byModel: "모델별",
            .noModelDetails: "인식 가능한 모델 세부 정보가 없습니다",
            .estimatedCost: "예상 비용",
            .cacheHit: "캐시 적중",
            .input: "입력",
            .output: "출력",
            .cacheRead: "캐시 읽기",
            .cacheWrite: "캐시 쓰기",
            .reasoning: "추론",
            .requests: "요청",
            .sessions: "세션",
            .credits: "Credits",
            .activeTime: "활성 시간",
            .quota: "한도",
            .remaining: "남음",
            .remainingQuota: "남은 한도",
            .subscriptionQuota: "구독 한도",
            .historical: "기록",
            .dataRead: "데이터를 정상적으로 읽었습니다",
            .partialData: "일부 데이터를 사용할 수 있습니다",
            .cachedHistory: "대상 앱이 실행 중이 아니므로 마지막으로 성공한 사용량을 표시합니다",
            .noData: "아직 데이터를 읽지 못했습니다",
            .syncing: "동기화 중",
            .retry: "다시 시도",
            .update: "업데이트",
            .immediateUpdate: "로컬 사용량 지금 업데이트",
            .softwareUpdate: "소프트웨어 업데이트",
            .softwareUpdateHelp: "시작할 때 GitHub Releases를 확인합니다. 새 버전은 다운로드, 검증, 재시작까지 자동으로 진행할 수 있습니다.",
            .checkForUpdates: "업데이트 확인",
            .updateAvailable: "새 버전 있음",
            .installUpdate: "다운로드 및 설치",
            .checkingForUpdates: "업데이트 확인 중…",
            .downloadingUpdate: "업데이트 다운로드 중…",
            .installingUpdate: "업데이트 설치 중…",
            .upToDate: "최신 버전입니다",
            .currentVersion: "현재 버전",
            .appSettings: "앱 설정",
            .launchAtLogin: "로그인 시 실행",
            .loginStatusEnabled: "활성화됨",
            .loginStatusPending: "시스템 승인 대기 중",
            .loginStatusUnavailable: "앱 위치를 사용할 수 없음",
            .loginStatusDisabled: "비활성화됨",
            .loginStatusUnknown: "알 수 없는 상태",
            .openSystemSettings: "시스템 설정 열기…",
            .configuredAccounts: "구성된 계정",
            .noManualAccounts: "수동으로 추가한 계정이 없습니다.",
            .product: "제품",
            .accountName: "계정 이름",
            .accessToken: "API Key / Access Token",
            .addAccount: "계정 추가",
            .addServerAccount: "서버 계정 추가",
            .credentialsFooter: "Codex 로그인 상태는 자동으로 읽습니다. QwenWork 구독 Credits는 공식 계정 API에서 가져오며, 로컬 로그로 요청과 모델 세부 정보를 보완합니다. 공식 한도를 읽으려면 Access Token을 macOS 키체인에 저장하세요.",
            .sidebarOrder: "사이드바 AI 도구 순서",
            .sidebarOrderHelp: "사이드바와 전체 개요가 이 순서로 표시됩니다. 도구를 드래그하거나 화살표로 이동하세요.",
            .sidebarExpansion: "사이드바 펼치기 위치",
            .sidebarExpansionHelp: "사이드바를 열 수 있는 데스크톱 가장자리를 선택합니다. 사이드바를 허용하지 않으면 메뉴 막대 아이콘을 클릭할 때 전체 개요가 바로 열립니다.",
            .sidebarExpansionRight: "데스크톱 오른쪽에서 펼치기",
            .sidebarExpansionLeft: "데스크톱 왼쪽에서 펼치기",
            .sidebarExpansionBoth: "양쪽에서 펼치기",
            .sidebarExpansionDisabled: "사이드바 허용 안 함",
            .dragToReorder: "드래그하여 순서 변경",
            .restoreDefault: "기본값 복원",
            .moveUp: "위로 이동",
            .moveDown: "아래로 이동",
            .language: "언어",
            .languageHelp: "앱 인터페이스 언어를 선택합니다. 변경 사항은 즉시 적용되고 다음 실행에도 유지됩니다.",
            .settingsWindowTitle: "AI Usage Bar 설정",
            .menuRefresh: "사용량 새로 고침",
            .menuDashboard: "전체 개요 열기",
            .menuSettings: "계정 설정…",
            .menuQuit: "AI Usage Bar 종료",
            .token: "토큰",
            .inputOutput: "입력 / 출력",
            .today: "오늘",
            .yesterday: "어제",
            .thisWeek: "이번 주",
            .lastWeek: "지난 주",
            .thisMonth: "이번 달",
            .lastMonth: "지난 달",
            .thisYear: "올해",
            .fiveHours: "5시간",
            .daily: "매일",
            .weekly: "이번 주",
            .billing: "청구 주기",
            .availableCredits: "사용 가능한 Credits",
            .resetCreditsAvailable: "사용 가능한 재설정",
            .resetCreditsExpiresAt: "가장 빠른 만료",
            .subscriptionCredits: "구독 Credits",
            .addOnCredits: "추가 Credits",
            .sharedCredits: "공유 Credits",
            .fiveHourQuota: "5시간 한도",
            .weeklyQuota: "주간 한도",
            .dailyQuota: "일일 한도",
            .monthlyQuota: "월간 한도",
            .lastMonthQuota: "지난달 한도",
            .requestUnit: "회",
            .sessionUnit: "세션",
            .itemUnit: "개",
            .minuteUnit: "분",
            .unknownModel: "알 수 없음",
            .usageUnavailable: "사용 가능한 사용량 데이터가 아직 없습니다",
            .currentAccount: "현재 계정",
            .accountUnit: "계정"
        ]
    ]

    // The original four locales remain above for backwards compatibility.
    // Keep the additional locales in a separate table so adding languages
    // does not risk changing existing translations.
    private static let additionalTranslations: [AppLanguage: [Key: String]] = [
        .traditionalChinese: [
            .overviewTitle: "AI 使用概覽",
            .overviewSubtitle: "Token、模型、用量、桌面寵物等功能",
            .updated: "更新",
            .reading: "讀取中",
            .localDataConnected: "已連接本機 AI 資料",
            .waitingForData: "等待本機資料",
            .accountSettings: "帳戶設定",
            .refreshNow: "立即重新整理",
            .refreshEvery30Seconds: "每 30 秒自動重新整理",
            .updating: "更新中",
            .retryLater: "稍後重試",
            .firstRead: "首次讀取中",
            .localFirst: "本機優先",
            .sourceFootnote: "Token/額度使用實際來源；只有在有 Token 與價格表時才估算成本",
            .noUsageInPeriod: "此時段未偵測到使用量",
            .openFullOverview: "開啟完整概覽",
            .balance: "餘額",
            .localActivity: "本機活動",
            .usageRange: "統計範圍",
            .models: "模型",
            .noUsage: "沒有可顯示的用量",
            .noMetric: "沒有可顯示的指標",
            .resetAt: "重設於",
            .plan: "方案",
            .byModel: "依模型",
            .noModelDetails: "沒有可辨識的模型明細",
            .estimatedCost: "預估成本",
            .cacheHit: "快取命中",
            .input: "輸入",
            .output: "輸出",
            .cacheRead: "快取讀取",
            .cacheWrite: "快取寫入",
            .reasoning: "推理",
            .requests: "請求",
            .sessions: "工作階段",
            .credits: "Credits",
            .activeTime: "活躍時間",
            .quota: "額度",
            .remaining: "剩餘",
            .remainingQuota: "剩餘額度",
            .subscriptionQuota: "訂閱額度",
            .historical: "歷史",
            .dataRead: "資料讀取成功",
            .partialData: "部分資料可用",
            .cachedHistory: "目標應用程式目前未執行；顯示最近一次成功讀取的用量快照",
            .noData: "尚未讀取資料",
            .syncing: "同步中",
            .retry: "重試",
            .update: "更新",
            .immediateUpdate: "立即更新本機用量",
            .softwareUpdate: "軟體更新",
            .softwareUpdateHelp: "啟動時自動檢查 GitHub Releases；有新版本可直接下載、驗證並重新啟動應用程式。",
            .checkForUpdates: "檢查更新",
            .updateAvailable: "有可用更新",
            .installUpdate: "下載並安裝",
            .checkingForUpdates: "正在檢查更新…",
            .downloadingUpdate: "正在下載更新…",
            .installingUpdate: "正在安裝更新…",
            .upToDate: "已是最新版本",
            .currentVersion: "目前版本",
            .appSettings: "應用程式設定",
            .launchAtLogin: "登入時啟動",
            .loginStatusEnabled: "已啟用",
            .loginStatusPending: "等待系統確認",
            .loginStatusUnavailable: "目前應用程式位置不可用",
            .loginStatusDisabled: "未啟用",
            .loginStatusUnknown: "狀態未知",
            .openSystemSettings: "開啟系統設定…",
            .configuredAccounts: "已設定帳戶",
            .noManualAccounts: "尚未手動新增帳戶。",
            .product: "產品",
            .accountName: "帳戶名稱",
            .accessToken: "API Key / Access Token",
            .addAccount: "新增帳戶",
            .addServerAccount: "新增伺服器帳戶",
            .credentialsFooter: "Codex 登入狀態會自動讀取；QwenWork 訂閱 Credits 來自官方帳戶 API，本機記錄補充請求與模型明細。需要讀取官方額度時，可將 Access Token 儲存至 macOS 鑰匙圈。",
            .sidebarOrder: "側邊欄 AI 工具順序",
            .sidebarOrderHelp: "側邊欄與完整概覽會依照這裡的順序顯示。拖曳工具或使用箭頭調整位置。",
            .sidebarExpansion: "側邊欄展開位置",
            .sidebarExpansionHelp: "選擇側邊欄從桌面的哪一側展開。選擇不允許側邊欄後，點擊選單列圖示會直接開啟完整概覽。",
            .sidebarExpansionRight: "從桌面右側展開",
            .sidebarExpansionLeft: "從桌面左側展開",
            .sidebarExpansionBoth: "兩側皆可展開",
            .sidebarExpansionDisabled: "不允許側邊欄",
            .dragToReorder: "拖曳工具調整顯示順序",
            .restoreDefault: "恢復預設",
            .moveUp: "上移",
            .moveDown: "下移",
            .language: "語言",
            .languageHelp: "選擇應用程式介面語言；修改後立即生效，並會在下次啟動時保留。",
            .settingsWindowTitle: "AI Usage Bar 設定",
            .menuRefresh: "重新整理用量",
            .menuDashboard: "開啟完整概覽",
            .menuSettings: "帳戶設定…",
            .menuQuit: "結束 AI Usage Bar",
            .token: "Token",
            .inputOutput: "輸入 / 輸出",
            .today: "今天",
            .yesterday: "昨天",
            .thisWeek: "本週",
            .lastWeek: "上週",
            .thisMonth: "本月",
            .lastMonth: "上月",
            .thisYear: "今年",
            .fiveHours: "5 小時",
            .daily: "每日",
            .weekly: "本週",
            .billing: "訂閱週期",
            .availableCredits: "可用 Credits",
            .resetCreditsAvailable: "可用重設卡",
            .resetCreditsExpiresAt: "最早到期",
            .subscriptionCredits: "訂閱 Credits",
            .addOnCredits: "加購 Credits",
            .sharedCredits: "共用 Credits",
            .fiveHourQuota: "5 小時額度",
            .weeklyQuota: "每週額度",
            .dailyQuota: "每日額度",
            .monthlyQuota: "每月額度",
            .lastMonthQuota: "上月額度",
            .requestUnit: "次",
            .sessionUnit: "個工作階段",
            .itemUnit: "個",
            .minuteUnit: "分鐘",
            .unknownModel: "未知",
            .usageUnavailable: "尚未讀取到可用用量",
            .currentAccount: "目前帳戶",
            .accountUnit: "個帳戶"
        ],
        .spanish: [
            .overviewTitle: "Resumen de uso de IA",
            .overviewSubtitle: "tokens, modelos, uso, mascota de escritorio y más",
            .updated: "Actualizado",
            .reading: "Leyendo",
            .localDataConnected: "Datos locales de IA conectados",
            .waitingForData: "Esperando datos locales",
            .accountSettings: "Configuración de cuentas",
            .refreshNow: "Actualizar ahora",
            .refreshEvery30Seconds: "Se actualiza automáticamente cada 30 segundos",
            .updating: "Actualizando",
            .retryLater: "Reintentar más tarde",
            .firstRead: "Primera lectura en curso",
            .localFirst: "Prioridad local",
            .sourceFootnote: "Los tokens y las cuotas usan sus fuentes reales; el coste solo se estima cuando hay tokens y precios disponibles",
            .noUsageInPeriod: "No se detectó uso en este periodo",
            .openFullOverview: "Abrir resumen completo",
            .balance: "Saldo",
            .localActivity: "Actividad local",
            .usageRange: "Periodo de uso",
            .models: "Modelos",
            .noUsage: "No hay uso que mostrar",
            .noMetric: "No hay métricas que mostrar",
            .resetAt: "Se restablece",
            .plan: "plan",
            .byModel: "Por modelo",
            .noModelDetails: "No hay detalles de modelo reconocibles",
            .estimatedCost: "Coste estimado",
            .cacheHit: "Aciertos de caché",
            .input: "Entrada",
            .output: "Salida",
            .cacheRead: "Lectura de caché",
            .cacheWrite: "Escritura de caché",
            .reasoning: "Razonamiento",
            .requests: "Solicitudes",
            .sessions: "Sesiones",
            .credits: "Credits",
            .activeTime: "Tiempo activo",
            .quota: "Cuota",
            .remaining: "Restante",
            .remainingQuota: "Cuota restante",
            .subscriptionQuota: "Cuota de suscripción",
            .historical: "Historial",
            .dataRead: "Datos leídos correctamente",
            .partialData: "Hay algunos datos disponibles",
            .cachedHistory: "La aplicación de destino no está abierta; se muestra la última lectura correcta de uso",
            .noData: "Todavía no se han leído datos",
            .syncing: "Sincronizando",
            .retry: "Reintentar",
            .update: "Actualizar",
            .immediateUpdate: "Actualizar el uso local ahora",
            .softwareUpdate: "Actualización de software",
            .softwareUpdateHelp: "Comprueba GitHub Releases al iniciar. Las nuevas versiones se pueden descargar, verificar e instalar con reinicio automático.",
            .checkForUpdates: "Buscar actualizaciones",
            .updateAvailable: "Actualización disponible",
            .installUpdate: "Descargar e instalar",
            .checkingForUpdates: "Buscando actualizaciones…",
            .downloadingUpdate: "Descargando actualización…",
            .installingUpdate: "Instalando actualización…",
            .upToDate: "Tienes la versión más reciente",
            .currentVersion: "Versión actual",
            .appSettings: "Configuración de la aplicación",
            .launchAtLogin: "Abrir al iniciar sesión",
            .loginStatusEnabled: "Activado",
            .loginStatusPending: "Esperando la aprobación del sistema",
            .loginStatusUnavailable: "La ubicación de la aplicación no está disponible",
            .loginStatusDisabled: "Desactivado",
            .loginStatusUnknown: "Estado desconocido",
            .openSystemSettings: "Abrir Ajustes del Sistema…",
            .configuredAccounts: "Cuentas configuradas",
            .noManualAccounts: "No hay cuentas añadidas manualmente.",
            .product: "Producto",
            .accountName: "Nombre de la cuenta",
            .accessToken: "API Key / Access Token",
            .addAccount: "Añadir cuenta",
            .addServerAccount: "Añadir cuenta de servidor",
            .credentialsFooter: "El inicio de sesión de Codex se lee automáticamente; los Credits de suscripción de QwenWork proceden de su API oficial y los registros locales aportan las solicitudes y los modelos. Guarda un Access Token en el Llavero de macOS cuando necesites consultar la cuota oficial.",
            .sidebarOrder: "Orden de herramientas de IA",
            .sidebarOrderHelp: "La barra lateral y el resumen completo usan este orden. Arrastra una herramienta o usa las flechas para moverla.",
            .sidebarExpansion: "Expansión de la barra lateral",
            .sidebarExpansionHelp: "Elige desde qué borde del escritorio puede abrirse la barra lateral. Si se desactiva, al hacer clic en el icono de la barra de menús se abre directamente el resumen completo.",
            .sidebarExpansionRight: "Expandir desde el borde derecho",
            .sidebarExpansionLeft: "Expandir desde el borde izquierdo",
            .sidebarExpansionBoth: "Permitir ambos lados",
            .sidebarExpansionDisabled: "Desactivar la barra lateral",
            .dragToReorder: "Arrastra para reordenar las herramientas",
            .restoreDefault: "Restaurar valores por defecto",
            .moveUp: "Subir",
            .moveDown: "Bajar",
            .language: "Idioma",
            .languageHelp: "Elige el idioma de la interfaz. El cambio se aplica al instante y se conserva para el próximo inicio.",
            .settingsWindowTitle: "Ajustes de AI Usage Bar",
            .menuRefresh: "Actualizar uso",
            .menuDashboard: "Abrir resumen completo",
            .menuSettings: "Configuración de cuentas…",
            .menuQuit: "Salir de AI Usage Bar",
            .token: "Token",
            .inputOutput: "Entrada / salida",
            .today: "Hoy",
            .yesterday: "Ayer",
            .thisWeek: "Esta semana",
            .lastWeek: "La semana pasada",
            .thisMonth: "Este mes",
            .lastMonth: "El mes pasado",
            .thisYear: "Este año",
            .fiveHours: "5 horas",
            .daily: "Diario",
            .weekly: "Esta semana",
            .billing: "Ciclo de facturación",
            .availableCredits: "Credits disponibles",
            .resetCreditsAvailable: "reinicios disponibles",
            .resetCreditsExpiresAt: "Caducidad más próxima",
            .subscriptionCredits: "Credits de suscripción",
            .addOnCredits: "Credits adicionales",
            .sharedCredits: "Credits compartidos",
            .fiveHourQuota: "Cuota de 5 horas",
            .weeklyQuota: "Cuota semanal",
            .dailyQuota: "Cuota diaria",
            .monthlyQuota: "Cuota mensual",
            .lastMonthQuota: "Cuota del mes pasado",
            .requestUnit: "solicitudes",
            .sessionUnit: "sesiones",
            .itemUnit: "elementos",
            .minuteUnit: "min",
            .unknownModel: "Desconocido",
            .usageUnavailable: "Aún no hay datos de uso disponibles",
            .currentAccount: "Cuenta actual",
            .accountUnit: "cuentas"
        ],
        .french: [
            .overviewTitle: "Aperçu de l’utilisation de l’IA",
            .overviewSubtitle: "tokens, modèles, utilisation, compagnon de bureau et plus",
            .updated: "Mis à jour",
            .reading: "Lecture",
            .localDataConnected: "Données IA locales connectées",
            .waitingForData: "En attente des données locales",
            .accountSettings: "Réglages des comptes",
            .refreshNow: "Actualiser maintenant",
            .refreshEvery30Seconds: "Actualisation automatique toutes les 30 secondes",
            .updating: "Mise à jour",
            .retryLater: "Réessayer plus tard",
            .firstRead: "Première lecture en cours",
            .localFirst: "Local en priorité",
            .sourceFootnote: "Les tokens et quotas utilisent leurs sources réelles ; le coût est estimé uniquement lorsque les tokens et les prix sont disponibles",
            .noUsageInPeriod: "Aucune utilisation détectée pendant cette période",
            .openFullOverview: "Ouvrir l’aperçu complet",
            .balance: "Solde",
            .localActivity: "Activité locale",
            .usageRange: "Période d’utilisation",
            .models: "Modèles",
            .noUsage: "Aucune utilisation à afficher",
            .noMetric: "Aucune métrique à afficher",
            .resetAt: "Réinitialisation",
            .plan: "forfait",
            .byModel: "Par modèle",
            .noModelDetails: "Aucun détail de modèle identifiable",
            .estimatedCost: "Coût estimé",
            .cacheHit: "Succès du cache",
            .input: "Entrée",
            .output: "Sortie",
            .cacheRead: "Lecture du cache",
            .cacheWrite: "Écriture du cache",
            .reasoning: "Raisonnement",
            .requests: "Requêtes",
            .sessions: "Sessions",
            .credits: "Credits",
            .activeTime: "Temps actif",
            .quota: "Quota",
            .remaining: "Restant",
            .remainingQuota: "Quota restant",
            .subscriptionQuota: "Quota d’abonnement",
            .historical: "Historique",
            .dataRead: "Données lues correctement",
            .partialData: "Certaines données sont disponibles",
            .cachedHistory: "L’application cible n’est pas ouverte ; affichage de la dernière lecture d’utilisation réussie",
            .noData: "Aucune donnée lue pour le moment",
            .syncing: "Synchronisation",
            .retry: "Réessayer",
            .update: "Mettre à jour",
            .immediateUpdate: "Mettre à jour l’utilisation locale",
            .softwareUpdate: "Mise à jour logicielle",
            .softwareUpdateHelp: "Vérifie GitHub Releases au démarrage. Les nouvelles versions peuvent être téléchargées, vérifiées et installées avec redémarrage automatique.",
            .checkForUpdates: "Rechercher les mises à jour",
            .updateAvailable: "Mise à jour disponible",
            .installUpdate: "Télécharger et installer",
            .checkingForUpdates: "Recherche de mises à jour…",
            .downloadingUpdate: "Téléchargement de la mise à jour…",
            .installingUpdate: "Installation de la mise à jour…",
            .upToDate: "Vous utilisez la dernière version",
            .currentVersion: "Version actuelle",
            .appSettings: "Réglages de l’application",
            .launchAtLogin: "Ouvrir à la connexion",
            .loginStatusEnabled: "Activé",
            .loginStatusPending: "En attente de l’autorisation du système",
            .loginStatusUnavailable: "L’emplacement de l’application est indisponible",
            .loginStatusDisabled: "Désactivé",
            .loginStatusUnknown: "État inconnu",
            .openSystemSettings: "Ouvrir les réglages système…",
            .configuredAccounts: "Comptes configurés",
            .noManualAccounts: "Aucun compte ajouté manuellement.",
            .product: "Produit",
            .accountName: "Nom du compte",
            .accessToken: "API Key / Access Token",
            .addAccount: "Ajouter un compte",
            .addServerAccount: "Ajouter un compte serveur",
            .credentialsFooter: "La connexion Codex est lue automatiquement ; les Credits d’abonnement QwenWork proviennent de son API officielle et les journaux locaux fournissent les requêtes et les modèles. Enregistrez un Access Token dans le trousseau macOS pour consulter le quota officiel.",
            .sidebarOrder: "Ordre des outils IA",
            .sidebarOrderHelp: "La barre latérale et l’aperçu complet utilisent cet ordre. Faites glisser un outil ou utilisez les flèches pour le déplacer.",
            .sidebarExpansion: "Ouverture de la barre latérale",
            .sidebarExpansionHelp: "Choisissez depuis quel bord du bureau la barre latérale peut s’ouvrir. Lorsqu’elle est désactivée, cliquer sur l’icône de la barre des menus ouvre directement l’aperçu complet.",
            .sidebarExpansionRight: "Ouvrir depuis le bord droit",
            .sidebarExpansionLeft: "Ouvrir depuis le bord gauche",
            .sidebarExpansionBoth: "Autoriser les deux côtés",
            .sidebarExpansionDisabled: "Désactiver la barre latérale",
            .dragToReorder: "Faites glisser pour réordonner les outils",
            .restoreDefault: "Rétablir les valeurs par défaut",
            .moveUp: "Monter",
            .moveDown: "Descendre",
            .language: "Langue",
            .languageHelp: "Choisissez la langue de l’interface. Le changement est immédiat et conservé au prochain démarrage.",
            .settingsWindowTitle: "Réglages d’AI Usage Bar",
            .menuRefresh: "Actualiser l’utilisation",
            .menuDashboard: "Ouvrir l’aperçu complet",
            .menuSettings: "Réglages des comptes…",
            .menuQuit: "Quitter AI Usage Bar",
            .token: "Token",
            .inputOutput: "Entrée / sortie",
            .today: "Aujourd’hui",
            .yesterday: "Hier",
            .thisWeek: "Cette semaine",
            .lastWeek: "La semaine dernière",
            .thisMonth: "Ce mois-ci",
            .lastMonth: "Le mois dernier",
            .thisYear: "Cette année",
            .fiveHours: "5 heures",
            .daily: "Quotidien",
            .weekly: "Cette semaine",
            .billing: "Cycle de facturation",
            .availableCredits: "Credits disponibles",
            .resetCreditsAvailable: "réinitialisations disponibles",
            .resetCreditsExpiresAt: "Expiration la plus proche",
            .subscriptionCredits: "Credits d’abonnement",
            .addOnCredits: "Credits supplémentaires",
            .sharedCredits: "Credits partagés",
            .fiveHourQuota: "Quota de 5 heures",
            .weeklyQuota: "Quota hebdomadaire",
            .dailyQuota: "Quota quotidien",
            .monthlyQuota: "Quota mensuel",
            .lastMonthQuota: "Quota du mois dernier",
            .requestUnit: "requêtes",
            .sessionUnit: "sessions",
            .itemUnit: "éléments",
            .minuteUnit: "min",
            .unknownModel: "Inconnu",
            .usageUnavailable: "Aucune donnée d’utilisation disponible pour le moment",
            .currentAccount: "Compte actuel",
            .accountUnit: "comptes"
        ],
        .german: [
            .overviewTitle: "KI-Nutzungsübersicht",
            .overviewSubtitle: "Tokens, Modelle, Nutzung, Desktop-Haustier und mehr",
            .updated: "Aktualisiert",
            .reading: "Wird gelesen",
            .localDataConnected: "Lokale KI-Daten verbunden",
            .waitingForData: "Warten auf lokale Daten",
            .accountSettings: "Kontoeinstellungen",
            .refreshNow: "Jetzt aktualisieren",
            .refreshEvery30Seconds: "Automatische Aktualisierung alle 30 Sekunden",
            .updating: "Wird aktualisiert",
            .retryLater: "Später erneut versuchen",
            .firstRead: "Erster Abruf läuft",
            .localFirst: "Lokal zuerst",
            .sourceFootnote: "Tokens und Quoten verwenden ihre tatsächlichen Quellen; Kosten werden nur bei verfügbaren Tokens und Preisen geschätzt",
            .noUsageInPeriod: "In diesem Zeitraum wurde keine Nutzung erkannt",
            .openFullOverview: "Vollständige Übersicht öffnen",
            .balance: "Guthaben",
            .localActivity: "Lokale Aktivität",
            .usageRange: "Nutzungszeitraum",
            .models: "Modelle",
            .noUsage: "Keine Nutzung zum Anzeigen",
            .noMetric: "Keine Messwerte zum Anzeigen",
            .resetAt: "Zurücksetzung",
            .plan: "Tarif",
            .byModel: "Nach Modell",
            .noModelDetails: "Keine erkennbaren Modelldetails",
            .estimatedCost: "Geschätzte Kosten",
            .cacheHit: "Cache-Treffer",
            .input: "Eingabe",
            .output: "Ausgabe",
            .cacheRead: "Cache-Lesen",
            .cacheWrite: "Cache-Schreiben",
            .reasoning: "Reasoning",
            .requests: "Anfragen",
            .sessions: "Sitzungen",
            .credits: "Credits",
            .activeTime: "Aktive Zeit",
            .quota: "Kontingent",
            .remaining: "Verbleibend",
            .remainingQuota: "Verbleibendes Kontingent",
            .subscriptionQuota: "Abo-Kontingent",
            .historical: "Verlauf",
            .dataRead: "Daten erfolgreich gelesen",
            .partialData: "Einige Daten verfügbar",
            .cachedHistory: "Die Ziel-App läuft nicht; der letzte erfolgreiche Nutzungsstand wird angezeigt",
            .noData: "Noch keine Daten gelesen",
            .syncing: "Synchronisierung",
            .retry: "Erneut versuchen",
            .update: "Aktualisieren",
            .immediateUpdate: "Lokale Nutzung jetzt aktualisieren",
            .softwareUpdate: "Softwareupdate",
            .softwareUpdateHelp: "Prüft beim Start die GitHub Releases. Neue Versionen können heruntergeladen, verifiziert und automatisch installiert werden.",
            .checkForUpdates: "Nach Updates suchen",
            .updateAvailable: "Update verfügbar",
            .installUpdate: "Herunterladen und installieren",
            .checkingForUpdates: "Suche nach Updates…",
            .downloadingUpdate: "Update wird geladen…",
            .installingUpdate: "Update wird installiert…",
            .upToDate: "Du verwendest die neueste Version",
            .currentVersion: "Aktuelle Version",
            .appSettings: "App-Einstellungen",
            .launchAtLogin: "Beim Anmelden öffnen",
            .loginStatusEnabled: "Aktiviert",
            .loginStatusPending: "Warten auf Systemfreigabe",
            .loginStatusUnavailable: "App-Standort ist nicht verfügbar",
            .loginStatusDisabled: "Deaktiviert",
            .loginStatusUnknown: "Unbekannter Status",
            .openSystemSettings: "Systemeinstellungen öffnen…",
            .configuredAccounts: "Konfigurierte Konten",
            .noManualAccounts: "Keine manuell hinzugefügten Konten.",
            .product: "Produkt",
            .accountName: "Kontoname",
            .accessToken: "API Key / Access Token",
            .addAccount: "Konto hinzufügen",
            .addServerAccount: "Serverkonto hinzufügen",
            .credentialsFooter: "Die Codex-Anmeldung wird automatisch gelesen. QwenWork-Abo-Credits stammen aus der offiziellen Konto-API; lokale Protokolle liefern Anfragen und Modelldetails. Speichere bei Bedarf ein Access Token im macOS-Schlüsselbund.",
            .sidebarOrder: "Reihenfolge der KI-Werkzeuge",
            .sidebarOrderHelp: "Seitenleiste und vollständige Übersicht verwenden diese Reihenfolge. Ziehe ein Werkzeug oder nutze die Pfeile zum Verschieben.",
            .sidebarExpansion: "Seitenleiste öffnen",
            .sidebarExpansionHelp: "Wähle, an welcher Desktop-Kante die Seitenleiste geöffnet werden kann. Bei deaktivierter Seitenleiste öffnet ein Klick auf das Menüleistensymbol direkt die vollständige Übersicht.",
            .sidebarExpansionRight: "Am rechten Rand öffnen",
            .sidebarExpansionLeft: "Am linken Rand öffnen",
            .sidebarExpansionBoth: "Beide Seiten erlauben",
            .sidebarExpansionDisabled: "Seitenleiste deaktivieren",
            .dragToReorder: "Ziehen, um Werkzeuge zu sortieren",
            .restoreDefault: "Standard wiederherstellen",
            .moveUp: "Nach oben",
            .moveDown: "Nach unten",
            .language: "Sprache",
            .languageHelp: "Wähle die Sprache der App-Oberfläche. Die Änderung gilt sofort und bleibt beim nächsten Start erhalten.",
            .settingsWindowTitle: "AI Usage Bar Einstellungen",
            .menuRefresh: "Nutzung aktualisieren",
            .menuDashboard: "Vollständige Übersicht öffnen",
            .menuSettings: "Kontoeinstellungen…",
            .menuQuit: "AI Usage Bar beenden",
            .token: "Token",
            .inputOutput: "Eingabe / Ausgabe",
            .today: "Heute",
            .yesterday: "Gestern",
            .thisWeek: "Diese Woche",
            .lastWeek: "Letzte Woche",
            .thisMonth: "Dieser Monat",
            .lastMonth: "Letzter Monat",
            .thisYear: "Dieses Jahr",
            .fiveHours: "5 Stunden",
            .daily: "Täglich",
            .weekly: "Diese Woche",
            .billing: "Abrechnungszeitraum",
            .availableCredits: "Verfügbare Credits",
            .resetCreditsAvailable: "verfügbare Zurücksetzungen",
            .resetCreditsExpiresAt: "Frühester Ablauf",
            .subscriptionCredits: "Abo-Credits",
            .addOnCredits: "Zusätzliche Credits",
            .sharedCredits: "Geteilte Credits",
            .fiveHourQuota: "5-Stunden-Kontingent",
            .weeklyQuota: "Wöchentliches Kontingent",
            .dailyQuota: "Tägliches Kontingent",
            .monthlyQuota: "Monatliches Kontingent",
            .lastMonthQuota: "Kontingent des letzten Monats",
            .requestUnit: "Anfragen",
            .sessionUnit: "Sitzungen",
            .itemUnit: "Elemente",
            .minuteUnit: "Min.",
            .unknownModel: "Unbekannt",
            .usageUnavailable: "Noch keine nutzbaren Nutzungsdaten",
            .currentAccount: "Aktuelles Konto",
            .accountUnit: "Konten"
        ],
        .italian: [
            .overviewTitle: "Panoramica dell’uso dell’IA",
            .overviewSubtitle: "token, modelli, utilizzo, mascotte desktop e altro",
            .updated: "Aggiornato",
            .reading: "Lettura",
            .localDataConnected: "Dati IA locali collegati",
            .waitingForData: "In attesa dei dati locali",
            .accountSettings: "Impostazioni account",
            .refreshNow: "Aggiorna ora",
            .refreshEvery30Seconds: "Aggiornamento automatico ogni 30 secondi",
            .updating: "Aggiornamento",
            .retryLater: "Riprova più tardi",
            .firstRead: "Prima lettura in corso",
            .localFirst: "Prima i dati locali",
            .sourceFootnote: "Token e quote usano le fonti reali; il costo viene stimato solo quando sono disponibili token e prezzi",
            .noUsageInPeriod: "Nessun utilizzo rilevato in questo periodo",
            .openFullOverview: "Apri panoramica completa",
            .balance: "Saldo",
            .localActivity: "Attività locale",
            .usageRange: "Periodo di utilizzo",
            .models: "Modelli",
            .noUsage: "Nessun utilizzo da mostrare",
            .noMetric: "Nessuna metrica da mostrare",
            .resetAt: "Reimpostazione",
            .plan: "piano",
            .byModel: "Per modello",
            .noModelDetails: "Nessun dettaglio modello riconoscibile",
            .estimatedCost: "Costo stimato",
            .cacheHit: "Cache hit",
            .input: "Input",
            .output: "Output",
            .cacheRead: "Lettura cache",
            .cacheWrite: "Scrittura cache",
            .reasoning: "Ragionamento",
            .requests: "Richieste",
            .sessions: "Sessioni",
            .credits: "Credits",
            .activeTime: "Tempo attivo",
            .quota: "Quota",
            .remaining: "Rimanente",
            .remainingQuota: "Quota rimanente",
            .subscriptionQuota: "Quota abbonamento",
            .historical: "Cronologia",
            .dataRead: "Dati letti correttamente",
            .partialData: "Alcuni dati disponibili",
            .cachedHistory: "L’app di destinazione non è in esecuzione; viene mostrato l’ultimo utilizzo letto correttamente",
            .noData: "Nessun dato letto finora",
            .syncing: "Sincronizzazione",
            .retry: "Riprova",
            .update: "Aggiorna",
            .immediateUpdate: "Aggiorna subito l’utilizzo locale",
            .softwareUpdate: "Aggiornamento software",
            .softwareUpdateHelp: "Controlla GitHub Releases all’avvio. Le nuove versioni possono essere scaricate, verificate e installate con riavvio automatico.",
            .checkForUpdates: "Controlla aggiornamenti",
            .updateAvailable: "Aggiornamento disponibile",
            .installUpdate: "Scarica e installa",
            .checkingForUpdates: "Controllo aggiornamenti…",
            .downloadingUpdate: "Download aggiornamento…",
            .installingUpdate: "Installazione aggiornamento…",
            .upToDate: "È installata la versione più recente",
            .currentVersion: "Versione attuale",
            .appSettings: "Impostazioni app",
            .launchAtLogin: "Apri al login",
            .loginStatusEnabled: "Attivato",
            .loginStatusPending: "In attesa dell’approvazione del sistema",
            .loginStatusUnavailable: "Posizione dell’app non disponibile",
            .loginStatusDisabled: "Disattivato",
            .loginStatusUnknown: "Stato sconosciuto",
            .openSystemSettings: "Apri Impostazioni di Sistema…",
            .configuredAccounts: "Account configurati",
            .noManualAccounts: "Nessun account aggiunto manualmente.",
            .product: "Prodotto",
            .accountName: "Nome account",
            .accessToken: "API Key / Access Token",
            .addAccount: "Aggiungi account",
            .addServerAccount: "Aggiungi account server",
            .credentialsFooter: "L’accesso Codex viene letto automaticamente; i Credits dell’abbonamento QwenWork provengono dalla sua API ufficiale e i log locali forniscono richieste e modelli. Salva un Access Token nel Portachiavi di macOS per leggere la quota ufficiale.",
            .sidebarOrder: "Ordine degli strumenti IA",
            .sidebarOrderHelp: "La barra laterale e la panoramica completa usano questo ordine. Trascina uno strumento o usa le frecce per spostarlo.",
            .sidebarExpansion: "Apertura della barra laterale",
            .sidebarExpansionHelp: "Scegli da quale bordo del desktop può aprirsi la barra laterale. Quando è disattivata, facendo clic sull’icona nella barra dei menu si apre direttamente la panoramica completa.",
            .sidebarExpansionRight: "Apri dal bordo destro",
            .sidebarExpansionLeft: "Apri dal bordo sinistro",
            .sidebarExpansionBoth: "Consenti entrambi i lati",
            .sidebarExpansionDisabled: "Disattiva barra laterale",
            .dragToReorder: "Trascina per riordinare gli strumenti",
            .restoreDefault: "Ripristina default",
            .moveUp: "Sposta su",
            .moveDown: "Sposta giù",
            .language: "Lingua",
            .languageHelp: "Scegli la lingua dell’interfaccia. La modifica è immediata e viene conservata al prossimo avvio.",
            .settingsWindowTitle: "Impostazioni di AI Usage Bar",
            .menuRefresh: "Aggiorna utilizzo",
            .menuDashboard: "Apri panoramica completa",
            .menuSettings: "Impostazioni account…",
            .menuQuit: "Esci da AI Usage Bar",
            .token: "Token",
            .inputOutput: "Input / output",
            .today: "Oggi",
            .yesterday: "Ieri",
            .thisWeek: "Questa settimana",
            .lastWeek: "La settimana scorsa",
            .thisMonth: "Questo mese",
            .lastMonth: "Il mese scorso",
            .thisYear: "Quest’anno",
            .fiveHours: "5 ore",
            .daily: "Giornaliero",
            .weekly: "Questa settimana",
            .billing: "Ciclo di fatturazione",
            .availableCredits: "Credits disponibili",
            .resetCreditsAvailable: "reimpostazioni disponibili",
            .resetCreditsExpiresAt: "Scadenza più vicina",
            .subscriptionCredits: "Credits abbonamento",
            .addOnCredits: "Credits aggiuntivi",
            .sharedCredits: "Credits condivisi",
            .fiveHourQuota: "Quota di 5 ore",
            .weeklyQuota: "Quota settimanale",
            .dailyQuota: "Quota giornaliera",
            .monthlyQuota: "Quota mensile",
            .lastMonthQuota: "Quota del mese scorso",
            .requestUnit: "richieste",
            .sessionUnit: "sessioni",
            .itemUnit: "elementi",
            .minuteUnit: "min",
            .unknownModel: "Sconosciuto",
            .usageUnavailable: "Nessun dato di utilizzo disponibile",
            .currentAccount: "Account attuale",
            .accountUnit: "account"
        ],
        .portugueseBrazil: [
            .overviewTitle: "Visão geral do uso de IA",
            .overviewSubtitle: "tokens, modelos, uso, mascote da área de trabalho e mais",
            .updated: "Atualizado",
            .reading: "Lendo",
            .localDataConnected: "Dados locais de IA conectados",
            .waitingForData: "Aguardando dados locais",
            .accountSettings: "Configurações de contas",
            .refreshNow: "Atualizar agora",
            .refreshEvery30Seconds: "Atualiza automaticamente a cada 30 segundos",
            .updating: "Atualizando",
            .retryLater: "Tentar novamente mais tarde",
            .firstRead: "Primeira leitura em andamento",
            .localFirst: "Local primeiro",
            .sourceFootnote: "Tokens e cotas usam suas fontes reais; os custos só são estimados quando há tokens e preços disponíveis",
            .noUsageInPeriod: "Nenhum uso detectado neste período",
            .openFullOverview: "Abrir visão geral completa",
            .balance: "Saldo",
            .localActivity: "Atividade local",
            .usageRange: "Período de uso",
            .models: "Modelos",
            .noUsage: "Não há uso para exibir",
            .noMetric: "Não há métricas para exibir",
            .resetAt: "Redefine em",
            .plan: "plano",
            .byModel: "Por modelo",
            .noModelDetails: "Nenhum detalhe de modelo reconhecível",
            .estimatedCost: "Custo estimado",
            .cacheHit: "Acertos de cache",
            .input: "Entrada",
            .output: "Saída",
            .cacheRead: "Leitura de cache",
            .cacheWrite: "Gravação de cache",
            .reasoning: "Raciocínio",
            .requests: "Solicitações",
            .sessions: "Sessões",
            .credits: "Credits",
            .activeTime: "Tempo ativo",
            .quota: "Cota",
            .remaining: "Restante",
            .remainingQuota: "Cota restante",
            .subscriptionQuota: "Cota da assinatura",
            .historical: "Histórico",
            .dataRead: "Dados lidos com sucesso",
            .partialData: "Alguns dados disponíveis",
            .cachedHistory: "O aplicativo de destino não está aberto; mostrando o último uso lido com sucesso",
            .noData: "Nenhum dado lido ainda",
            .syncing: "Sincronizando",
            .retry: "Tentar novamente",
            .update: "Atualizar",
            .immediateUpdate: "Atualizar o uso local agora",
            .softwareUpdate: "Atualização de software",
            .softwareUpdateHelp: "Verifica o GitHub Releases ao iniciar. Novas versões podem ser baixadas, verificadas e instaladas com reinício automático.",
            .checkForUpdates: "Verificar atualizações",
            .updateAvailable: "Atualização disponível",
            .installUpdate: "Baixar e instalar",
            .checkingForUpdates: "Verificando atualizações…",
            .downloadingUpdate: "Baixando atualização…",
            .installingUpdate: "Instalando atualização…",
            .upToDate: "Você está usando a versão mais recente",
            .currentVersion: "Versão atual",
            .appSettings: "Configurações do app",
            .launchAtLogin: "Abrir ao iniciar sessão",
            .loginStatusEnabled: "Ativado",
            .loginStatusPending: "Aguardando aprovação do sistema",
            .loginStatusUnavailable: "A localização do app não está disponível",
            .loginStatusDisabled: "Desativado",
            .loginStatusUnknown: "Status desconhecido",
            .openSystemSettings: "Abrir Ajustes do Sistema…",
            .configuredAccounts: "Contas configuradas",
            .noManualAccounts: "Nenhuma conta adicionada manualmente.",
            .product: "Produto",
            .accountName: "Nome da conta",
            .accessToken: "API Key / Access Token",
            .addAccount: "Adicionar conta",
            .addServerAccount: "Adicionar conta do servidor",
            .credentialsFooter: "O login do Codex é lido automaticamente; os Credits da assinatura do QwenWork vêm da API oficial da conta, enquanto os registros locais fornecem solicitações e modelos. Salve um Access Token nas Chaves do macOS quando precisar consultar a cota oficial.",
            .sidebarOrder: "Ordem das ferramentas de IA",
            .sidebarOrderHelp: "A barra lateral e a visão geral completa usam esta ordem. Arraste uma ferramenta ou use as setas para movê-la.",
            .sidebarExpansion: "Expansão da barra lateral",
            .sidebarExpansionHelp: "Escolha de qual borda da mesa a barra lateral pode abrir. Quando desativada, clicar no ícone da barra de menus abre diretamente a visão geral completa.",
            .sidebarExpansionRight: "Expandir pela borda direita",
            .sidebarExpansionLeft: "Expandir pela borda esquerda",
            .sidebarExpansionBoth: "Permitir os dois lados",
            .sidebarExpansionDisabled: "Desativar barra lateral",
            .dragToReorder: "Arraste para reordenar as ferramentas",
            .restoreDefault: "Restaurar padrão",
            .moveUp: "Mover para cima",
            .moveDown: "Mover para baixo",
            .language: "Idioma",
            .languageHelp: "Escolha o idioma da interface. A alteração é imediata e será mantida no próximo início.",
            .settingsWindowTitle: "Configurações do AI Usage Bar",
            .menuRefresh: "Atualizar uso",
            .menuDashboard: "Abrir visão geral completa",
            .menuSettings: "Configurações de contas…",
            .menuQuit: "Sair do AI Usage Bar",
            .token: "Token",
            .inputOutput: "Entrada / saída",
            .today: "Hoje",
            .yesterday: "Ontem",
            .thisWeek: "Esta semana",
            .lastWeek: "Semana passada",
            .thisMonth: "Este mês",
            .lastMonth: "Mês passado",
            .thisYear: "Este ano",
            .fiveHours: "5 horas",
            .daily: "Diário",
            .weekly: "Esta semana",
            .billing: "Ciclo de cobrança",
            .availableCredits: "Credits disponíveis",
            .resetCreditsAvailable: "redefinições disponíveis",
            .resetCreditsExpiresAt: "Vencimento mais próximo",
            .subscriptionCredits: "Credits da assinatura",
            .addOnCredits: "Credits adicionais",
            .sharedCredits: "Credits compartilhados",
            .fiveHourQuota: "Cota de 5 horas",
            .weeklyQuota: "Cota semanal",
            .dailyQuota: "Cota diária",
            .monthlyQuota: "Cota mensal",
            .lastMonthQuota: "Cota do mês passado",
            .requestUnit: "solicitações",
            .sessionUnit: "sessões",
            .itemUnit: "itens",
            .minuteUnit: "min",
            .unknownModel: "Desconhecido",
            .usageUnavailable: "Ainda não há dados de uso disponíveis",
            .currentAccount: "Conta atual",
            .accountUnit: "contas"
        ],
        .russian: [
            .overviewTitle: "Обзор использования ИИ",
            .overviewSubtitle: "токены, модели, использование, питомец на рабочем столе и другое",
            .updated: "Обновлено",
            .reading: "Чтение",
            .localDataConnected: "Локальные данные ИИ подключены",
            .waitingForData: "Ожидание локальных данных",
            .accountSettings: "Настройки аккаунтов",
            .refreshNow: "Обновить сейчас",
            .refreshEvery30Seconds: "Автообновление каждые 30 секунд",
            .updating: "Обновление",
            .retryLater: "Повторить позже",
            .firstRead: "Первое чтение",
            .localFirst: "Сначала локальные данные",
            .sourceFootnote: "Токены и квоты используют фактические источники; стоимость оценивается только при наличии токенов и цен",
            .noUsageInPeriod: "За этот период использование не обнаружено",
            .openFullOverview: "Открыть полный обзор",
            .balance: "Баланс",
            .localActivity: "Локальная активность",
            .usageRange: "Период использования",
            .models: "Модели",
            .noUsage: "Нет данных об использовании",
            .noMetric: "Нет показателей для отображения",
            .resetAt: "Сброс",
            .plan: "тариф",
            .byModel: "По модели",
            .noModelDetails: "Нет распознанных сведений о модели",
            .estimatedCost: "Расчётная стоимость",
            .cacheHit: "Попадания в кэш",
            .input: "Ввод",
            .output: "Вывод",
            .cacheRead: "Чтение кэша",
            .cacheWrite: "Запись кэша",
            .reasoning: "Рассуждение",
            .requests: "Запросы",
            .sessions: "Сеансы",
            .credits: "Credits",
            .activeTime: "Активное время",
            .quota: "Лимит",
            .remaining: "Осталось",
            .remainingQuota: "Оставшийся лимит",
            .subscriptionQuota: "Лимит подписки",
            .historical: "История",
            .dataRead: "Данные успешно прочитаны",
            .partialData: "Доступны некоторые данные",
            .cachedHistory: "Целевое приложение не запущено; показан последний успешно прочитанный снимок использования",
            .noData: "Данные ещё не прочитаны",
            .syncing: "Синхронизация",
            .retry: "Повторить",
            .update: "Обновить",
            .immediateUpdate: "Обновить локальное использование",
            .softwareUpdate: "Обновление ПО",
            .softwareUpdateHelp: "При запуске проверяет GitHub Releases. Новые версии можно скачать, проверить и установить с автоматическим перезапуском.",
            .checkForUpdates: "Проверить обновления",
            .updateAvailable: "Доступно обновление",
            .installUpdate: "Скачать и установить",
            .checkingForUpdates: "Проверка обновлений…",
            .downloadingUpdate: "Загрузка обновления…",
            .installingUpdate: "Установка обновления…",
            .upToDate: "Установлена последняя версия",
            .currentVersion: "Текущая версия",
            .appSettings: "Настройки приложения",
            .launchAtLogin: "Запускать при входе",
            .loginStatusEnabled: "Включено",
            .loginStatusPending: "Ожидание разрешения системы",
            .loginStatusUnavailable: "Расположение приложения недоступно",
            .loginStatusDisabled: "Выключено",
            .loginStatusUnknown: "Неизвестный статус",
            .openSystemSettings: "Открыть системные настройки…",
            .configuredAccounts: "Настроенные аккаунты",
            .noManualAccounts: "Нет аккаунтов, добавленных вручную.",
            .product: "Продукт",
            .accountName: "Имя аккаунта",
            .accessToken: "API Key / Access Token",
            .addAccount: "Добавить аккаунт",
            .addServerAccount: "Добавить серверный аккаунт",
            .credentialsFooter: "Вход в Codex считывается автоматически; Credits подписки QwenWork поступают из официального API аккаунта, а локальные журналы дополняют сведения о запросах и моделях. При необходимости сохраните Access Token в Связке ключей macOS.",
            .sidebarOrder: "Порядок инструментов ИИ",
            .sidebarOrderHelp: "Боковая панель и полный обзор используют этот порядок. Перетащите инструмент или используйте стрелки для перемещения.",
            .sidebarExpansion: "Открытие боковой панели",
            .sidebarExpansionHelp: "Выберите край рабочего стола, с которого может открываться боковая панель. Если она отключена, нажатие значка в строке меню сразу открывает полный обзор.",
            .sidebarExpansionRight: "Открывать справа",
            .sidebarExpansionLeft: "Открывать слева",
            .sidebarExpansionBoth: "Разрешить обе стороны",
            .sidebarExpansionDisabled: "Отключить боковую панель",
            .dragToReorder: "Перетащите для изменения порядка",
            .restoreDefault: "Восстановить по умолчанию",
            .moveUp: "Переместить вверх",
            .moveDown: "Переместить вниз",
            .language: "Язык",
            .languageHelp: "Выберите язык интерфейса. Изменение применяется сразу и сохраняется при следующем запуске.",
            .settingsWindowTitle: "Настройки AI Usage Bar",
            .menuRefresh: "Обновить использование",
            .menuDashboard: "Открыть полный обзор",
            .menuSettings: "Настройки аккаунтов…",
            .menuQuit: "Выйти из AI Usage Bar",
            .token: "Токен",
            .inputOutput: "Ввод / вывод",
            .today: "Сегодня",
            .yesterday: "Вчера",
            .thisWeek: "На этой неделе",
            .lastWeek: "На прошлой неделе",
            .thisMonth: "В этом месяце",
            .lastMonth: "В прошлом месяце",
            .thisYear: "В этом году",
            .fiveHours: "5 часов",
            .daily: "За день",
            .weekly: "На этой неделе",
            .billing: "Расчётный период",
            .availableCredits: "Доступные Credits",
            .resetCreditsAvailable: "доступных сбросов",
            .resetCreditsExpiresAt: "Ближайшее истечение",
            .subscriptionCredits: "Credits подписки",
            .addOnCredits: "Дополнительные Credits",
            .sharedCredits: "Общие Credits",
            .fiveHourQuota: "Лимит на 5 часов",
            .weeklyQuota: "Недельный лимит",
            .dailyQuota: "Дневной лимит",
            .monthlyQuota: "Месячный лимит",
            .lastMonthQuota: "Лимит прошлого месяца",
            .requestUnit: "запросов",
            .sessionUnit: "сеансов",
            .itemUnit: "элементов",
            .minuteUnit: "мин",
            .unknownModel: "Неизвестно",
            .usageUnavailable: "Доступные данные об использовании ещё не получены",
            .currentAccount: "Текущий аккаунт",
            .accountUnit: "аккаунта"
        ]
    ]

    static func text(_ key: Key, language: AppLanguage = AppLanguageSettings.currentLanguage) -> String {
        additionalTranslations[language]?[key]
            ?? translations[language]?[key]
            ?? translations[.english]?[key]
            ?? key.rawValue
    }

    static func timeString(
        _ date: Date,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func shortDateTimeFormatter(
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "MdHm",
            options: 0,
            locale: language.locale
        )
        return formatter
    }

    static func weekdayFormatter(
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "E"
        return formatter
    }

    static func relativeDateString(
        _ date: Date,
        relativeTo referenceDate: Date = Date(),
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func providerName(
        _ provider: ProviderID,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch provider {
        case .codex: return "Codex"
        case .kimi: return "KIMI Desktop"
        case .chatGPT: return "ChatGPT"
        case .qwenWork: return "QwenWork"
        case .zcode: return "ZCode"
        case .openCode: return "OpenCode"
        case .doubaoWork:
            switch language {
            case .simplifiedChinese: return "豆包工作"
            case .japanese: return "豆包ワーク"
            default: return "Doubao Work"
            }
        case .qianwenOffice:
            switch language {
            case .simplifiedChinese: return "千问办公模式"
            case .japanese: return "千問オフィスモード"
            case .korean: return "Qwen 오피스 모드"
            default: return "Qwen Office Mode"
            }
        case .deepSeekHarness: return "DeepSeek Harness"
        case .workBuddy: return "WorkBuddy"
        case .miniMax: return "MiniMax Code"
        }
    }

    static func periodTitle(
        _ rawValue: String,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let key: Key
        switch rawValue {
        case "today": key = .today
        case "yesterday": key = .yesterday
        case "thisWeek": key = .thisWeek
        case "lastWeek": key = .lastWeek
        case "thisMonth": key = .thisMonth
        case "lastMonth": key = .lastMonth
        case "thisYear": key = .thisYear
        default: return rawValue
        }
        return text(key, language: language)
    }

    static func windowTitle(
        _ window: UsageWindow,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch window {
        case .today: return text(.today, language: language)
        case .yesterday: return text(.yesterday, language: language)
        case .fiveHours: return text(.fiveHours, language: language)
        case .daily: return text(.daily, language: language)
        case .weekly: return text(.weekly, language: language)
        case .lastWeek: return text(.lastWeek, language: language)
        case .monthly: return text(.thisMonth, language: language)
        case .lastMonth: return text(.lastMonth, language: language)
        case .yearly: return text(.thisYear, language: language)
        case .billing: return text(.billing, language: language)
        }
    }

    static func stateTitle(
        _ state: ProviderState,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch state {
        case .connected:
            switch language {
            case .simplifiedChinese: return "已连接"
            case .english: return "Connected"
            case .japanese: return "接続済み"
            case .korean: return "연결됨"
            case .traditionalChinese: return "已連接"
            case .spanish: return "Conectado"
            case .french: return "Connecté"
            case .german: return "Verbunden"
            case .italian: return "Connesso"
            case .portugueseBrazil: return "Conectado"
            case .russian: return "Подключено"
            default: return "Connected"
            }
        case .partial:
            switch language {
            case .simplifiedChinese: return "部分可用"
            case .english: return "Partially Available"
            case .japanese: return "一部利用可能"
            case .korean: return "일부 사용 가능"
            case .traditionalChinese: return "部分可用"
            case .spanish: return "Parcialmente disponible"
            case .french: return "Partiellement disponible"
            case .german: return "Teilweise verfügbar"
            case .italian: return "Parzialmente disponibile"
            case .portugueseBrazil: return "Parcialmente disponível"
            case .russian: return "Доступно частично"
            default: return "Partially Available"
            }
        case .cached:
            switch language {
            case .simplifiedChinese: return "历史数据"
            case .english: return "Historical Data"
            case .japanese: return "履歴データ"
            case .korean: return "기록 데이터"
            case .traditionalChinese: return "歷史資料"
            case .spanish: return "Datos históricos"
            case .french: return "Données historiques"
            case .german: return "Verlaufsdaten"
            case .italian: return "Dati storici"
            case .portugueseBrazil: return "Dados históricos"
            case .russian: return "Исторические данные"
            default: return "Historical Data"
            }
        case .unavailable:
            switch language {
            case .simplifiedChinese: return "暂不可用"
            case .english: return "Unavailable"
            case .japanese: return "利用不可"
            case .korean: return "사용할 수 없음"
            case .traditionalChinese: return "暫不可用"
            case .spanish: return "No disponible"
            case .french: return "Indisponible"
            case .german: return "Nicht verfügbar"
            case .italian: return "Non disponibile"
            case .portugueseBrazil: return "Indisponível"
            case .russian: return "Недоступно"
            default: return "Unavailable"
            }
        }
    }

    static func sourceTitle(
        _ source: DataSource,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch source {
        case .server:
            switch language {
            case .simplifiedChinese: return "服务端"
            case .japanese: return "サーバー"
            case .korean: return "서버"
            case .english: return "Server"
            case .traditionalChinese: return "伺服器"
            case .spanish: return "Servidor"
            case .french: return "Serveur"
            case .german: return "Server"
            case .italian: return "Server"
            case .portugueseBrazil: return "Servidor"
            case .russian: return "Сервер"
            default: return "Server"
            }
        case .local:
            switch language {
            case .simplifiedChinese: return "本地日志"
            case .japanese: return "ローカルログ"
            case .korean: return "로컬 로그"
            case .english: return "Local Logs"
            case .traditionalChinese: return "本機記錄"
            case .spanish: return "Registros locales"
            case .french: return "Journaux locaux"
            case .german: return "Lokale Protokolle"
            case .italian: return "Log locali"
            case .portugueseBrazil: return "Registros locais"
            case .russian: return "Локальные журналы"
            default: return "Local Logs"
            }
        case .cached:
            switch language {
            case .simplifiedChinese: return "本机缓存"
            case .japanese: return "ローカルキャッシュ"
            case .korean: return "로컬 캐시"
            case .english: return "Local Cache"
            case .traditionalChinese: return "本機快取"
            case .spanish: return "Caché local"
            case .french: return "Cache local"
            case .german: return "Lokaler Cache"
            case .italian: return "Cache locale"
            case .portugueseBrazil: return "Cache local"
            case .russian: return "Локальный кэш"
            default: return "Local Cache"
            }
        case .unavailable:
            switch language {
            case .simplifiedChinese: return "未读取"
            case .japanese: return "未読み込み"
            case .korean: return "읽지 못함"
            case .english: return "Not Read"
            case .traditionalChinese: return "未讀取"
            case .spanish: return "No leído"
            case .french: return "Non lu"
            case .german: return "Nicht gelesen"
            case .italian: return "Non letto"
            case .portugueseBrazil: return "Não lido"
            case .russian: return "Не прочитано"
            default: return "Not Read"
            }
        }
    }

    static func metricTitle(
        _ metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let key = metric.key.lowercased()
        if key.contains("kimi-membership-monthly") {
            switch language {
            case .simplifiedChinese: return "KIMI · 月度额度"
            case .english: return "KIMI · Monthly quota"
            case .japanese: return "KIMI · 月間クォータ"
            case .korean: return "KIMI · 월간 한도"
            case .traditionalChinese: return "KIMI · 月度額度"
            case .spanish: return "KIMI · Cuota mensual"
            case .french: return "KIMI · Quota mensuel"
            case .german: return "KIMI · Monatskontingent"
            case .italian: return "KIMI · Quota mensile"
            case .portugueseBrazil: return "KIMI · Cota mensal"
            case .russian: return "KIMI · Месячный лимит"
            default: return "KIMI · Monthly quota"
            }
        }
        if key.contains("kimi-code-5h") {
            switch language {
            case .simplifiedChinese: return "Kimi Code · 5 小时额度"
            case .english: return "Kimi Code · 5-hour quota"
            case .japanese: return "Kimi Code · 5時間クォータ"
            case .korean: return "Kimi Code · 5시간 한도"
            case .traditionalChinese: return "Kimi Code · 5 小時額度"
            case .spanish: return "Kimi Code · Cuota de 5 horas"
            case .french: return "Kimi Code · Quota de 5 heures"
            case .german: return "Kimi Code · 5-Stunden-Kontingent"
            case .italian: return "Kimi Code · Quota di 5 ore"
            case .portugueseBrazil: return "Kimi Code · Cota de 5 horas"
            case .russian: return "Kimi Code · Лимит на 5 часов"
            default: return "Kimi Code · 5-hour quota"
            }
        }
        if key.contains("kimi-code-7d") {
            switch language {
            case .simplifiedChinese: return "Kimi Code · 7 天额度"
            case .english: return "Kimi Code · 7-day quota"
            case .japanese: return "Kimi Code · 7日クォータ"
            case .korean: return "Kimi Code · 7일 한도"
            case .traditionalChinese: return "Kimi Code · 7 天額度"
            case .spanish: return "Kimi Code · Cuota de 7 días"
            case .french: return "Kimi Code · Quota de 7 jours"
            case .german: return "Kimi Code · 7-Tage-Kontingent"
            case .italian: return "Kimi Code · Quota di 7 giorni"
            case .portugueseBrazil: return "Kimi Code · Cota de 7 dias"
            case .russian: return "Kimi Code · Лимит на 7 дней"
            default: return "Kimi Code · 7-day quota"
            }
        }
        if metric.kind == .credits {
            if key == "codex-credits" { return text(.availableCredits, language: language) }
            return text(.credits, language: language)
        }
        if metric.unit.localizedCaseInsensitiveContains("credit") {
            if key.contains("add-on") || key.contains("add_on") {
                return text(.addOnCredits, language: language)
            }
            if key.contains("shared") || key.contains("org_resource") {
                return text(.sharedCredits, language: language)
            }
            return text(.subscriptionCredits, language: language)
        }
        if key.contains("token-breakdown") { return text(.inputOutput, language: language) }
        if key.contains("cache") { return text(.cacheRead, language: language) }
        if key.contains("requests") { return text(.requests, language: language) }
        if key.contains("sessions") { return text(.sessions, language: language) }
        if key.contains("active") { return text(.activeTime, language: language) }
        if key.contains("cost") { return text(.estimatedCost, language: language) }

        switch metric.kind {
        case .tokens: return text(.token, language: language)
        case .requests: return text(.requests, language: language)
        case .duration: return text(.activeTime, language: language)
        case .money: return text(.estimatedCost, language: language)
        case .quota:
            switch metric.window {
            case .fiveHours: return text(.fiveHourQuota, language: language)
            case .weekly, .lastWeek: return text(.weeklyQuota, language: language)
            case .daily, .today: return text(.dailyQuota, language: language)
            case .monthly, .billing: return text(.monthlyQuota, language: language)
            case .lastMonth: return text(.lastMonthQuota, language: language)
            case .yesterday, .yearly: return text(.quota, language: language)
            }
        case .credits: return text(.credits, language: language)
        }
    }

    static func balanceTitle(
        for metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        if metric.key.lowercased().contains("kimi-") {
            return metricTitle(metric, language: language)
        }
        if metric.unit.localizedCaseInsensitiveContains("credit") {
            return metricTitle(metric, language: language)
        }
        switch metric.window {
        case .weekly, .lastWeek: return text(.weeklyQuota, language: language)
        case .fiveHours: return text(.fiveHourQuota, language: language)
        case .daily, .today: return text(.dailyQuota, language: language)
        case .billing, .monthly: return text(.subscriptionQuota, language: language)
        case .lastMonth: return text(.lastMonthQuota, language: language)
        default: return text(.balance, language: language)
        }
    }

    static func edgeQuotaTitle(
        for metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        if metric.key.lowercased().contains("kimi-") {
            return metricTitle(metric, language: language)
        }
        switch metric.window {
        case .fiveHours: return text(.fiveHours, language: language)
        case .weekly, .lastWeek:
            switch language {
            case .simplifiedChinese: return "7 天"
            case .japanese: return "7日"
            case .korean: return "7일"
            case .english: return "7 Days"
            case .traditionalChinese: return "7 天"
            case .spanish: return "7 días"
            case .french: return "7 jours"
            case .german: return "7 Tage"
            case .italian: return "7 giorni"
            case .portugueseBrazil: return "7 dias"
            case .russian: return "7 дней"
            default: return "7 Days"
            }
        case .daily, .today: return text(.daily, language: language)
        case .billing, .monthly: return language == .simplifiedChinese ? "订阅" : text(.subscriptionQuota, language: language)
            default: return metricTitle(metric, language: language)
        }
    }

    static func remainingLabel(
        for metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let title = edgeQuotaTitle(for: metric, language: language)
        switch language {
        case .simplifiedChinese: return "\(title)剩余"
        case .english: return "\(title) Remaining"
        case .japanese: return "\(title)残り"
        case .korean: return "\(title) 남음"
        case .traditionalChinese: return "剩餘\(title)"
        case .spanish: return "\(title) restante"
        case .french: return "\(title) restant"
        case .german: return "\(title) verbleibend"
        case .italian: return "\(title) rimanente"
        case .portugueseBrazil: return "\(title) restante"
        case .russian: return "Осталось: \(title)"
        default: return "\(title) Remaining"
        }
    }

    static func remainingText(
        for metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        if metric.unit == "%", let remaining = metric.remaining {
            return "\(NumberFormat.compact(remaining, language: language))%"
        }
        if let remaining = metric.remaining {
            return "\(NumberFormat.compact(remaining, language: language)) \(localizedUnit(metric.unit, language: language))"
        }
        return "—"
    }

    static func resetCreditsAvailableText(
        count: Int,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let count = max(count, 0)
        switch language {
        case .simplifiedChinese:
            return "\(text(.resetCreditsAvailable, language: language)) \(count) 张"
        case .english:
            return "\(count) \(text(.resetCreditsAvailable, language: language))"
        case .japanese:
            return "\(text(.resetCreditsAvailable, language: language)) \(count) 枚"
        case .korean:
            return "\(text(.resetCreditsAvailable, language: language)) \(count)개"
        default:
            return "\(count) \(text(.resetCreditsAvailable, language: .english))"
        }
    }

    static func usedText(
        for metric: UsageMetric,
        currencyUnit: String,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        guard let used = metric.used else { return "—" }
        if metric.kind == .money {
            return NumberFormat.currency(used, unit: currencyUnit, language: language)
        }
        let unit = localizedUnit(metric.unit, language: language)
        return "\(NumberFormat.compact(used, language: language))\(unit.isEmpty ? "" : " \(unit)")"
    }

    static func updateFailureText(
        _ failure: AppUpdateFailure,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch failure {
        case .noRelease:
            switch language {
            case .simplifiedChinese: return "暂时没有正式发布版本"
            case .english: return "No public release is available yet"
            case .japanese: return "公開リリースはまだありません"
            case .korean: return "아직 공개 릴리스가 없습니다"
            default: return "No public release is available yet"
            }
        case .network(let issue):
            return updateNetworkFailureText(issue, language: language)
        case .invalidMetadata:
            switch language {
            case .simplifiedChinese: return "更新信息不完整或更新包不受支持"
            case .english: return "The update metadata or package is incomplete"
            case .japanese: return "アップデート情報またはパッケージが不完全です"
            case .korean: return "업데이트 정보 또는 패키지가 완전하지 않습니다"
            default: return "The update metadata or package is incomplete"
            }
        case .untrustedURL:
            switch language {
            case .simplifiedChinese: return "更新地址不受信任，已停止安装"
            case .english: return "The update URL was not trusted, so installation stopped"
            case .japanese: return "信頼できない更新URLのため、インストールを停止しました"
            case .korean: return "신뢰할 수 없는 업데이트 주소라 설치를 중단했습니다"
            default: return "The update URL was not trusted, so installation stopped"
            }
        case .missingChecksum:
            switch language {
            case .simplifiedChinese: return "更新包缺少 SHA-256 校验信息"
            case .english: return "The update package has no SHA-256 checksum"
            case .japanese: return "アップデートパッケージにSHA-256チェックサムがありません"
            case .korean: return "업데이트 패키지에 SHA-256 체크섬이 없습니다"
            default: return "The update package has no SHA-256 checksum"
            }
        case .checksumMismatch:
            switch language {
            case .simplifiedChinese: return "更新包校验失败，已停止安装"
            case .english: return "The update checksum did not match, so installation stopped"
            case .japanese: return "アップデートのチェックサムが一致しないため、インストールを停止しました"
            case .korean: return "업데이트 체크섬이 일치하지 않아 설치를 중단했습니다"
            default: return "The update checksum did not match, so installation stopped"
            }
        case .invalidPackage:
            switch language {
            case .simplifiedChinese: return "更新包不是有效的 AI Usage Bar 应用"
            case .english: return "The package is not a valid AI Usage Bar app"
            case .japanese: return "有効なAI Usage Barアプリパッケージではありません"
            case .korean: return "유효한 AI Usage Bar 앱 패키지가 아닙니다"
            default: return "The package is not a valid AI Usage Bar app"
            }
        case .appLocationUnavailable:
            switch language {
            case .simplifiedChinese: return "应用所在位置不可写，请将 App 放入 Applications 后重试"
            case .english: return "The app location is not writable. Move the app to Applications and try again"
            case .japanese: return "アプリの場所に書き込めません。Applicationsに移動して再試行してください"
            case .korean: return "앱 위치에 쓸 수 없습니다. Applications로 옮긴 후 다시 시도하세요"
            default: return "The app location is not writable. Move the app to Applications and try again"
            }
        case .installation:
            switch language {
            case .simplifiedChinese: return "准备安装更新失败，原应用保持不变"
            case .english: return "The update could not be prepared; the current app was left unchanged"
            case .japanese: return "アップデートの準備に失敗しました。現在のアプリは変更されていません"
            case .korean: return "업데이트 준비에 실패했습니다. 현재 앱은 변경되지 않았습니다"
            default: return "The update could not be prepared; the current app was left unchanged"
            }
        }
    }

    private static func updateNetworkFailureText(
        _ issue: AppUpdateNetworkIssue,
        language: AppLanguage
    ) -> String {
        let text: (zh: String, en: String, ja: String, ko: String)
        switch issue {
        case .offline:
            text = (
                "当前没有可用网络连接",
                "No network connection is available",
                "ネットワーク接続が利用できません",
                "사용 가능한 네트워크 연결이 없습니다"
            )
        case .dns:
            text = (
                "无法解析 GitHub 域名，请检查 DNS、网络或代理",
                "GitHub's domain could not be resolved. Check DNS, network, or proxy settings",
                "GitHubのドメインを解決できません。DNS、ネットワーク、またはプロキシを確認してください",
                "GitHub 도메인을 확인할 수 없습니다. DNS, 네트워크 또는 프록시를 확인하세요"
            )
        case .connection:
            text = (
                "无法建立到 GitHub 的连接，请检查网络或 Clash/代理",
                "Could not connect to GitHub. Check your network or proxy",
                "GitHubに接続できません。ネットワークまたはプロキシを確認してください",
                "GitHub에 연결할 수 없습니다. 네트워크 또는 프록시를 확인하세요"
            )
        case .timeout:
            text = (
                "连接 GitHub 超时，请检查网络或代理",
                "The GitHub connection timed out. Check your network or proxy",
                "GitHubへの接続がタイムアウトしました。ネットワークまたはプロキシを確認してください",
                "GitHub 연결 시간이 초과되었습니다. 네트워크 또는 프록시를 확인하세요"
            )
        case .secureConnection:
            text = (
                "GitHub 安全连接验证失败，请检查代理或系统时间",
                "GitHub's secure connection could not be verified. Check your proxy or system time",
                "GitHubの安全な接続を検証できません。プロキシまたはシステム時刻を確認してください",
                "GitHub 보안 연결을 확인할 수 없습니다. 프록시 또는 시스템 시간을 확인하세요"
            )
        case .rateLimited:
            text = (
                "GitHub API 暂时限流，请稍后再试",
                "GitHub's API is temporarily rate-limited. Try again shortly",
                "GitHub APIが一時的にレート制限されています。しばらくしてから再試行してください",
                "GitHub API가 일시적으로 속도 제한되었습니다. 잠시 후 다시 시도하세요"
            )
        case .httpStatus(let status):
            text = (
                "GitHub 返回 HTTP \(status)",
                "GitHub returned HTTP \(status)",
                "GitHubがHTTP \(status) を返しました",
                "GitHub에서 HTTP \(status) 응답을 반환했습니다"
            )
        case .unknown:
            text = (
                "暂时无法连接 GitHub",
                "GitHub is temporarily unavailable",
                "GitHubに一時的に接続できません",
                "GitHub에 일시적으로 연결할 수 없습니다"
            )
        }

        switch language {
        case .simplifiedChinese: return text.zh
        case .english: return text.en
        case .japanese: return text.ja
        case .korean: return text.ko
        default: return text.en
        }
    }

    static func primaryLabel(
        periodRawValue: String,
        kind: MetricKind,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let period = periodTitle(periodRawValue, language: language)
        switch kind {
        case .tokens: return localizedPhrase(period, chinese: "总量", english: "total", language: language)
        case .requests: return localizedPhrase(period, chinese: "请求", english: "requests", language: language)
        case .duration: return localizedPhrase(period, chinese: "活跃", english: "active", language: language)
        case .credits:
            return "\(period) Credits"
        case .money: return localizedPhrase(period, chinese: "成本", english: "cost", language: language)
        case .quota: return text(.remainingQuota, language: language)
        }
    }

    static func readFailedRetry(
        count: Int,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch language {
        case .simplifiedChinese:
            return "读取用量失败，\(count)/3 次，3 秒后重试"
        case .english:
            return "Usage read failed, attempt \(count)/3. Retrying in 3 seconds"
        case .japanese:
            return "使用量の読み込みに失敗しました（\(count)/3回）。3秒後に再試行します"
        case .korean:
            return "사용량을 읽지 못했습니다(\(count)/3회). 3초 후 다시 시도합니다"
        default:
            return "Usage read failed, attempt \(count)/3. Retrying in 3 seconds"
        }
    }

    static func codexStatusTooltip(
        remaining: Int?,
        weeklyRemaining: Int? = nil,
        window: UsageWindow = .fiveHours,
        sidebarDisabled: Bool = false,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        guard let remaining else {
            return text(.overviewTitle, language: language)
        }
        let windowName: String
        switch window {
        case .fiveHours:
            switch language {
            case .simplifiedChinese: windowName = "5 小时"
            case .english: windowName = "5-hour"
            case .japanese: windowName = "5時間"
            case .korean: windowName = "5시간"
            default: windowName = "5-hour"
            }
        case .weekly:
            switch language {
            case .simplifiedChinese: windowName = "7 天"
            case .english: windowName = "7-day"
            case .japanese: windowName = "7日"
            case .korean: windowName = "7일"
            default: windowName = "7-day"
            }
        default:
            windowName = window.title
        }
        let weeklyText: String?
        if let weeklyRemaining,
           window != .weekly || weeklyRemaining != remaining {
            weeklyText = "\(weeklyRemaining)%"
        } else {
            weeklyText = nil
        }
        let actionText: String
        switch language {
        case .simplifiedChinese:
            let weeklySuffix = weeklyText.map { " · 周额度剩余 \($0)" } ?? ""
            actionText = sidebarDisabled ? "点击打开完整概览" : "点击唤醒侧边栏"
            return "Codex：\(windowName)剩余 \(remaining)%\(weeklySuffix) · \(actionText)"
        case .english:
            let weeklySuffix = weeklyText.map { " · Weekly quota \($0) remaining" } ?? ""
            actionText = sidebarDisabled ? "Click to open the full overview" : "Click to open the sidebar"
            return "Codex: \(windowName) quota \(remaining)% remaining\(weeklySuffix) · \(actionText)"
        case .japanese:
            let weeklySuffix = weeklyText.map { " · 週間クォータ残り \($0)" } ?? ""
            actionText = sidebarDisabled ? "クリックして完全な概要を開く" : "クリックしてサイドバーを開く"
            return "Codex：\(windowName)クォータ残り \(remaining)%\(weeklySuffix) · \(actionText)"
        case .korean:
            let weeklySuffix = weeklyText.map { " · 주간 한도 \($0) 남음" } ?? ""
            actionText = sidebarDisabled ? "클릭하여 전체 개요 열기" : "클릭하여 사이드바 열기"
            return "Codex: \(windowName) 한도 \(remaining)% 남음\(weeklySuffix) · \(actionText)"
        default:
            let weeklySuffix = weeklyText.map { " · Weekly quota \($0) remaining" } ?? ""
            actionText = sidebarDisabled ? "Click to open the full overview" : "Click to open the sidebar"
            return "Codex: \(windowName) quota \(remaining)% remaining\(weeklySuffix) · \(actionText)"
        }
    }

    static func localizedUnit(
        _ unit: String,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch unit.lowercased() {
        case "次": return text(.requestUnit, language: language)
        case "个": return text(.itemUnit, language: language)
        case "分钟": return text(.minuteUnit, language: language)
        case "credits": return text(.credits, language: language)
        default: return unit
        }
    }

    private static func localizedPhrase(
        _ period: String,
        chinese: String,
        english: String,
        language: AppLanguage
    ) -> String {
        switch language {
        case .simplifiedChinese:
            return "\(period)\(chinese)"
        case .japanese:
            let translated = japaneseWord(for: english)
            return "\(period)の\(translated)"
        case .korean:
            let translated = koreanWord(for: english)
            return "\(period) \(translated)"
        case .english:
            return "\(period) \(english)"
        case .traditionalChinese:
            let translated = traditionalChineseWord(for: english)
            return "\(period)\(translated)"
        case .spanish:
            return "\(period) \(spanishWord(for: english))"
        case .french:
            return "\(period) \(frenchWord(for: english))"
        case .german:
            return "\(period) \(germanWord(for: english))"
        case .italian:
            return "\(period) \(italianWord(for: english))"
        case .portugueseBrazil:
            return "\(period) \(portugueseWord(for: english))"
        case .russian:
            return "\(period): \(russianWord(for: english))"
        default:
            return "\(period) \(english)"
        }
    }

    private static func traditionalChineseWord(for english: String) -> String {
        switch english {
        case "total": return "總量"
        case "requests": return "請求"
        case "active": return "活躍"
        default: return "成本"
        }
    }

    private static func spanishWord(for english: String) -> String {
        switch english {
        case "total": return "total"
        case "requests": return "solicitudes"
        case "active": return "activo"
        default: return "coste"
        }
    }

    private static func frenchWord(for english: String) -> String {
        switch english {
        case "total": return "total"
        case "requests": return "requêtes"
        case "active": return "actif"
        default: return "coût"
        }
    }

    private static func germanWord(for english: String) -> String {
        switch english {
        case "total": return "gesamt"
        case "requests": return "Anfragen"
        case "active": return "aktiv"
        default: return "Kosten"
        }
    }

    private static func italianWord(for english: String) -> String {
        switch english {
        case "total": return "totale"
        case "requests": return "richieste"
        case "active": return "attivo"
        default: return "costo"
        }
    }

    private static func portugueseWord(for english: String) -> String {
        switch english {
        case "total": return "total"
        case "requests": return "solicitações"
        case "active": return "ativo"
        default: return "custo"
        }
    }

    private static func russianWord(for english: String) -> String {
        switch english {
        case "total": return "всего"
        case "requests": return "запросов"
        case "active": return "активность"
        default: return "стоимость"
        }
    }

    private static func japaneseWord(for english: String) -> String {
        switch english {
        case "total": return "合計"
        case "requests": return "リクエスト"
        case "active": return "アクティブ"
        default: return "コスト"
        }
    }

    private static func koreanWord(for english: String) -> String {
        switch english {
        case "total": return "총량"
        case "requests": return "요청"
        case "active": return "활성"
        default: return "비용"
        }
    }
}

extension UsageMetric {
    var localizedTitle: String {
        L10n.metricTitle(self)
    }
}

extension ProviderID {
    var localizedDisplayName: String {
        L10n.providerName(self)
    }
}
