import AppKit
import Foundation
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let aiUsageBarDesktopPetDidHide = Notification.Name(
        "AIUsageBar.desktopPetDidHide"
    )
}

/// The states are intentionally provider-neutral. A Codex hook, a KIMI log
/// update, or a future provider adapter can all drive the same pet behavior.
enum DesktopPetMood: String, Codable, CaseIterable {
    case idle
    case working
    case waiting
    case blocked
    case celebrating
    case resting
}

enum DesktopPetAchievement: String, Codable, CaseIterable, Hashable, Identifiable {
    case firstSession
    case sessions10
    case sessions50
    case sessions100
    case tokens1M
    case tokens10M
    case tokens50M
    case level5
    case level10
    case level20
    case streak3
    case streak7
    case nightOwl
    case earlyBird

    var id: String { rawValue }
}

struct DesktopPetPreferences: Codable, Equatable {
    var isEnabled = true
    var showMessages = true
    var notificationsEnabled = false
    var soundEnabled = true
    var breakRemindersEnabled = false
    var breakReminderMinutes = 55
    var splitByProject = false
    var petSize: Double = 116
    var opacity: Double = 1
    var selectedPackID = PetPack.defaultPackID
    var idleMessage = ""
    var workingMessage = ""
    var waitingMessage = ""
    var completedMessage = ""
}

/// A small, open pack description. Imported packs deliberately use a simple
/// pet.json + PNG convention so users can make or share their own pets without
/// tying the app to any third-party gallery or service.
struct PetPack: Codable, Identifiable, Hashable {
    static let defaultPackID = "aiusagebar-orbit"

    let id: String
    var name: String
    var spritePath: String
    var columns: Int
    var bundled: Bool

    static let defaultPack = PetPack(
        id: defaultPackID,
        name: "Orbit",
        spritePath: "usage-orb-sprite.png",
        columns: 4,
        bundled: true
    )

    func frameIndex(for mood: DesktopPetMood) -> Int {
        switch mood {
        case .idle, .resting: return 0
        case .working: return min(1, max(columns - 1, 0))
        case .waiting, .blocked: return min(2, max(columns - 1, 0))
        case .celebrating: return min(3, max(columns - 1, 0))
        }
    }
}

struct PetPackManifest: Codable {
    let id: String?
    let name: String
    let sprite: String
    let columns: Int?
}

struct PetProjectMapping: Codable, Identifiable, Hashable {
    let id: UUID
    var projectPath: String
    var packID: String

    init(id: UUID = UUID(), projectPath: String, packID: String) {
        self.id = id
        self.projectPath = projectPath
        self.packID = packID
    }
}

struct PetDayHistory: Codable, Identifiable, Hashable {
    var day: Date
    var tokens: Double
    var requests: Double
    var sessions: Int
    var feeds: Int

    var id: Date { day }

    init(day: Date, tokens: Double = 0, requests: Double = 0, sessions: Int = 0, feeds: Int = 0) {
        self.day = Calendar.current.startOfDay(for: day)
        self.tokens = tokens
        self.requests = requests
        self.sessions = sessions
        self.feeds = feeds
    }
}

struct DesktopPetQuotaRow: Identifiable, Hashable {
    let provider: ProviderID
    let window: UsageWindow
    let remainingPercent: Int
    let resetAt: Date?

    var id: String { "\(provider.rawValue)-\(window.rawValue)" }
}

struct PetProgress: Codable, Equatable {
    var totalXP = 0
    var totalTokens: Double = 0
    var totalRequests: Double = 0
    var completedSessions = 0
    var manualFeeds = 0
    var dailyStreak = 0
    var lastActivityAt: Date?
    var lastActiveDay: Date?
    var lastBreakReminderAt: Date?

    var level: Int {
        // Gentle early levels, then a progressively longer runway. This makes
        // the pet feel alive without turning usage tracking into a grind.
        1 + Int(sqrt(Double(max(totalXP, 0)) / 30.0))
    }

    var stage: PetGrowthStage {
        switch level {
        case 0...3: return .hatchling
        case 4...7: return .companion
        case 8...14: return .scout
        case 15...24: return .hero
        default: return .legend
        }
    }

    var xpIntoCurrentLevel: Int {
        let currentBase = max(0, (level - 1) * (level - 1) * 30)
        return max(0, totalXP - currentBase)
    }

    var xpForNextLevel: Int {
        let nextBase = level * level * 30
        let currentBase = max(0, (level - 1) * (level - 1) * 30)
        return max(1, nextBase - currentBase)
    }
}

enum PetGrowthStage: String, Codable, CaseIterable {
    case hatchling
    case companion
    case scout
    case hero
    case legend
}

/// The local hook protocol. The socket accepts one JSON event per line. Its
/// deliberately small shape means adapters for any agent can be implemented
/// without giving AI Usage Bar access to the agent's credentials or prompts.
struct PetHookEvent: Codable, Hashable {
    var provider: String
    var state: String
    var projectPath: String?
    var sessionID: String?
    var message: String?
    var model: String?
    var tokens: Double?
    var requests: Double?
    var timestamp: Date?
}

/// A live agent row shown in the pet bubble/HUD. State timers are based on
/// `stateSince`, not merely the last event, so an agent that is waiting for
/// input remains visibly waiting until a new hook event arrives.
struct PetActiveAgentSession: Codable, Identifiable, Hashable {
    var id: String
    var provider: ProviderID?
    var projectPath: String?
    var message: String?
    var model: String?
    var mood: DesktopPetMood
    var createdAt: Date
    var stateSince: Date
    var updatedAt: Date
}

