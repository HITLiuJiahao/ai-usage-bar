import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    /// Keep language names in their native form so the selector stays easy
    /// to understand even before the user changes the app language.
    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
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
            .overviewSubtitle: "Codex · ZCode · 豆包工作 · MiniMax Code · WorkBuddy · QwenWork · Token、模型与用量",
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
            .overviewSubtitle: "Codex · ZCode · Doubao Work · MiniMax Code · WorkBuddy · QwenWork · tokens, models, and usage",
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
            .overviewSubtitle: "Codex · ZCode · 豆包ワーク · MiniMax Code · WorkBuddy · QwenWork · トークン、モデル、使用量",
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
            .overviewSubtitle: "Codex · ZCode · Doubao Work · MiniMax Code · WorkBuddy · QwenWork · 토큰, 모델 및 사용량",
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

    static func text(_ key: Key, language: AppLanguage = AppLanguageSettings.currentLanguage) -> String {
        translations[language]?[key]
            ?? translations[.simplifiedChinese]?[key]
            ?? key.rawValue
    }

    static func providerName(
        _ provider: ProviderID,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        switch provider {
        case .codex: return "Codex"
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
            }
        case .partial:
            switch language {
            case .simplifiedChinese: return "部分可用"
            case .english: return "Partially Available"
            case .japanese: return "一部利用可能"
            case .korean: return "일부 사용 가능"
            }
        case .cached:
            switch language {
            case .simplifiedChinese: return "历史数据"
            case .english: return "Historical Data"
            case .japanese: return "履歴データ"
            case .korean: return "기록 데이터"
            }
        case .unavailable:
            switch language {
            case .simplifiedChinese: return "暂不可用"
            case .english: return "Unavailable"
            case .japanese: return "利用不可"
            case .korean: return "사용할 수 없음"
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
            }
        case .local:
            switch language {
            case .simplifiedChinese: return "本地日志"
            case .japanese: return "ローカルログ"
            case .korean: return "로컬 로그"
            case .english: return "Local Logs"
            }
        case .cached:
            switch language {
            case .simplifiedChinese: return "本机缓存"
            case .japanese: return "ローカルキャッシュ"
            case .korean: return "로컬 캐시"
            case .english: return "Local Cache"
            }
        case .unavailable:
            switch language {
            case .simplifiedChinese: return "未读取"
            case .japanese: return "未読み込み"
            case .korean: return "읽지 못함"
            case .english: return "Not Read"
            }
        }
    }

    static func metricTitle(
        _ metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        let key = metric.key.lowercased()
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
        switch metric.window {
        case .fiveHours: return text(.fiveHours, language: language)
        case .weekly, .lastWeek:
            switch language {
            case .simplifiedChinese: return "7 天"
            case .japanese: return "7日"
            case .korean: return "7일"
            case .english: return "7 Days"
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
        }
    }

    static func remainingText(
        for metric: UsageMetric,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        if metric.unit == "%", let remaining = metric.remaining {
            return "\(NumberFormat.compact(remaining))%"
        }
        if let remaining = metric.remaining {
            return "\(NumberFormat.compact(remaining)) \(localizedUnit(metric.unit, language: language))"
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
        }
    }

    static func usedText(
        for metric: UsageMetric,
        currencyUnit: String,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        guard let used = metric.used else { return "—" }
        if metric.kind == .money {
            return NumberFormat.currency(used, unit: currencyUnit)
        }
        let unit = localizedUnit(metric.unit, language: language)
        return "\(NumberFormat.compact(used))\(unit.isEmpty ? "" : " \(unit)")"
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
        }
    }

    static func codexStatusTooltip(
        remaining: Int?,
        language: AppLanguage = AppLanguageSettings.currentLanguage
    ) -> String {
        guard let remaining else {
            return text(.overviewTitle, language: language)
        }
        switch language {
        case .simplifiedChinese:
            return "Codex：5 小时剩余 \(remaining)% · 点击唤醒侧边栏"
        case .english:
            return "Codex: 5-hour quota \(remaining)% remaining · Click to open the sidebar"
        case .japanese:
            return "Codex：5時間クォータ残り \(remaining)% · クリックしてサイドバーを開く"
        case .korean:
            return "Codex: 5시간 한도 \(remaining)% 남음 · 클릭하여 사이드바 열기"
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
