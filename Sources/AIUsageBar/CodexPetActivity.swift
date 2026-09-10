import Foundation

/// The Codex rollout log records task lifecycle messages independently from
/// token-count entries.  Reading those small, recent tails lets the desktop
/// pet represent live task state instead of guessing from a usage increase.
enum CodexPetTaskState: String, Hashable, Sendable {
    case running
    case completed
    case blocked
}

/// A deliberately coarse activity category for the desktop pet.  The rollout
/// scanner only derives this from event/tool metadata; it never retains
/// prompts, responses, command arguments, file contents, or credentials.
enum CodexPetTaskAction: String, Hashable, Sendable {
    case starting
    case thinking
    case runningCommand
    case editingFiles
    case readingFiles
    case searchingWeb
    case callingTool
    case waitingForInput
}

struct CodexPetTaskActivity: Identifiable, Hashable, Sendable {
    let id: String
    let state: CodexPetTaskState
    let projectPath: String?
    let model: String?
    let action: CodexPetTaskAction?
    let startedAt: Date
    let updatedAt: Date
}

/// A small, serially-used monitor for the current (not archived) Codex
/// rollouts.  It intentionally reads only recent file tails and only lifecycle
/// metadata: no prompt, response, credential, or tool arguments are retained.
final class CodexPetActivityMonitor: @unchecked Sendable {
    private struct FileCandidate {
        let url: URL
        let modifiedAt: Date
        let size: Int64
    }

    private struct FileCacheEntry {
        let modifiedAt: Date
        let size: Int64
        let activities: [CodexPetTaskActivity]
        let currentTurnID: String?
    }

    private struct TailScanResult {
        let activities: [CodexPetTaskActivity]
        let currentTurnID: String?
    }

    private let lock = NSLock()
    private var knownFiles: [URL] = []
    private var fileCache: [URL: FileCacheEntry] = [:]
    private var lastDiscovery = Date.distantPast

    private let discoveryInterval: TimeInterval = 2
    private let recentFileWindow: TimeInterval = 20 * 60
    // A task_started record can survive a crashed or closed Codex turn without
    // a matching terminal record.  The scanner also refreshes this timestamp
    // from recent turn activity below, so this is a safety limit for genuinely
    // abandoned turns rather than a limit on the duration of active work.
    private let runningActivityWindow: TimeInterval = 15 * 60
    // A historical turn_aborted record is not proof that the conversation is
    // still blocked. Keep only recent blocked events eligible for the live
    // pet state; the full rollout history remains untouched.
    private let blockedActivityWindow: TimeInterval = 30 * 60
    private let maximumFiles = 12
    private let bootstrapTailBytes = 512 * 1024
    private let changedTailBytes = 256 * 1024

    func refresh() -> [CodexPetTaskActivity] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if now.timeIntervalSince(lastDiscovery) >= discoveryInterval {
            knownFiles = Self.rolloutFiles()
            lastDiscovery = now
        }