/// Local-only, rolling 90-day finished-session archive. It contains metadata
/// supplied by a hook, never a prompt, response, or credential.
struct PetSessionArchiveEntry: Codable, Identifiable, Hashable {
    var id: String
    var provider: ProviderID?
    var projectPath: String?
    var message: String?
    var model: String?
    var startedAt: Date
    var endedAt: Date
    var tokens: Double
    var requests: Double
}

private struct DesktopPetSavedState: Codable {
    var preferences: DesktopPetPreferences
    var progress: PetProgress
    var history: [PetDayHistory]
    var achievements: Set<DesktopPetAchievement>
    var packs: [PetPack]
    var projectMappings: [PetProjectMapping]
    var activeSessions: [PetActiveAgentSession]
    var sessionArchive: [PetSessionArchiveEntry]

    init(
        preferences: DesktopPetPreferences,
        progress: PetProgress,
        history: [PetDayHistory],
        achievements: Set<DesktopPetAchievement>,
        packs: [PetPack],
        projectMappings: [PetProjectMapping],
        activeSessions: [PetActiveAgentSession] = [],
        sessionArchive: [PetSessionArchiveEntry] = []
    ) {
        self.preferences = preferences
        self.progress = progress
        self.history = history
        self.achievements = achievements
        self.packs = packs
        self.projectMappings = projectMappings
        self.activeSessions = activeSessions
        self.sessionArchive = sessionArchive
    }

    private enum CodingKeys: String, CodingKey {
        case preferences, progress, history, achievements, packs, projectMappings, activeSessions, sessionArchive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferences = try container.decodeIfPresent(DesktopPetPreferences.self, forKey: .preferences) ?? DesktopPetPreferences()
        progress = try container.decodeIfPresent(PetProgress.self, forKey: .progress) ?? PetProgress()
        history = try container.decodeIfPresent([PetDayHistory].self, forKey: .history) ?? []
        achievements = try container.decodeIfPresent(Set<DesktopPetAchievement>.self, forKey: .achievements) ?? []
        packs = try container.decodeIfPresent([PetPack].self, forKey: .packs) ?? [PetPack.defaultPack]
        projectMappings = try container.decodeIfPresent([PetProjectMapping].self, forKey: .projectMappings) ?? []
        activeSessions = try container.decodeIfPresent([PetActiveAgentSession].self, forKey: .activeSessions) ?? []
        sessionArchive = try container.decodeIfPresent([PetSessionArchiveEntry].self, forKey: .sessionArchive) ?? []
    }
}

private struct TodayProviderTotals: Equatable {
    var tokens: Double = 0
    var requests: Double = 0
}

/// Filesystem locations are deliberately nonisolated so the background socket
/// listener can create and remove its local endpoint without hopping through
/// the UI actor.
enum DesktopPetStorage {
    static var storageDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("AIUsageBar", isDirectory: true)
            .appendingPathComponent("DesktopPet", isDirectory: true)
    }

    static var packsDirectory: URL {
        storageDirectory.appendingPathComponent("Packs", isDirectory: true)
    }

    static var storageURL: URL {
        storageDirectory.appendingPathComponent("pet-state.json")
    }
}

@MainActor
final class DesktopPetStore: ObservableObject {
    static let shared = DesktopPetStore()
    private static let workingSessionLifetime: TimeInterval = 15 * 60
    private static let blockedSessionLifetime: TimeInterval = 30 * 60
    private static let codexSessionPrefix = "codex-log:"
    private static let hideReminderSuppressedKey = "AIUsageBar.desktopPet.hideReminderSuppressed"

    @Published private(set) var preferences: DesktopPetPreferences
    @Published private(set) var progress: PetProgress
    @Published private(set) var history: [PetDayHistory]
    @Published private(set) var achievements: Set<DesktopPetAchievement>
    @Published private(set) var packs: [PetPack]
    @Published private(set) var projectMappings: [PetProjectMapping]
    @Published private(set) var mood: DesktopPetMood = .idle
    @Published private(set) var speech: String = ""
    @Published private(set) var activeProvider: ProviderID?
    @Published private(set) var activeProjectPath: String?
    @Published private(set) var quotaRows: [DesktopPetQuotaRow] = []
    @Published private(set) var activeSessions: [PetActiveAgentSession]
    @Published private(set) var sessionArchive: [PetSessionArchiveEntry]
    @Published private(set) var showPetShortcut: PetShortcut
    @Published private(set) var hidePetShortcut: PetShortcut

    private var observationBaseline: [ProviderID: TodayProviderTotals] = [:]
    private var hasObservationBaseline = false
    private var moodResetTask: Task<Void, Never>?
    private var breakTimer: Timer?
    private var completedHookSessions = Set<String>()
    private let codexActivityMonitor = CodexPetActivityMonitor()
    private var codexActivityTimer: Timer?
    private var codexActivityTask: Task<Void, Never>?
    private var hasCodexActivityBaseline = false
    private var codexTaskActivities: [String: CodexPetTaskActivity] = [:]

    private init() {
        let saved = Self.loadSavedState()
        preferences = saved.preferences
        progress = saved.progress
        history = saved.history
        achievements = saved.achievements
        var loadedPacks = saved.packs.isEmpty ? [PetPack.defaultPack] : saved.packs
        if !loadedPacks.contains(where: { $0.id == PetPack.defaultPackID }) {
            loadedPacks.insert(PetPack.defaultPack, at: 0)
        }
        packs = loadedPacks
        projectMappings = saved.projectMappings
        showPetShortcut = Self.loadPetShortcut(
            forKey: "AIUsageBar.desktopPet.showShortcut",
            fallback: .defaultShow
        )
        hidePetShortcut = Self.loadPetShortcut(
            forKey: "AIUsageBar.desktopPet.hideShortcut",
            fallback: .defaultHide
        )
        let now = Date()
        activeSessions = saved.activeSessions.filter {
            !Self.isStaleActiveSession($0, now: now)
        }
        sessionArchive = saved.sessionArchive
        pruneHistory()
        pruneSessionArchive()
        scheduleBreakTimer()
        updateSpeech(for: .idle)
        scheduleCodexActivityMonitoring()
    }

