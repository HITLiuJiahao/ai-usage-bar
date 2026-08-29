import Foundation

enum AppPaths {
    static let fileManager = FileManager.default
    static let home = fileManager.homeDirectoryForCurrentUser

    static let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
    static let codexSessions = codexRoot.appendingPathComponent("sessions", isDirectory: true)
    static let codexArchivedSessions = codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)

    static let workBuddyRoot = home.appendingPathComponent(".workbuddy", isDirectory: true)
    static let workBuddyProjects = workBuddyRoot.appendingPathComponent("projects", isDirectory: true)
    /// WorkBuddy persists one authoritative credit-consumption event per
    /// streamed response in this log tree.
    static let workBuddyLogs = workBuddyRoot.appendingPathComponent("logs", isDirectory: true)
    static let workBuddyAuthFile = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("CodeBuddyExtension", isDirectory: true)
        .appendingPathComponent("Data", isDirectory: true)
        .appendingPathComponent("Public", isDirectory: true)
        .appendingPathComponent("auth", isDirectory: true)
        .appendingPathComponent("workbuddy-desktop.info")

    static let qwenRoot = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("QwenWorkCN", isDirectory: true)
    /// The consumer Qianwen desktop app keeps its agent sessions separately
    /// from QwenWorkCN.  Its office mode writes one event stream per thread
    /// below `qwen-agent/<account>/projects/.../sessions/...`.
    static let qianwenDesktopSupport = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Qianwen", isDirectory: true)
    static let qianwenAgentRoot = qianwenDesktopSupport
        .appendingPathComponent("qwen-agent", isDirectory: true)
    static let qwenWorkRoot = home.appendingPathComponent(".qwenworkcn", isDirectory: true)
    /// QwenWorkCN stores one JSONL transcript per session below this folder.
    /// The layout is `projects/<workspace>/<session>.jsonl`; sub-agent
    /// transcripts may be nested below the session directory as well.
    static let qwenWorkProjects = qwenWorkRoot
        .appendingPathComponent("projects", isDirectory: true)
    static let qwenWorkLogs = qwenWorkRoot
        .appendingPathComponent("logs", isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)
    static let qwenWorkLogRoots = [qwenWorkProjects, qwenWorkLogs]
    static let qwenStatusSnapshot = qwenWorkRoot.appendingPathComponent(".status.json")
    static let qwenAuthFallbackCandidates = [
        qwenRoot.appendingPathComponent("auth-v2.dat.json"),
        qwenRoot.appendingPathComponent("auth.dat.json")
    ]
    static let qwenDatabase = qwenRoot.appendingPathComponent("data/agents.db")

    /// ZCode stores its local App Usage ledger in the CLI data directory.
    /// The desktop app and its bundled CLI share this SQLite database.
    static let zcodeRoot = home.appendingPathComponent(".zcode", isDirectory: true)
    static let zcodeDatabaseCandidates = [
        zcodeRoot
            .appendingPathComponent("cli", isDirectory: true)
            .appendingPathComponent("db", isDirectory: true)
            .appendingPathComponent("db.sqlite"),
        zcodeRoot
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("db", isDirectory: true)
            .appendingPathComponent("db.sqlite"),
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ZCode", isDirectory: true)
            .appendingPathComponent("db.sqlite")
    ]

    /// OpenCode stores its message ledger in an SQLite database. The
    /// XDG path is the default used by the official CLI; the Application
    /// Support and config paths cover macOS installations that override it.
    static var openCodeDatabaseCandidates: [URL] {
        var roots: [URL] = []
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
           !xdgDataHome.isEmpty {
            roots.append(URL(fileURLWithPath: xdgDataHome, isDirectory: true))
        }
        roots.append(contentsOf: [
            home
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true),
            home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true),
            home.appendingPathComponent(".config", isDirectory: true)
        ])

        var seen: Set<String> = []
        return roots.compactMap { root in
            let directory = root.appendingPathComponent("opencode", isDirectory: true)
            guard seen.insert(directory.path).inserted else { return nil }
            return directory.appendingPathComponent("opencode.db")
        }
    }

    /// Doubao Work keeps model-usage and task records in the chat IndexedDB
    /// store, its network-event ledger in Tea, and mirrors recent events in
    /// SDK logs.
    static let doubaoWorkRoot = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("DoubaoWork", isDirectory: true)
    static let doubaoWorkTeaDatabase = doubaoWorkRoot
        .appendingPathComponent("Tea", isDirectory: true)
        .appendingPathComponent("tea.db", isDirectory: true)
    static let doubaoWorkChatDatabase = doubaoWorkRoot
        .appendingPathComponent("Default", isDirectory: true)
        .appendingPathComponent("IndexedDB", isDirectory: true)
        .appendingPathComponent("chrome_doubaowork-chat_0.indexeddb.leveldb", isDirectory: true)
    static let doubaoWorkSDKLogs = doubaoWorkRoot
        .appendingPathComponent("sdk_storage", isDirectory: true)
        .appendingPathComponent("log", isDirectory: true)

    static let deepSeekHarnessRoot = home.appendingPathComponent(".dsh", isDirectory: true)
    static let deepSeekHarnessSessions = deepSeekHarnessRoot
        .appendingPathComponent("sessions", isDirectory: true)

    static let miniMaxSupport = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("MiniMax", isDirectory: true)
    static let miniMaxConfig = miniMaxSupport.appendingPathComponent("minimax-agent-cn-config.json")
    static let miniMaxRoot = home.appendingPathComponent(".minimax", isDirectory: true)
    /// MiniMax Code keeps its local runtime ledger in this SQLite database.
    /// The path is deliberately kept separate from the browser cache above:
    /// the ledger is the source that contains one token-usage row per model
    /// response.
    static let miniMaxRuntimeDatabase = miniMaxRoot
        .appendingPathComponent("v2", isDirectory: true)
        .appendingPathComponent("sqlite", isDirectory: true)
        .appendingPathComponent("runtime-state.sqlite")
    static let miniMaxSessions = miniMaxRoot
        .appendingPathComponent("v2", isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)

    static let codexAuthCandidates = [
        codexRoot.appendingPathComponent("auth.json"),
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Codex/auth.json")
    ]

    static let appSupport = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("AIUsageBar", isDirectory: true)

    /// The last successful provider snapshots are kept here so local usage
    /// remains visible when a client is closed, its database is temporarily
    /// locked, or AI Usage Bar itself is restarted.
    static let usageSnapshotCache = appSupport.appendingPathComponent("usage-snapshots.json")
    static let doubaoWorkScanCache = appSupport.appendingPathComponent("doubao-work-scan-cache.json")
}