        let cutoff = now.addingTimeInterval(-recentFileWindow)
        let candidates = knownFiles.compactMap { url -> FileCandidate? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff
            else { return nil }
            return FileCandidate(
                url: url,
                modifiedAt: modifiedAt,
                size: max(Int64(values.fileSize ?? 0), 0)
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
        .prefix(maximumFiles)

        let candidateURLs = Set(candidates.map { $0.url })
        fileCache = fileCache.filter { candidateURLs.contains($0.key) }

        var newestByID: [String: CodexPetTaskActivity] = [:]
        for candidate in candidates {
            let activities: [CodexPetTaskActivity]
            if let cached = fileCache[candidate.url],
               cached.modifiedAt == candidate.modifiedAt,
               cached.size == candidate.size {
                activities = cached.activities
            } else {
                // A larger bootstrap tail makes an already-running task
                // discoverable at launch. Subsequent refreshes only inspect
                // a compact tail of files that actually changed. Carry the
                // previous lifecycle state into that compact scan: a long
                // running turn can have its task_started record far outside
                // the tail while its latest response activity is still near
                // the end of the file.
                let cachedState = fileCache[candidate.url]
                let canContinuePreviousScan = cachedState.map {
                    candidate.size >= $0.size
                } ?? false
                let maximumBytes = fileCache[candidate.url] == nil
                    ? bootstrapTailBytes
                    : changedTailBytes
                let scan = Self.scanTail(
                    at: candidate.url,
                    modifiedAt: candidate.modifiedAt,
                    maximumBytes: maximumBytes,
                    seedActivities: canContinuePreviousScan ? (cachedState?.activities ?? []) : [],
                    seedCurrentTurnID: canContinuePreviousScan ? cachedState?.currentTurnID : nil
                )
                activities = scan.activities
                fileCache[candidate.url] = FileCacheEntry(
                    modifiedAt: candidate.modifiedAt,
                    size: candidate.size,
                    activities: activities,
                    currentTurnID: scan.currentTurnID
                )
            }

            for activity in activities {
                if let previous = newestByID[activity.id], previous.updatedAt > activity.updatedAt {
                    continue
                }
                newestByID[activity.id] = activity
            }
        }
        return newestByID.values
            .filter { activity in
                switch activity.state {
                case .running:
                    return now.timeIntervalSince(activity.updatedAt) <= runningActivityWindow
                case .blocked:
                    return now.timeIntervalSince(activity.updatedAt) <= blockedActivityWindow
                case .completed:
                    return true
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func rolloutFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: AppPaths.codexSessions.path),
              let enumerator = FileManager.default.enumerator(
                at: AppPaths.codexSessions,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
              )
        else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-")
            else { continue }
            result.append(url.resolvingSymlinksInPath().standardizedFileURL)
        }
        return result
    }

    private static func scanTail(
        at url: URL,
        modifiedAt: Date,
        maximumBytes: Int,
        seedActivities: [CodexPetTaskActivity] = [],
        seedCurrentTurnID: String? = nil
    ) -> TailScanResult {
        guard let data = tailData(at: url, maximumBytes: maximumBytes) else {
            return TailScanResult(activities: seedActivities, currentTurnID: seedCurrentTurnID)
        }

        struct TurnContext {
            var projectPath: String?
            var model: String?
        }
        struct MutableActivity {
            var state: CodexPetTaskState
            var startedAt: Date
            var updatedAt: Date
            var context: TurnContext
            var action: CodexPetTaskAction?
        }

        var sessionContext = TurnContext()
        var contexts: [String: TurnContext] = [:]
        var tasks = Dictionary(
            uniqueKeysWithValues: seedActivities.map { activity in
                (
                    activity.id,
                    MutableActivity(
                        state: activity.state,
                        startedAt: activity.startedAt,
                        updatedAt: activity.updatedAt,
                        context: TurnContext(
                            projectPath: activity.projectPath,
                            model: activity.model
                        ),
                        action: activity.action
                    )
                )
            }
        )
        var currentTurnID = seedCurrentTurnID

        func taskID(for turnID: String) -> String {
            "codex-log:\(url.path):\(turnID)"
        }

        func touchRunningTask(
            _ turnID: String,
            at timestamp: Date,
            action: CodexPetTaskAction? = nil
        ) {
            let id = taskID(for: turnID)
            if var task = tasks[id] {
                guard task.state == .running else { return }
                task.updatedAt = max(task.updatedAt, timestamp)
                if let action {
                    task.action = action
                }
                tasks[id] = task
            } else {
                // The tail may begin after task_started. A turn_context,
                // token_usage_record, or recent response event still proves
                // that this turn is active, so recover a lightweight running
                // row instead of dropping it as an unknown event.
                tasks[id] = MutableActivity(
                    state: .running,
                    startedAt: timestamp,
                    updatedAt: timestamp,
                    context: contexts[turnID] ?? sessionContext,
                    action: action
                )
            }
        }

        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let object = LocalData.parseJSON(data: Data(rawLine)) as? [String: Any] else { continue }
            let outerType = LocalData.string(object["type"])
            let payload = object["payload"] as? [String: Any] ?? [:]
            let objectTimestamp = LocalData.date(object["timestamp"]) ?? modifiedAt

            if outerType == "session_meta" {
                sessionContext.projectPath = LocalData.string(payload["cwd"]) ?? sessionContext.projectPath
                continue
            }

            if outerType == "turn_context" {
                guard let turnID = LocalData.string(payload["turn_id"]), !turnID.isEmpty else { continue }
                let context = TurnContext(
                    projectPath: LocalData.string(payload["cwd"]) ?? sessionContext.projectPath,
                    model: LocalData.string(payload["model"])
                )
                contexts[turnID] = context
                currentTurnID = turnID
                touchRunningTask(turnID, at: objectTimestamp)
                continue
            }

            if outerType == "token_usage_record",
               let turnID = LocalData.string(object["turn_id"]),
               !turnID.isEmpty {
                currentTurnID = turnID
                touchRunningTask(turnID, at: objectTimestamp)
                continue
            }

            if outerType == "response_item" {
                let responseTurnID = [
                    LocalData.string(payload["turn_id"]),
                    LocalData.string(object["turn_id"])
                ]
                .compactMap { $0 }
                .first { !$0.isEmpty }
                if let responseTurnID {
                    currentTurnID = responseTurnID
                }

                if let action = Self.action(forResponseItem: payload),
                   let turnID = responseTurnID ?? currentTurnID,
                   !turnID.isEmpty {
                    touchRunningTask(turnID, at: objectTimestamp, action: action)
                }
                continue
            }

            guard outerType == "event_msg",
                  let eventType = LocalData.string(payload["type"]) else { continue }

            let explicitTurnID = [
                LocalData.string(payload["turn_id"]),
                LocalData.string(payload["turnId"]),
                LocalData.string(payload["turnID"]),
                LocalData.string(object["turn_id"]),
                LocalData.string(object["turnId"]),
                LocalData.string(object["turnID"])
            ]
            .compactMap { $0 }
            .first { !$0.isEmpty }
            let timestamp = LocalData.date(
                payload["completed_at"]
                    ?? payload["started_at"]
                    ?? object["timestamp"]
            ) ?? modifiedAt

            guard ["task_started", "task_complete", "turn_aborted"].contains(eventType) else {
                let turnID = explicitTurnID ?? currentTurnID
                if let turnID, !turnID.isEmpty {
                    touchRunningTask(
                        turnID,
                        at: timestamp,
                        action: Self.action(forEventType: eventType)
                    )
                }
                continue
            }

            guard let turnID = explicitTurnID, !turnID.isEmpty else { continue }

            let context = contexts[turnID] ?? sessionContext
            // The rollout path plus turn ID stays stable even when the tail
            // no longer includes the early session_meta record.
            let id = taskID(for: turnID)
            let existing = tasks[id]

            switch eventType {
            case "task_started":
                tasks[id] = MutableActivity(
                    state: .running,
                    startedAt: timestamp,
                    updatedAt: timestamp,
                    context: context,
                    action: .starting
                )
                currentTurnID = turnID
            case "task_complete":
                tasks[id] = MutableActivity(
                    state: .completed,
                    startedAt: existing?.startedAt ?? timestamp,
                    updatedAt: timestamp,
                    context: existing?.context ?? context,
                    action: existing?.action
                )
                if currentTurnID == turnID {
                    currentTurnID = nil
                }
            case "turn_aborted":
                tasks[id] = MutableActivity(
                    state: .blocked,
                    startedAt: existing?.startedAt ?? timestamp,
                    updatedAt: timestamp,
                    context: existing?.context ?? context,
                    action: existing?.action
                )
                if currentTurnID == turnID {
                    currentTurnID = nil
                }
            default:
                break
            }
        }

        return TailScanResult(
            activities: tasks.map { id, task in
            CodexPetTaskActivity(
                id: id,
                state: task.state,
                projectPath: task.context.projectPath,
                model: task.context.model,
                action: task.action,
                startedAt: task.startedAt,
                updatedAt: task.updatedAt
            )
            },
            currentTurnID: currentTurnID
        )
    }