    deinit {
        breakTimer?.invalidate()
        codexActivityTimer?.invalidate()
        codexActivityTask?.cancel()
        moodResetTask?.cancel()
    }

    var selectedPack: PetPack {
        packs.first(where: { $0.id == preferences.selectedPackID }) ?? PetPack.defaultPack
    }

    var activePack: PetPack {
        guard preferences.splitByProject,
              let activeProjectPath,
              let mapping = projectMappings
                .sorted(by: { $0.projectPath.count > $1.projectPath.count })
                .first(where: { activeProjectPath.hasPrefix($0.projectPath) }),
              let pack = packs.first(where: { $0.id == mapping.packID })
        else { return selectedPack }
        return pack
    }

    var energyPercent: Int {
        guard let lastActivity = progress.lastActivityAt else { return 100 }
        let elapsedHours = Date().timeIntervalSince(lastActivity) / 3_600
        return Int(min(max(100 - elapsedHours * 7, 0), 100).rounded())
    }

    var nextLevelProgress: Double {
        Double(progress.xpIntoCurrentLevel) / Double(progress.xpForNextLevel)
    }

    var recentHistory: [PetDayHistory] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return history.first(where: { calendar.isDate($0.day, inSameDayAs: day) })
                ?? PetDayHistory(day: day)
        }
    }

    func setEnabled(_ enabled: Bool) {
        let wasEnabled = preferences.isEnabled
        preferences.isEnabled = enabled
        persist()
        if wasEnabled && !enabled {
            NotificationCenter.default.post(
                name: .aiUsageBarDesktopPetDidHide,
                object: nil
            )
        }
    }

    func setShowMessages(_ enabled: Bool) {
        preferences.showMessages = enabled
        persist()
    }

    @discardableResult
    func setShowPetShortcut(_ shortcut: PetShortcut) -> Bool {
        guard shortcut.isValid, shortcut != hidePetShortcut else { return false }
        showPetShortcut = shortcut
        Self.savePetShortcut(shortcut, forKey: "AIUsageBar.desktopPet.showShortcut")
        return true
    }

    @discardableResult
    func setHidePetShortcut(_ shortcut: PetShortcut) -> Bool {
        guard shortcut.isValid, shortcut != showPetShortcut else { return false }
        hidePetShortcut = shortcut
        Self.savePetShortcut(shortcut, forKey: "AIUsageBar.desktopPet.hideShortcut")
        return true
    }

    func resetPetShortcuts() {
        showPetShortcut = .defaultShow
        hidePetShortcut = .defaultHide
        Self.savePetShortcut(showPetShortcut, forKey: "AIUsageBar.desktopPet.showShortcut")
        Self.savePetShortcut(hidePetShortcut, forKey: "AIUsageBar.desktopPet.hideShortcut")
    }

    var shouldShowHideReminder: Bool {
        !UserDefaults.standard.bool(forKey: Self.hideReminderSuppressedKey)
    }

    func suppressHideReminder() {
        UserDefaults.standard.set(true, forKey: Self.hideReminderSuppressedKey)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        preferences.notificationsEnabled = enabled
        if enabled {
            PetNotificationCenter.requestAuthorization()
        }
        persist()
    }

    func setSoundEnabled(_ enabled: Bool) {
        preferences.soundEnabled = enabled
        persist()
    }

    func setBreakRemindersEnabled(_ enabled: Bool) {
        preferences.breakRemindersEnabled = enabled
        persist()
    }

    func setBreakReminderMinutes(_ minutes: Int) {
        preferences.breakReminderMinutes = min(max(minutes, 15), 180)
        persist()
    }

    func setSplitByProject(_ enabled: Bool) {
        preferences.splitByProject = enabled
        persist()
    }

    func setPetSize(_ value: Double) {
        preferences.petSize = min(max(value, 72), 180)
        persist()
    }

    func setOpacity(_ value: Double) {
        preferences.opacity = min(max(value, 0.35), 1)
        persist()
    }

    func setSelectedPack(_ packID: String) {
        guard packs.contains(where: { $0.id == packID }) else { return }
        preferences.selectedPackID = packID
        persist()
    }

    func setCustomMessages(idle: String, working: String, waiting: String, completed: String) {
        preferences.idleMessage = idle.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.workingMessage = working.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.waitingMessage = waiting.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.completedMessage = completed.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSpeech(for: mood)
        persist()
    }

    func ingest(snapshots: [ProviderSnapshot]) {
        pruneStaleActiveSessions()
        quotaRows = Self.quotaRows(from: snapshots)
        let next = Dictionary(uniqueKeysWithValues: snapshots.map { snapshot in
            (snapshot.provider, Self.todayTotals(for: snapshot))
        })

        guard hasObservationBaseline else {
            observationBaseline = next
            hasObservationBaseline = true
            return
        }

        var gainedTokens: Double = 0
        var gainedRequests: Double = 0
        var providerWithActivity: ProviderID?
        for (provider, newValue) in next {
            let oldValue = observationBaseline[provider] ?? TodayProviderTotals()
            let tokenDelta = max(0, newValue.tokens - oldValue.tokens)
            let requestDelta = max(0, newValue.requests - oldValue.requests)
            if tokenDelta > 0 || requestDelta > 0 {
                gainedTokens += tokenDelta
                gainedRequests += requestDelta
                providerWithActivity = provider
            }
        }
        observationBaseline = next

        guard gainedTokens > 0 || gainedRequests > 0 else { return }
        recordActivity(
            tokens: gainedTokens,
            requests: gainedRequests,
            provider: providerWithActivity,
            projectPath: nil,
            isCompletedSession: false
        )
    }

    func consume(_ event: PetHookEvent) {
        pruneStaleActiveSessions()
        let provider = Self.providerID(from: event.provider)
        let eventState = event.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        activeProvider = provider
        activeProjectPath = event.projectPath

        switch eventState {
        case "working", "run", "running", "tool", "started":
            upsertActiveSession(event, mood: .working)
            setMood(.working, message: event.message, resetAfter: nil)
        case "waiting", "input", "approval", "question", "needs_input":
            upsertActiveSession(event, mood: .waiting)
            setMood(.waiting, message: event.message, resetAfter: nil)
            notifyIfNeeded(title: "AI Usage Bar", body: event.message ?? PetText.waiting)
        case "blocked", "error", "failed", "aborted", "turn_aborted", "denied":
            upsertActiveSession(event, mood: .blocked)
            setMood(.blocked, message: event.message, resetAfter: nil)
            notifyIfNeeded(title: "AI Usage Bar", body: event.message ?? PetText.blocked)
        case "done", "complete", "completed", "finished", "success":
            let sessionKey = event.sessionID ?? "\(event.provider)-\(event.timestamp?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)"
            let firstCompletion = completedHookSessions.insert(sessionKey).inserted
            recordActivity(
                tokens: max(event.tokens ?? 0, 0),
                requests: max(event.requests ?? 0, 0),
                provider: provider,
                projectPath: event.projectPath,
                isCompletedSession: firstCompletion
            )
            archiveActiveSession(event)
            if let activeMood = dominantActiveMood {
                setMood(activeMood, message: nil, resetAfter: nil)
            } else {
                setMood(.celebrating, message: event.message, resetAfter: 6)
            }
            notifyIfNeeded(title: "AI Usage Bar", body: event.message ?? PetText.completed)
        case "idle", "stopped", "cancelled", "canceled":
            archiveActiveSession(event)
            setMood(dominantActiveMood ?? .idle, message: event.message, resetAfter: nil)
        default:
            upsertActiveSession(event, mood: .working)
            setMood(.working, message: event.message, resetAfter: nil)
        }
    }

    private func resolvedSessionID(for event: PetHookEvent) -> String {
        if let sessionID = event.sessionID, !sessionID.isEmpty { return sessionID }
        let provider = event.provider.lowercased().replacingOccurrences(of: " ", with: "-")
        let project = event.projectPath ?? "default"
        // A caller that has no native session ID still gets a stable row per
        // provider/project while it is active.
        return "\(provider):\(project)"
    }

    private func upsertActiveSession(
        _ event: PetHookEvent,
        mood: DesktopPetMood,
        persistChanges: Bool = true
    ) {
        let id = resolvedSessionID(for: event)
        let now = event.timestamp ?? Date()
        let provider = Self.providerID(from: event.provider)
        if let index = activeSessions.firstIndex(where: { $0.id == id }) {
            let stateChanged = activeSessions[index].mood != mood
            activeSessions[index].provider = provider ?? activeSessions[index].provider
            activeSessions[index].projectPath = event.projectPath ?? activeSessions[index].projectPath
            activeSessions[index].message = event.message ?? activeSessions[index].message
            activeSessions[index].model = event.model ?? activeSessions[index].model
            activeSessions[index].mood = mood
            activeSessions[index].updatedAt = now
            if stateChanged { activeSessions[index].stateSince = now }
        } else {
            activeSessions.append(PetActiveAgentSession(
                id: id,
                provider: provider,
                projectPath: event.projectPath,
                message: event.message,
                model: event.model,
                mood: mood,
                createdAt: now,
                stateSince: now,
                updatedAt: now
            ))
        }
        if persistChanges {
            persist()
        }
    }

    private func archiveActiveSession(_ event: PetHookEvent) {
        let id = resolvedSessionID(for: event)
        let now = event.timestamp ?? Date()
        let active = activeSessions.first(where: { $0.id == id })
        activeSessions.removeAll(where: { $0.id == id })
        let entry = PetSessionArchiveEntry(
            id: id,
            provider: Self.providerID(from: event.provider) ?? active?.provider,
            projectPath: event.projectPath ?? active?.projectPath,
            message: event.message ?? active?.message,
            model: event.model ?? active?.model,
            startedAt: active?.createdAt ?? now,
            endedAt: now,
            tokens: max(event.tokens ?? 0, 0),
            requests: max(event.requests ?? 0, 0)
        )
        // Most agents reuse their session id for one conversation. Keep the
        // newest lifecycle summary rather than creating repeated stop rows.
        sessionArchive.removeAll(where: { $0.id == id })
        sessionArchive.append(entry)
        pruneSessionArchive()
        persist()
    }

    func feed() {
        progress.manualFeeds += 1
        progress.totalXP += 5
        progress.lastActivityAt = Date()
        mutateToday { $0.feeds += 1 }
        unlockAchievements()
        setMood(.celebrating, message: PetText.fed, resetAfter: 4)
        persist()
    }

    func resetPetPosition() {
        DesktopPetWindowController.shared.resetPosition()
    }

    func importPack() {
        let panel = NSOpenPanel()
        panel.message = PetText.choosePackFolder
        panel.prompt = PetText.importPack
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let manifestURL = folder.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetPackManifest.self, from: data)
        else {
            setMood(.waiting, message: PetText.invalidPack, resetAfter: 7)
            return
        }
        let source = folder.appendingPathComponent(manifest.sprite)
        guard FileManager.default.fileExists(atPath: source.path) else {
            setMood(.waiting, message: PetText.invalidPack, resetAfter: 7)
            return
        }

        let identifier = Self.safePackIdentifier(manifest.id ?? manifest.name)
        let targetFolder = Self.packsDirectory.appendingPathComponent(identifier, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            let targetSprite = targetFolder.appendingPathComponent("sprite.png")
            try? FileManager.default.removeItem(at: targetSprite)
            try FileManager.default.copyItem(at: source, to: targetSprite)
            let pack = PetPack(
                id: identifier,
                name: manifest.name,
                spritePath: targetSprite.path,
                columns: min(max(manifest.columns ?? 4, 1), 16),
                bundled: false
            )
            packs.removeAll(where: { $0.id == identifier })
            packs.append(pack)
            preferences.selectedPackID = identifier
            setMood(.celebrating, message: PetText.packImported, resetAfter: 5)
            persist()
        } catch {
            setMood(.waiting, message: PetText.packImportFailed, resetAfter: 7)
        }
    }

    func addProjectMapping() {
        let panel = NSOpenPanel()
        panel.message = PetText.chooseProjectFolder
        panel.prompt = PetText.addProject
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let path = folder.standardizedFileURL.path
        projectMappings.removeAll(where: { $0.projectPath == path })
        projectMappings.append(PetProjectMapping(projectPath: path, packID: preferences.selectedPackID))
        persist()
    }

    func removeProjectMapping(_ mapping: PetProjectMapping) {
        projectMappings.removeAll(where: { $0.id == mapping.id })
        persist()
    }

    func clearHistory() {
        history = []
        progress = PetProgress()
        achievements = []
        activeSessions = []
        sessionArchive = []
        observationBaseline = [:]
        hasObservationBaseline = false
        updateSpeech(for: .idle)
        persist()
    }

    private func recordActivity(
        tokens: Double,
        requests: Double,
        provider: ProviderID?,
        projectPath: String?,
        isCompletedSession: Bool
    ) {
        let safeTokens = max(tokens, 0)
        let safeRequests = max(requests, 0)
        let now = Date()
        activeProvider = provider ?? activeProvider
        activeProjectPath = projectPath ?? activeProjectPath
        progress.totalTokens += safeTokens
        progress.totalRequests += safeRequests
        progress.totalXP += Int((safeTokens / 1_000).rounded(.down)) + Int(safeRequests * 2)
        if isCompletedSession {
            progress.completedSessions += 1
            progress.totalXP += 15
        }
        progress.lastActivityAt = now
        updateStreak(for: now)
        mutateToday {
            $0.tokens += safeTokens
            $0.requests += safeRequests
            if isCompletedSession { $0.sessions += 1 }
        }
        unlockAchievements()

        persist()
    }

    private func updateStreak(for date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let lastDay = progress.lastActiveDay else {
            progress.dailyStreak = 1
            progress.lastActiveDay = today
            return
        }
        if calendar.isDate(lastDay, inSameDayAs: today) {
            return
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        progress.dailyStreak = calendar.isDate(lastDay, inSameDayAs: yesterday)
            ? max(progress.dailyStreak + 1, 2)
            : 1
        progress.lastActiveDay = today
    }

    private func mutateToday(_ mutate: (inout PetDayHistory) -> Void) {
        let today = Calendar.current.startOfDay(for: Date())
        if let index = history.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: today) }) {
            mutate(&history[index])
        } else {
            var day = PetDayHistory(day: today)
            mutate(&day)
            history.append(day)
        }
        pruneHistory()
    }

    private func unlockAchievements() {
        func unlock(_ achievement: DesktopPetAchievement, when condition: Bool) {
            if condition { achievements.insert(achievement) }
        }
        unlock(.firstSession, when: progress.completedSessions >= 1)
        unlock(.sessions10, when: progress.completedSessions >= 10)
        unlock(.sessions50, when: progress.completedSessions >= 50)
        unlock(.sessions100, when: progress.completedSessions >= 100)
        unlock(.tokens1M, when: progress.totalTokens >= 1_000_000)
        unlock(.tokens10M, when: progress.totalTokens >= 10_000_000)
        unlock(.tokens50M, when: progress.totalTokens >= 50_000_000)
        unlock(.level5, when: progress.level >= 5)
        unlock(.level10, when: progress.level >= 10)
        unlock(.level20, when: progress.level >= 20)
        unlock(.streak3, when: progress.dailyStreak >= 3)
        unlock(.streak7, when: progress.dailyStreak >= 7)
        let hour = Calendar.current.component(.hour, from: progress.lastActivityAt ?? .distantPast)
        unlock(.nightOwl, when: hour >= 23 || hour < 5)
        unlock(.earlyBird, when: hour >= 5 && hour < 8)
    }

    private func setMood(_ newMood: DesktopPetMood, message: String?, resetAfter: TimeInterval?) {
        moodResetTask?.cancel()
        mood = newMood
        updateSpeech(for: newMood, override: message)
        if let resetAfter {
            moodResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(resetAfter * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.restoreActiveMoodOrIdle()
            }
        }
    }

    private var dominantActiveMood: DesktopPetMood? {
        if activeSessions.contains(where: { $0.mood == .blocked }) { return .blocked }
        if activeSessions.contains(where: { $0.mood == .waiting }) { return .waiting }
        if activeSessions.contains(where: { $0.mood == .working }) { return .working }
        return nil
    }

    private func restoreActiveMoodOrIdle() {
        setMood(dominantActiveMood ?? .idle, message: nil, resetAfter: nil)
    }

    private static func isCodexActivitySession(_ session: PetActiveAgentSession) -> Bool {
        session.id.hasPrefix(codexSessionPrefix)
    }

    private static func isStaleActiveSession(
        _ session: PetActiveAgentSession,
        now: Date
    ) -> Bool {
        let lifetime: TimeInterval
        switch session.mood {
        case .working:
            lifetime = workingSessionLifetime
        case .blocked:
            lifetime = blockedSessionLifetime
        case .idle, .resting, .waiting, .celebrating:
            return false
        }
        return now.timeIntervalSince(session.updatedAt) > lifetime
    }

    private func pruneStaleActiveSessions() {
        let now = Date()
        let previousCount = activeSessions.count
        // Codex-log sessions are reconciled against the monitor's current
        // activity set below.  Do not expire them before that reconciliation,
        // because a long-running task may have a fresh heartbeat even though
        // its last lifecycle event is old.
        activeSessions.removeAll { session in
            guard !Self.isCodexActivitySession(session) else { return false }
            return Self.isStaleActiveSession(session, now: now)
        }
        guard activeSessions.count != previousCount else { return }

        if mood == .blocked || mood == .waiting || mood == .working {
            restoreActiveMoodOrIdle()
        }
        persist()
    }

    private func updateSpeech(for mood: DesktopPetMood, override: String? = nil) {
        if let override, !override.isEmpty {
            speech = override
            return
        }
        let custom: String
        switch mood {
        case .idle, .resting: custom = preferences.idleMessage
        case .working: custom = preferences.workingMessage
        case .waiting, .blocked: custom = preferences.waitingMessage
        case .celebrating: custom = preferences.completedMessage
        }
        if !custom.isEmpty {
            speech = custom
            return
        }
        switch mood {
        case .idle: speech = PetText.idle
        case .working: speech = activeProvider.map { "\(L10n.providerName($0)) · \(PetText.working)" } ?? PetText.working
        case .waiting: speech = PetText.waiting
        case .blocked: speech = PetText.blocked
        case .celebrating: speech = PetText.completed
        case .resting: speech = PetText.rest
        }
    }

    /// Codex itself writes `task_started`, `task_complete`, and `turn_aborted`
    /// records to its local rollout log.  Polling only these short metadata
    /// tails gives the pet lifecycle-level status without requiring a user to
    /// install or maintain a Codex hook.
    private func scheduleCodexActivityMonitoring() {
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollCodexActivity()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        codexActivityTimer = timer
        pollCodexActivity()
    }

    private func pollCodexActivity() {
        pruneStaleActiveSessions()
        guard codexActivityTask == nil else { return }
        let monitor = codexActivityMonitor
        codexActivityTask = Task { [weak self] in
            let activities = await Task.detached(priority: .utility) {
                monitor.refresh()
            }.value
            guard let self else { return }
            self.codexActivityTask = nil
            guard !Task.isCancelled else { return }
            self.applyCodexActivity(activities)
        }
    }

    private func applyCodexActivity(_ activities: [CodexPetTaskActivity]) {
        pruneStaleActiveSessions()
        reconcileCodexActiveSessions(with: activities)
        let next = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        defer {
            codexTaskActivities = next
            hasCodexActivityBaseline = true
        }

        guard hasCodexActivityBaseline else {
            // Existing completed turns are history, not fresh celebrations.
            // Existing active/blocked turns should still be visible on launch.
            for activity in activities where activity.state == .running || activity.state == .blocked {
                consume(codexEvent(for: activity, state: activity.state == .running ? "working" : "blocked"))
            }
            return
        }

        for activity in activities {
            let previous = codexTaskActivities[activity.id]
            guard previous?.state != activity.state else { continue }
            switch activity.state {
            case .running:
                consume(codexEvent(for: activity, state: "working"))
            case .blocked:
                consume(codexEvent(for: activity, state: "blocked"))
            case .completed:
                // A task that began and ended between two polls is still worth
                // acknowledging if its completion is genuinely recent.
                if previous != nil || Date().timeIntervalSince(activity.updatedAt) < 3 {
                    consume(codexEvent(for: activity, state: "done"))
                }
            }
        }
    }

    private func reconcileCodexActiveSessions(with activities: [CodexPetTaskActivity]) {
        let liveActivities = activities.filter {
            $0.state == .running || $0.state == .blocked
        }
        let liveIDs = Set(liveActivities.map(\.id))
        let previousSessions = activeSessions

        // The rollout monitor is authoritative for Codex rows.  This removes
        // completed turns and sessions from files that are no longer recent;
        // previously these rows stayed in the persisted list forever.
        activeSessions.removeAll { session in
            Self.isCodexActivitySession(session) && !liveIDs.contains(session.id)
        }

        // Refresh the heartbeat timestamp on every poll without writing the
        // state file every 1.5 seconds.  A real lifecycle transition still
        // goes through consume(), which persists normally.
        for activity in liveActivities {
            let state = activity.state == .running ? DesktopPetMood.working : .blocked
            upsertActiveSession(
                codexEvent(for: activity, state: state == .working ? "working" : "blocked"),
                mood: state,
                persistChanges: false
            )
        }

        guard activeSessions != previousSessions else { return }
        if let latest = liveActivities.first {
            activeProvider = .codex
            activeProjectPath = latest.projectPath
        }
        restoreActiveMoodOrIdle()
        persist()
    }

    private func codexEvent(for activity: CodexPetTaskActivity, state: String) -> PetHookEvent {
        PetHookEvent(
            provider: ProviderID.codex.rawValue,
            state: state,
            projectPath: activity.projectPath,
            sessionID: activity.id,
            message: state == "working" ? activity.action.map(PetUI.codexAction) : nil,
            model: activity.model,
            tokens: nil,
            requests: nil,
            timestamp: activity.updatedAt
        )
    }

    private func scheduleBreakTimer() {
        breakTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkBreakReminder()
            }
        }
    }

    private func checkBreakReminder() {
        guard preferences.breakRemindersEnabled,
              let lastActivity = progress.lastActivityAt
        else { return }
        let interval = TimeInterval(preferences.breakReminderMinutes * 60)
        guard Date().timeIntervalSince(lastActivity) >= interval else { return }
        if let lastReminder = progress.lastBreakReminderAt,
           Date().timeIntervalSince(lastReminder) < interval { return }
        progress.lastBreakReminderAt = Date()
        setMood(.resting, message: PetText.breakTime, resetAfter: 12)
        notifyIfNeeded(title: "AI Usage Bar", body: PetText.breakTime)
        persist()
    }

    private func notifyIfNeeded(title: String, body: String) {
        guard preferences.notificationsEnabled else { return }
        PetNotificationCenter.notify(title: title, body: body, playSound: preferences.soundEnabled)
    }

    private func pruneHistory() {
        let earliest = Calendar.current.date(byAdding: .day, value: -89, to: Date()) ?? Date()
        history = history
            .filter { $0.day >= Calendar.current.startOfDay(for: earliest) }
            .sorted(by: { $0.day < $1.day })
    }

    private func pruneSessionArchive() {
        let earliest = Calendar.current.date(byAdding: .day, value: -89, to: Date()) ?? Date()
        sessionArchive = sessionArchive
            .filter { $0.endedAt >= earliest }
            .sorted(by: { $0.endedAt > $1.endedAt })
    }

    private func persist() {
        let state = DesktopPetSavedState(
            preferences: preferences,
            progress: progress,
            history: history,
            achievements: achievements,
            packs: packs,
            projectMappings: projectMappings,
            activeSessions: activeSessions,
            sessionArchive: sessionArchive
        )
        do {
            try FileManager.default.createDirectory(at: Self.storageDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            // A desktop pet should never make normal usage monitoring fail if
            // its optional local cache cannot be persisted.
        }
    }

    private static func loadSavedState() -> DesktopPetSavedState {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? JSONDecoder().decode(DesktopPetSavedState.self, from: data)
        else {
            return DesktopPetSavedState(
                preferences: DesktopPetPreferences(),
                progress: PetProgress(),
                history: [],
                achievements: [],
                packs: [PetPack.defaultPack],
                projectMappings: [],
                activeSessions: [],
                sessionArchive: []
            )
        }
        return state
    }

    static var storageDirectory: URL {
        DesktopPetStorage.storageDirectory
    }

    static var packsDirectory: URL {
        DesktopPetStorage.packsDirectory
    }

    static var storageURL: URL {
        DesktopPetStorage.storageURL
    }

    private static func todayTotals(for snapshot: ProviderSnapshot) -> TodayProviderTotals {
        var result = TodayProviderTotals()
        for metric in snapshot.accounts.flatMap(\.metrics) where metric.window == .today || metric.window == .daily {
            switch metric.kind {
            case .tokens:
                if let used = metric.used {
                    result.tokens += max(used, 0)
                } else {
                    result.tokens += [metric.inputTokens, metric.outputTokens, metric.cacheReadTokens, metric.cacheWriteTokens, metric.reasoningTokens]
                        .compactMap { $0 }
                        .reduce(0, +)
                }
            case .requests:
                result.requests += max(metric.used ?? 0, 0)
            default:
                break
            }
        }
        return result
    }

    private static func quotaRows(from snapshots: [ProviderSnapshot]) -> [DesktopPetQuotaRow] {
        var seen = Set<String>()
        let order: [UsageWindow] = [.fiveHours, .weekly, .monthly, .daily, .billing]
        let rows = snapshots.flatMap { snapshot in
            snapshot.accounts.flatMap { account in
                account.metrics.compactMap { metric -> DesktopPetQuotaRow? in
                    guard metric.kind == .quota,
                          order.contains(metric.window),
                          let rawRemaining = metric.remaining ?? metric.limit.map({ ($0 - (metric.used ?? 0)) })
                    else { return nil }
                    let normalized: Double
                    if rawRemaining <= 1, (metric.limit ?? 0) <= 1 {
                        normalized = rawRemaining * 100
                    } else if let limit = metric.limit, limit > 0, limit != 100, metric.unit != "%" {
                        normalized = rawRemaining / limit * 100
                    } else {
                        normalized = rawRemaining
                    }
                    return DesktopPetQuotaRow(
                        provider: snapshot.provider,
                        window: metric.window,
                        remainingPercent: Int(min(max(normalized, 0), 100).rounded()),
                        resetAt: metric.resetAt
                    )
                }
            }
        }
        return rows
            .sorted {
                let lhsProvider = ProviderID.trackedCases.firstIndex(of: $0.provider) ?? .max
                let rhsProvider = ProviderID.trackedCases.firstIndex(of: $1.provider) ?? .max
                if lhsProvider != rhsProvider { return lhsProvider < rhsProvider }
                let lhsWindow = order.firstIndex(of: $0.window) ?? .max
                let rhsWindow = order.firstIndex(of: $1.window) ?? .max
                return lhsWindow < rhsWindow
            }
            .filter { seen.insert($0.id).inserted }
            .prefix(4)
            .map { $0 }
    }

    private static func providerID(from value: String) -> ProviderID? {
        let normalized = value.lowercased().replacingOccurrences(of: "-", with: "")
        if let direct = ProviderID(rawValue: value) { return direct }
        switch normalized {
        case "codex", "openai": return .codex
        case "kimi", "kimidesktop": return .kimi
        case "qwenwork", "qwen": return .qwenWork
        case "zcode": return .zcode
        case "doubaowork", "doubao": return .doubaoWork
        case "workbuddy": return .workBuddy
        case "minimax", "minimaxcode": return .miniMax
        case "opencode": return .openCode
        case "qianwenoffice": return .qianwenOffice
        case "deepseek", "deepseekharness": return .deepSeekHarness
        default: return nil
        }
    }

    private static func safePackIdentifier(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let normalized = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "pet-\(UUID().uuidString.lowercased())" : normalized
    }

    private static func loadPetShortcut(
        forKey key: String,
        fallback: PetShortcut
    ) -> PetShortcut {
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(PetShortcut.self, from: data),
              shortcut.isValid
        else { return fallback }
        return shortcut
    }

    private static func savePetShortcut(_ shortcut: PetShortcut, forKey key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum PetNotificationCenter {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
enum PetText {
    private static var language: AppLanguage { AppLanguageSettings.shared.language }

    static var idle: String {
        switch language {
        case .simplifiedChinese: return "我在这里陪你。"
        case .english: return "I’m here with you."
        case .japanese: return "ここで見守っています。"
        case .korean: return "여기서 함께하고 있어요."
        }
    }

    static var working: String {
        switch language {
        case .simplifiedChinese: return "正在工作"
        case .english: return "is working"
        case .japanese: return "作業中"
        case .korean: return "작업 중"
        }
    }

    static var waiting: String {
        switch language {
        case .simplifiedChinese: return "需要你的注意。"
        case .english: return "Needs your attention."
        case .japanese: return "あなたの確認が必要です。"
        case .korean: return "확인이 필요해요."
        }
    }

    static var blocked: String {
        switch language {
        case .simplifiedChinese: return "任务受阻，需要处理。"
        case .english: return "Task blocked. Needs attention."
        case .japanese: return "タスクが中断されました。対応が必要です。"
        case .korean: return "작업이 중단되었어요. 확인이 필요합니다."
        }
    }

    static var completed: String {
        switch language {
        case .simplifiedChinese: return "任务完成，做得好！"
        case .english: return "Task complete. Nicely done!"
        case .japanese: return "完了しました。おつかれさま！"
        case .korean: return "작업 완료! 수고했어요!"
        }
    }

    static var fed: String {
        switch language {
        case .simplifiedChinese: return "能量补充好了！"
        case .english: return "Energy restored!"
        case .japanese: return "元気をチャージ！"
        case .korean: return "에너지를 채웠어요!"
        }
    }

    static var rest: String {
        switch language {
        case .simplifiedChinese: return "我也在休息。"
        case .english: return "Taking a quiet moment."
        case .japanese: return "少し休憩中です。"
        case .korean: return "잠시 쉬고 있어요."
        }
    }

    static var breakTime: String {
        switch language {
        case .simplifiedChinese: return "连续工作一段时间了，休息一下吧。"
        case .english: return "You’ve been at it a while — take a short break."
        case .japanese: return "少し続けて作業しました。短い休憩をどうぞ。"
        case .korean: return "한참 집중했어요. 잠깐 쉬어가요."
        }
    }

    static var choosePackFolder: String {
        switch language {
        case .simplifiedChinese: return "选择包含 pet.json 和透明 PNG 精灵图的宠物包文件夹"
        case .english: return "Choose a pet pack folder containing pet.json and a transparent PNG sprite"
        case .japanese: return "pet.json と透明 PNG スプライトを含むペットパックを選択"
        case .korean: return "pet.json과 투명 PNG 스프라이트가 있는 펫 팩 폴더를 선택하세요"
        }
    }

    static var importPack: String {
        switch language {
        case .simplifiedChinese: return "导入宠物包"
        case .english: return "Import Pet Pack"
        case .japanese: return "ペットパックを読み込む"
        case .korean: return "펫 팩 가져오기"
        }
    }

    static var invalidPack: String {
        switch language {
        case .simplifiedChinese: return "这个宠物包缺少有效的 pet.json 或精灵图。"
        case .english: return "This pet pack is missing a valid pet.json or sprite."
        case .japanese: return "有効な pet.json またはスプライトが見つかりません。"
        case .korean: return "유효한 pet.json 또는 스프라이트가 없습니다."
        }
    }

    static var packImported: String {
        switch language {
        case .simplifiedChinese: return "新伙伴加入了！"
        case .english: return "A new companion joined!"
        case .japanese: return "新しい仲間が加わりました！"
        case .korean: return "새 친구가 합류했어요!"
        }
    }

    static var packImportFailed: String {
        switch language {
        case .simplifiedChinese: return "导入宠物包失败。"
        case .english: return "Couldn’t import that pet pack."
        case .japanese: return "ペットパックを読み込めませんでした。"
        case .korean: return "펫 팩을 가져오지 못했어요."
        }
    }

    static var chooseProjectFolder: String {
        switch language {
        case .simplifiedChinese: return "选择要绑定专属宠物的项目文件夹"
        case .english: return "Choose a project folder for a dedicated pet"
        case .japanese: return "専用ペットを割り当てるプロジェクトフォルダを選択"
        case .korean: return "전용 펫을 연결할 프로젝트 폴더를 선택하세요"
        }
    }

    static var addProject: String {
        switch language {
        case .simplifiedChinese: return "添加项目"
        case .english: return "Add Project"
        case .japanese: return "プロジェクトを追加"
        case .korean: return "프로젝트 추가"
        }
    }
}
