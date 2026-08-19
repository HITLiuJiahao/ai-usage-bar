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

    /// TRAE Work desktop builds use these two Electron application-support
    /// roots.  `TRAE SOLO CN` is the CN build name used by current releases;
    /// `TRAE SOLO` is kept for older/current international-branded builds.
    static let traeWorkSupportCandidates = [
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("TRAE SOLO CN", isDirectory: true),
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("TRAE SOLO", isDirectory: true),
    ]

    static let traeChinaSupportCandidates = [
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Trae CN", isDirectory: true)
    ]

    /// Kept as a combined list for compatibility with older local readers.
    static let traeSupportCandidates = traeWorkSupportCandidates + traeChinaSupportCandidates

    /// Trae's local usage ledger. `TRAE SOLO CN` is the current TraeWork CN
    /// application-support root; the standalone `Trae CN` root is kept for
    /// older installs. Keep CN roots ahead of the international root because
    /// the same machine can have both clients installed.
    static let traeDatabaseCandidates = [
        traeWorkSupportCandidates[0],
        traeChinaSupportCandidates[0],
        traeWorkSupportCandidates[1]
    ].map {
        $0.appendingPathComponent("ModularData/ai-agent/database.db")
    }

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
}