    private static func action(forResponseItem payload: [String: Any]) -> CodexPetTaskAction? {
        let responseType = normalized(LocalData.string(payload["type"]))
        if responseType.contains("reason") {
            return .thinking
        }

        let toolCallTypes = [
            "custom_tool_call",
            "custom_tool_call_output",
            "function_call",
            "function_call_output",
            "tool_call",
            "tool_call_output",
            "computer_call",
            "web_search_call"
        ]
        guard toolCallTypes.contains(responseType) else { return nil }
        return action(
            forToolName: LocalData.string(payload["name"]),
            namespace: LocalData.string(payload["namespace"]),
            responseType: responseType
        )
    }

    private static func action(
        forToolName name: String?,
        namespace: String?,
        responseType: String?
    ) -> CodexPetTaskAction {
        let tool = normalized([namespace, name].compactMap { $0 }.joined(separator: " "))
        let type = normalized(responseType)

        if type == "web_search_call" || containsAny(tool, ["web", "search", "browser"]) {
            return .searchingWeb
        }
        if containsAny(tool, ["request_user_input", "user_input", "approval", "ask_user"]) {
            return .waitingForInput
        }
        if containsAny(tool, ["apply_patch", "edit_file", "write_file", "replace", "patch"]) {
            return .editingFiles
        }
        if containsAny(tool, ["exec_command", "run_command", "shell", "terminal", "command"]) {
            return .runningCommand
        }
        if containsAny(tool, ["view_image", "read_mcp_resource", "read_file", "open_in_codex", "file"]) {
            return .readingFiles
        }
        return .callingTool
    }

    private static func action(forEventType eventType: String) -> CodexPetTaskAction? {
        let type = normalized(eventType)
        if type.contains("reason") {
            return .thinking
        }
        if containsAny(type, ["apply_patch", "file_edit", "write_file", "patch_apply"]) {
            return .editingFiles
        }
        if containsAny(type, ["exec_command", "run_command", "shell", "terminal"]) {
            return .runningCommand
        }
        if containsAny(type, ["web_search", "browser_search", "search_web"]) {
            return .searchingWeb
        }
        if containsAny(type, ["request_user_input", "approval", "needs_input"]) {
            return .waitingForInput
        }
        if type.contains("mcp") && type.contains("call") {
            return .callingTool
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String {
        normalized(value ?? "")
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func containsAny(_ value: String, _ fragments: [String]) -> Bool {
        fragments.contains { value.contains($0) }
    }

    private static func tailData(at url: URL, maximumBytes: Int) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        let size = max(Int64(values.fileSize ?? 0), 0)
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let offset = max(size - Int64(maximumBytes), 0)
        if offset > 0 {
            try? handle.seek(toOffset: UInt64(offset))
        }
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        // The first partial line in a tail cannot be parsed safely.  Retain
        // only complete JSONL records, then parse the rest independently.
        if offset > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(...firstNewline)
        }
        return data
    }
}
