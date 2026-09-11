import Foundation

struct DoubaoWorkScanResult {
    let summary: LocalUsageSummary
    let modelUsages: [ModelUsage]
    let responseCount: Int
    let hasLogFiles: Bool
    let countSource: DoubaoWorkCountSource
}

enum DoubaoWorkCountSource {
    case chatUsage
    case taskLedger
    case networkRequests
    case combined
    case none
}

private struct DoubaoWorkRequest: Codable {
    let date: Date
    let requestStartDate: Date?
    let requestEndDate: Date?
    let path: String
    let statusCode: Int?
    let requestSize: Double?
    let responseSize: Double?
    let durationMilliseconds: Double?
    let model: String?
}

private struct DoubaoWorkFile {
    let url: URL
    let size: Int64
    let modifiedAt: Double
}

private struct DoubaoWorkFileEntry: Codable {
    let size: Int64
    let modifiedAt: Double
    let requests: [DoubaoWorkRequest]
}

private struct DoubaoWorkTask: Codable, Equatable {
    let id: String
    let date: Date
}

private struct DoubaoWorkModelEvent: Codable, Equatable {
    let id: String
    let date: Date
    let model: String?
}

private struct DoubaoWorkChatScan {
    let modernEvents: [DoubaoWorkModelEvent]
    let legacyEvents: [DoubaoWorkModelEvent]
}

private struct DoubaoWorkUsageDay {
    let date: Date
    let count: Int
}

private struct DoubaoWorkScanCache: Codable {
    let version: Int
    let files: [String: DoubaoWorkFileEntry]
    let archivedRequests: [DoubaoWorkRequest]
    let tasks: [DoubaoWorkTask]
    let modelEvents: [DoubaoWorkModelEvent]

    init(
        version: Int,
        files: [String: DoubaoWorkFileEntry],
        archivedRequests: [DoubaoWorkRequest] = [],
        tasks: [DoubaoWorkTask] = [],
        modelEvents: [DoubaoWorkModelEvent] = []
    ) {
        self.version = version
        self.files = files
        self.archivedRequests = archivedRequests
        self.tasks = tasks
        self.modelEvents = modelEvents
    }
}

enum DoubaoWorkUsageScanner {
    // Version 7 also keeps a best-effort model name when the local record
    // exposes model/model_name/model_id (or an equivalent engine field).
    // Version 6 counts the local chat record's ext_window_usage entries when
    // available, while also retaining the Tea/SDK completion ledger. A single
    // Work-mode task can make several model calls, so task/message IDs are
    // only a fallback and must not be used as the primary request count. The
    // long-lived local-tool SSE channel is not a usage counter: it reconnects
    // periodically while the app is idle. The cache also stores requests from
    // retired log files and uses request start times for daily buckets.
    private static let cacheVersion = 7
    private static let cacheOverlapBytes: Int64 = 2 * 1024 * 1024
    private static let completionPaths: Set<String> = [
        "/chat/completion",
        "/samantha/chat/completion"
    ]
    private static let eventMarker = Data("{\"events\":".utf8)
    private static let taskMarker = Array("thread_local_message_id".utf8)
    private static let chatFolderMarker = Array("/DoubaoWork/chats/".utf8)
    private static let modelUsageMarker = Array("ext_window_usage\"\\{".utf8)
    private static let legacyModelUsageMarker = Array("usage\"\\{\"system_prompt\"".utf8)
    private static let taskContextMarkers = [
        Array("general_task_param".utf8),
        Array("/DoubaoWork/chats/".utf8)
    ]

    static func scan() -> DoubaoWorkScanResult {
        let files = logFiles()
        let chatFiles = chatDatabaseFiles()
        let previous = loadCache()
        var current: [String: DoubaoWorkFileEntry] = [:]
        var archivedRequests = previous?.archivedRequests ?? []
        let chatScans = chatFiles.map(parseChatUsage)
        let hasModernModelEvents = chatScans.contains { !$0.modernEvents.isEmpty }
        let detectedModelEvents = chatScans.flatMap {
            hasModernModelEvents ? $0.modernEvents : $0.legacyEvents
        }
        let modelEvents = mergedModelEvents((previous?.modelEvents ?? []) + detectedModelEvents)
        let detectedTasks = chatFiles.flatMap(parseTasks)
        let tasks = mergedTasks((previous?.tasks ?? []) + detectedTasks)
        var cacheDirty = previous == nil

        for file in files {
            let key = file.url.resolvingSymlinksInPath().standardizedFileURL.path
            if let cached = previous?.files[key],
               cached.size == file.size,
               cached.modifiedAt == file.modifiedAt {
                current[key] = cached
                continue
            }

            let requests: [DoubaoWorkRequest]
            if let cached = previous?.files[key],
               file.size > cached.size,
               cached.size > 0 {
                // The active Tea/SDK files are append-only in normal use. Read
                // only a small overlap around the old end so an event split
                // across reads is still found; aggregate deduplication removes
                // requests repeated inside that overlap.
                let offset = max(cached.size - cacheOverlapBytes, 0)
                requests = mergeRequests(
                    cached.requests,
                    parseFile(at: file.url, from: offset)
                )
            } else {
                requests = parseFile(at: file.url, from: 0)
            }

            if let cached = previous?.files[key] {
                // The file changed in place, so requests that were already
                // observed may no longer be present after truncation or
                // replacement. Keep them in the retired-log archive; the
                // global identity check below removes any duplicates.
                archivedRequests.append(contentsOf: cached.requests)
            }

            current[key] = DoubaoWorkFileEntry(
                size: file.size,
                modifiedAt: file.modifiedAt,
                requests: requests
            )
            cacheDirty = true
        }

        if let previous {
            // A rotated file disappears from the filesystem, but its usage
            // is still part of the historical total.
            for (key, entry) in previous.files where current[key] == nil {
                archivedRequests.append(contentsOf: entry.requests)
            }
        }

        let activeRequests = current.values.flatMap(\.requests)
        let allRequests = deduplicated(activeRequests + archivedRequests)
        let activeKeys = Set(activeRequests.map(deduplicationKey(for:)))
        archivedRequests = allRequests.filter {
            !activeKeys.contains(deduplicationKey(for: $0))
        }

        if let previous,
           Set(previous.files.keys) != Set(current.keys) ||
           previous.archivedRequests.count != archivedRequests.count ||
           previous.tasks != tasks ||
           previous.modelEvents != modelEvents ||
           previous.version != cacheVersion {
            cacheDirty = true
        }
        if cacheDirty {
            saveCache(DoubaoWorkScanCache(
                version: cacheVersion,
                files: current,
                archivedRequests: archivedRequests,
                tasks: tasks,
                modelEvents: modelEvents
            ))
        }

        let successfulRequests = allRequests.filter { isSuccessful($0.statusCode) }
        if !modelEvents.isEmpty || !successfulRequests.isEmpty {
            let usageDays = mergedUsageDays(
                modelEvents: modelEvents,
                requests: successfulRequests
            )
            var summary = LocalUsageSummary()
            for usageDay in usageDays {
                summary.add(
                    date: usageDay.date,
                    tokens: nil,
                    requests: Double(usageDay.count)
                )
            }
            let modelSummary = modelUsageSummary(
                modelEvents: modelEvents,
                requests: successfulRequests
            )
            return DoubaoWorkScanResult(
                summary: summary,
                modelUsages: UsageMetrics.modelUsages(summary: modelSummary),
                responseCount: usageDays.reduce(0) { $0 + $1.count },
                hasLogFiles: !files.isEmpty || !chatFiles.isEmpty,
                countSource: modelEvents.isEmpty
                    ? .networkRequests
                    : successfulRequests.isEmpty
                        ? .chatUsage
                        : .combined
            )
        }

        if !tasks.isEmpty {
            var summary = LocalUsageSummary()
            for task in tasks {
                summary.add(date: task.date, tokens: nil, requests: 1)
            }
            return DoubaoWorkScanResult(
                summary: summary,
                modelUsages: [],
                responseCount: tasks.count,
                hasLogFiles: !files.isEmpty || !chatFiles.isEmpty,
                countSource: .taskLedger
            )
        }

        return DoubaoWorkScanResult(
            summary: LocalUsageSummary(),
            modelUsages: [],
            responseCount: 0,
            hasLogFiles: !files.isEmpty || !chatFiles.isEmpty,
            countSource: .none
        )
    }

    private static func modelUsageSummary(
        modelEvents: [DoubaoWorkModelEvent],
        requests: [DoubaoWorkRequest]
    ) -> LocalUsageSummary {
        var summary = LocalUsageSummary()
        let knownEvents = modelEvents.filter { $0.model != nil }

        // Chat usage entries are the more direct signal: one entry represents
        // one model call, while the network ledger can contain a mirror of the
        // same request. Use the ledger only when chat records did not expose a
        // model at all.
        if !knownEvents.isEmpty {
            for event in knownEvents {
                summary.add(
                    date: event.date,
                    tokens: nil,
                    requests: 1,
                    model: event.model
                )
            }
        } else {
            for request in requests {
                guard let model = request.model else { continue }
                summary.add(
                    date: request.date,
                    tokens: nil,
                    requests: 1,
                    model: model
                )
            }
        }
        return summary
    }

    private static func mergedUsageDays(
        modelEvents: [DoubaoWorkModelEvent],
        requests: [DoubaoWorkRequest],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [DoubaoWorkUsageDay] {
        struct DayCounts {
            var modelEvents = 0
            var requests = 0
            var latestDate: Date?
        }

        var counts: [Date: DayCounts] = [:]
        let upperBound = Date().addingTimeInterval(60)

        for event in modelEvents where event.date <= upperBound {
            let day = calendar.startOfDay(for: event.date)
            var value = counts[day] ?? DayCounts()
            value.modelEvents += 1
            if value.latestDate == nil || event.date > value.latestDate! {
                value.latestDate = event.date
            }
            counts[day] = value
        }

        for request in requests where request.date <= upperBound {
            let day = calendar.startOfDay(for: request.date)
            var value = counts[day] ?? DayCounts()
            value.requests += 1
            if value.latestDate == nil || request.date > value.latestDate! {
                value.latestDate = request.date
            }
            counts[day] = value
        }

        return counts.map { day, value in
            DoubaoWorkUsageDay(
                date: value.latestDate ?? day,
                count: max(value.modelEvents, value.requests)
            )
        }
        .filter { $0.count > 0 }
        .sorted { $0.date < $1.date }
    }

    private static func logFiles() -> [DoubaoWorkFile] {
        let roots = [AppPaths.doubaoWorkTeaDatabase, AppPaths.doubaoWorkSDKLogs]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var candidates: [DoubaoWorkFile] = []

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(
                      at: root,
                      includingPropertiesForKeys: Array(keys),
                      options: [.skipsPackageDescendants]
                  ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true else { continue }
                candidates.append(DoubaoWorkFile(
                    url: url,
                    size: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
                ))
            }
        }
        return candidates.sorted { $0.url.path < $1.url.path }
    }

    private static func chatDatabaseFiles() -> [DoubaoWorkFile] {
        let root = AppPaths.doubaoWorkChatDatabase
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: Array(keys),
                  options: [.skipsPackageDescendants]
              ) else {
            return []
        }

        var files: [DoubaoWorkFile] = []
        for case let url as URL in enumerator {
            guard ["ldb", "log"].contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            files.append(DoubaoWorkFile(
                url: url,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            ))
        }
        return files.sorted { $0.url.path < $1.url.path }
    }

    private static func parseChatUsage(in file: DoubaoWorkFile) -> DoubaoWorkChatScan {
        guard let data = readData(at: file.url, from: 0) else {
            return DoubaoWorkChatScan(modernEvents: [], legacyEvents: [])
        }
        let bytes = Array(data)
        let chatDate = chatDay(in: bytes)
            ?? Date(timeIntervalSince1970: file.modifiedAt)
        let modernPositions = positions(of: modelUsageMarker, in: bytes)
        let legacyPositions = positions(of: legacyModelUsageMarker, in: bytes)
        return DoubaoWorkChatScan(
            modernEvents: modelEvents(
                positions: modernPositions,
                bytes: bytes,
                fallbackDate: chatDate,
                marker: modelUsageMarker
            ),
            legacyEvents: modelEvents(
                positions: legacyPositions,
                bytes: bytes,
                fallbackDate: chatDate,
                marker: legacyModelUsageMarker
            )
        )
    }

    private static func modelEvents(
        positions: [Int],
        bytes: [UInt8],
        fallbackDate: Date,
        marker: [UInt8]
    ) -> [DoubaoWorkModelEvent] {
        positions.enumerated().map { ordinal, position in
            let nextPosition = positions.dropFirst(ordinal + 1).first ?? bytes.count
            let end = min(nextPosition, position + 64 * 1024)
            let identity = stableIdentity(in: bytes, range: position..<end)
            let payloadStart = min(position + marker.count, end)
            let model = modelName(
                in: bytes,
                range: payloadStart..<end
            ) ?? modelName(
                in: bytes,
                range: max(position - 8 * 1024, 0)..<end
            )
            return DoubaoWorkModelEvent(
                id: "chat-usage-\(identity)",
                date: chatDay(in: bytes, around: position) ?? fallbackDate,
                model: model
            )
        }
    }

    private static let modelFieldNames = [
        "model_name", "modelName",
        "model_id", "modelId",
        "model_slug", "modelSlug",
        "model_alias", "modelAlias",
        "model_type", "modelType",
        "model_key", "modelKey",
        "model", "engine"
    ]

    private static func modelName(
        from value: Any?
    ) -> String? {
        guard let value else { return nil }
        if let model = normalizedModelName(LocalData.modelName(in: value)) {
            return model
        }

        // Some clients serialize the selection as {"model":{"id":...}}
        // instead of a scalar model field.
        guard let modelObject = LocalData.firstObject(
            in: value,
            keys: ["model", "modeldata", "modelinfo", "engine"]
        ) else {
            return nil
        }
        return normalizedModelName(LocalData.firstString(
            in: modelObject,
            keys: [
                "name", "id", "slug", "alias", "model", "modelname", "modelid"
            ]
        ))
    }

    private static func modelName(
        in bytes: [UInt8],
        range: Range<Int>
    ) -> String? {
        guard range.lowerBound >= 0,
              range.upperBound <= bytes.count,
              range.lowerBound < range.upperBound else {
            return nil
        }

        // Prefer ordinary JSON because it preserves escaping and field
        // boundaries. Chat IndexedDB values are often structured-clone data,
        // so the printable-string fallback below handles that representation.
        for field in modelFieldNames {
            if let value = jsonStringValue(
                for: field,
                in: bytes,
                range: range
            ), let model = normalizedModelName(value) {
                return model
            }
        }

        for field in modelFieldNames {
            let fieldBytes = Array(field.utf8)
            var cursor = range.lowerBound
            while let position = find(fieldBytes, in: bytes, from: cursor),
                  position + fieldBytes.count <= range.upperBound {
                let after = position + fieldBytes.count
                let beforeByte = position > range.lowerBound ? bytes[position - 1] : nil
                let afterByte = after < range.upperBound ? bytes[after] : nil
                guard !isIdentifierByte(beforeByte), !isIdentifierByte(afterByte) else {
                    cursor = after
                    continue
                }

                let searchEnd = min(after + 512, range.upperBound)
                if let value = printableValue(
                    after: after,
                    in: bytes,
                    upperBound: searchEnd
                ), let model = normalizedModelName(value) {
                    return model
                }
                cursor = after
            }
        }
        return nil
    }

    private static func jsonStringValue(
        for field: String,
        in bytes: [UInt8],
        range: Range<Int>
    ) -> String? {
        let quotedField = Array("\"\(field)\"".utf8)
        var cursor = range.lowerBound
        while let position = find(quotedField, in: bytes, from: cursor),
              position + quotedField.count <= range.upperBound {
            var valueStart = position + quotedField.count
            while valueStart < range.upperBound, isJSONWhitespace(bytes[valueStart]) {
                valueStart += 1
            }
            guard valueStart < range.upperBound, bytes[valueStart] == 58 else {
                cursor = position + quotedField.count
                continue
            }

            valueStart += 1
            while valueStart < range.upperBound, isJSONWhitespace(bytes[valueStart]) {
                valueStart += 1
            }
            guard valueStart < range.upperBound, bytes[valueStart] == 34,
                  let valueEnd = endOfQuotedString(
                      in: bytes,
                      startingAt: valueStart,
                      upperBound: range.upperBound
                  ) else {
                cursor = position + quotedField.count
                continue
            }

            let valueData = Data(bytes[valueStart...valueEnd])
            if let value = LocalData.parseJSON(data: valueData) as? String {
                return value
            }
            cursor = valueEnd + 1
        }
        return nil
    }

    private static func endOfQuotedString(
        in bytes: [UInt8],
        startingAt start: Int,
        upperBound: Int
    ) -> Int? {
        guard start >= 0, start < upperBound, bytes[start] == 34 else { return nil }
        var escaped = false
        var index = start + 1
        while index < upperBound {
            let byte = bytes[index]
            if escaped {
                escaped = false
            } else if byte == 92 {
                escaped = true
            } else if byte == 34 {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func printableValue(
        after start: Int,
        in bytes: [UInt8],
        upperBound: Int
    ) -> String? {
        guard start >= 0, start < upperBound else { return nil }
        var index = start
        while index < upperBound {
            while index < upperBound, !isPrintable(bytes[index]) {
                index += 1
            }
            guard index < upperBound else { return nil }
            let valueStart = index
            while index < upperBound, isPrintable(bytes[index]) {
                index += 1
            }
            let value = String(bytes: bytes[valueStart..<index], encoding: .utf8)
                ?? String(bytes: bytes[valueStart..<index], encoding: .ascii)
            if let value {
                return value.trimmingCharacters(
                    in: CharacterSet(charactersIn: "\"'` \t\r\n,:{}[]")
                )
            }
        }
        return nil
    }

    private static func normalizedModelName(_ value: String?) -> String? {
        guard let value else { return nil }
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 2, candidate.count <= 160,
              !candidate.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            return nil
        }

        let lowercased = candidate.lowercased()
        let ignoredValues: Set<String> = [
            "unknown", "null", "nil", "none", "default", "model", "engine",
            "path", "params", "events", "completion", "chat", "samantha"
        ]
        guard !ignoredValues.contains(lowercased) else { return nil }

        // The raw fallback can see adjacent serialized strings. Require a
        // recognizable model family or a version-like identifier so prompts,
        // URLs, and telemetry labels are not shown as a model name.
        let knownFamily = [
            "doubao", "seed", "pro", "lite", "turbo", "thinking", "reason",
            "deepseek", "qwen", "kimi", "glm", "claude", "gpt", "gemini", "ark"
        ].contains { lowercased.contains($0) }
        let hasDigit = candidate.unicodeScalars.contains { $0.properties.numericType != nil }
        guard knownFamily || hasDigit else { return nil }
        return ModelUsage.normalizedName(candidate)
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13
    }

    private static func isPrintable(_ byte: UInt8) -> Bool {
        (32...126).contains(byte)
    }

    private static func isIdentifierByte(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return (48...57).contains(byte)
            || (65...90).contains(byte)
            || (97...122).contains(byte)
            || byte == 95
    }

    private static func mergedModelEvents(
        _ events: [DoubaoWorkModelEvent]
    ) -> [DoubaoWorkModelEvent] {
        var byID: [String: DoubaoWorkModelEvent] = [:]
        for event in events {
            if let existing = byID[event.id] {
                // A cache created before model parsing may contain the same
                // event without a model. Prefer the newly parsed value even
                // when its date is identical.
                if existing.model == nil, event.model != nil {
                    byID[event.id] = event
                    continue
                }
                if existing.model != nil, event.model == nil {
                    continue
                }
                if existing.date <= event.date {
                    continue
                }
            }
            byID[event.id] = event
        }
        return byID.values.sorted { $0.date < $1.date }
    }

    private static func positions(of needle: [UInt8], in bytes: [UInt8]) -> [Int] {
        guard !needle.isEmpty, bytes.count >= needle.count else { return [] }
        var result: [Int] = []
        var cursor = 0
        while let position = find(needle, in: bytes, from: cursor) {
            result.append(position)
            cursor = position + needle.count
        }
        return result
    }

    private static func stableIdentity(in bytes: [UInt8], range: Range<Int>) -> String {
        // A small deterministic digest keeps the cache independent of the
        // LevelDB file name and survives compaction when the serialized value
        // itself is unchanged.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes[range] {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func parseTasks(in file: DoubaoWorkFile) -> [DoubaoWorkTask] {
        guard let data = readData(at: file.url, from: 0) else { return [] }
        let bytes = Array(data)
        guard bytes.count >= taskMarker.count else { return [] }

        var tasks: [DoubaoWorkTask] = []
        var seen: Set<String> = []
        var cursor = 0
        while let markerIndex = find(taskMarker, in: bytes, from: cursor) {
            let searchStart = markerIndex + taskMarker.count
            guard let id = uuid(after: searchStart, in: bytes) else {
                cursor = searchStart
                continue
            }

            let windowStart = max(markerIndex - 8 * 1024, 0)
            let windowEnd = min(markerIndex + 8 * 1024, bytes.count)
            let window = windowStart..<windowEnd
            guard taskContextMarkers.allSatisfy({ contains($0, in: bytes, range: window) }),
                  seen.insert(id).inserted else {
                cursor = searchStart
                continue
            }

            let date = workDay(in: bytes, range: window)
                ?? Date(timeIntervalSince1970: file.modifiedAt)
            tasks.append(DoubaoWorkTask(id: id, date: date))
            cursor = searchStart
        }
        return tasks
    }

    private static func chatDay(in bytes: [UInt8]) -> Date? {
        var cursor = 0
        while let markerIndex = find(chatFolderMarker, in: bytes, from: cursor) {
            let dateStart = markerIndex + chatFolderMarker.count
            let dateEnd = min(dateStart + 10, bytes.count)
            if dateEnd - dateStart == 10,
               let date = workDay(in: bytes, range: dateStart..<dateEnd) {
                return date
            }
            cursor = dateStart
        }
        return nil
    }

    private static func chatDay(in bytes: [UInt8], around position: Int) -> Date? {
        let rangeStart = max(position - 8 * 1024, 0)
        let rangeEnd = min(position + 8 * 1024, bytes.count)
        guard rangeStart < rangeEnd else { return nil }
        let range = rangeStart..<rangeEnd
        var cursor = range.lowerBound
        while let markerIndex = find(chatFolderMarker, in: bytes, from: cursor),
              markerIndex < range.upperBound {
            let dateStart = markerIndex + chatFolderMarker.count
            let dateEnd = min(dateStart + 10, range.upperBound)
            if dateEnd - dateStart == 10,
               let date = workDay(in: bytes, range: dateStart..<dateEnd) {
                return date
            }
            cursor = dateStart
        }
        return workDay(in: bytes, range: range)
    }

    private static func mergedTasks(_ tasks: [DoubaoWorkTask]) -> [DoubaoWorkTask] {
        var byID: [String: DoubaoWorkTask] = [:]
        for task in tasks {
            if let existing = byID[task.id], existing.date <= task.date {
                continue
            }
            byID[task.id] = task
        }
        return byID.values.sorted { $0.date < $1.date }
    }

    private static func contains(
        _ needle: [UInt8],
        in bytes: [UInt8],
        range: Range<Int>
    ) -> Bool {
        guard !needle.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= bytes.count,
              range.count >= needle.count,
              let index = find(needle, in: bytes, from: range.lowerBound) else {
            return false
        }
        return index + needle.count <= range.upperBound
    }

    private static func uuid(after start: Int, in bytes: [UInt8]) -> String? {
        let length = 36
        guard start < bytes.count else { return nil }
        let lastStart = min(start + 256, bytes.count - length)
        guard start <= lastStart else { return nil }

        for index in start...lastStart {
            guard bytes[index + 8] == 45,
                  bytes[index + 13] == 45,
                  bytes[index + 18] == 45,
                  bytes[index + 23] == 45 else { continue }
            let hexPositions = [
                0..<8, 9..<13, 14..<18, 19..<23, 24..<36
            ]
            guard hexPositions.allSatisfy({ range in
                range.allSatisfy { isHex(bytes[index + $0]) }
            }),
            let value = String(bytes: bytes[index..<(index + length)], encoding: .utf8) else {
                continue
            }
            return value
        }
        return nil
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private static func workDay(in bytes: [UInt8], range: Range<Int>) -> Date? {
        guard range.count >= 10 else { return nil }
        let lastStart = range.upperBound - 10
        for index in range.lowerBound...lastStart {
            guard bytes[index + 4] == 45,
                  bytes[index + 7] == 45,
                  (0..<4).allSatisfy({ isDigit(bytes[index + $0]) }),
                  (5..<7).allSatisfy({ isDigit(bytes[index + $0]) }),
                  (8..<10).allSatisfy({ isDigit(bytes[index + $0]) }) else {
                continue
            }

            let year = integer(in: bytes, range: index..<(index + 4))
            let month = integer(in: bytes, range: (index + 5)..<(index + 7))
            let day = integer(in: bytes, range: (index + 8)..<(index + 10))
            guard let year, let month, let day,
                  (2000...2100).contains(year),
                  (1...12).contains(month),
                  (1...31).contains(day) else { continue }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            if let date = Calendar.autoupdatingCurrent.date(from: components) {
                return date
            }
        }
        return nil
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
    }

    private static func integer(in bytes: [UInt8], range: Range<Int>) -> Int? {
        guard range.lowerBound >= 0, range.upperBound <= bytes.count else { return nil }
        return Int(String(bytes: bytes[range], encoding: .ascii) ?? "")
    }

    private static func parseFile(at url: URL, from offset: Int64) -> [DoubaoWorkRequest] {
        guard let data = readData(at: url, from: offset),
              data.range(of: eventMarker) != nil else {
            return []
        }
        return embeddedJSONObjects(in: data).flatMap(extractRequests)
    }

    private static func readData(at url: URL, from offset: Int64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            if offset > 0 {
                try handle.seek(toOffset: UInt64(offset))
            }
            return try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    private static func extractRequests(in object: [String: Any]) -> [DoubaoWorkRequest] {
        guard let events = object["events"] as? [Any] else { return [] }
        return events.compactMap { event in
            guard let event = event as? [String: Any],
                  LocalData.string(event["event"]) == "net_report_dev" else {
                return nil
            }

            let params: [String: Any]?
            if let dictionary = event["params"] as? [String: Any] {
                params = dictionary
            } else {
                params = LocalData.embeddedJSON(event["params"]) as? [String: Any]
            }
            guard let params,
                  let path = LocalData.string(params["path"]),
                  completionPaths.contains(path) else {
                return nil
            }

            let requestStartDate = LocalData.date(params["req_start_ms"])
            let requestEndDate = LocalData.date(params["req_end_ms"])
            guard let date = requestStartDate
                    ?? LocalData.date(event["local_time_ms"] ?? params["req_end_ms"]) else {
                return nil
            }
            let statusCode = LocalData.number(params["status_code"]).map { Int($0.rounded()) }
            return DoubaoWorkRequest(
                date: date,
                requestStartDate: requestStartDate,
                requestEndDate: requestEndDate,
                path: path,
                statusCode: statusCode,
                requestSize: LocalData.number(params["req_size"]),
                responseSize: LocalData.number(params["rsp_size"]),
                durationMilliseconds: LocalData.number(params["req2rsp_dur_ms"]),
                model: modelName(from: event)
                    ?? modelName(from: params)
                    ?? modelName(from: LocalData.embeddedJSON(event["data"]))
            )
        }
    }

    private static func isSuccessful(_ statusCode: Int?) -> Bool {
        guard let statusCode else { return true }
        return (200..<400).contains(statusCode)
    }

    private static func mergeRequests(
        _ existing: [DoubaoWorkRequest],
        _ incoming: [DoubaoWorkRequest]
    ) -> [DoubaoWorkRequest] {
        deduplicated(existing + incoming)
    }

    private static func deduplicated(_ requests: [DoubaoWorkRequest]) -> [DoubaoWorkRequest] {
        var seen: Set<String> = []
        return requests.filter { seen.insert(deduplicationKey(for: $0)).inserted }
    }

    private static func deduplicationKey(for request: DoubaoWorkRequest) -> String {
        func milliseconds(_ date: Date?) -> String {
            guard let date else { return "-1" }
            return String(Int((date.timeIntervalSince1970 * 1_000).rounded()))
        }

        // Tea and sdk_storage/log can both record the same network request.
        // The request start timestamp is the stable identity; response size,
        // duration, and the local completion timestamp can differ between the
        // two mirrors and must not turn one completion into two.
        return [
            request.path,
            milliseconds(request.requestStartDate ?? request.date),
        ].joined(separator: "|")
    }

    private static func embeddedJSONObjects(in data: Data) -> [[String: Any]] {
        let bytes = Array(data)
        let marker = Array(eventMarker)
        guard !bytes.isEmpty, bytes.count >= marker.count else { return [] }

        var objects: [[String: Any]] = []
        var cursor = 0
        while cursor <= bytes.count - marker.count {
            guard let start = find(marker, in: bytes, from: cursor) else { break }
            guard let end = endOfJSONObject(in: bytes, startingAt: start) else {
                cursor = start + marker.count
                continue
            }
            let objectData = Data(bytes[start...end])
            if let object = LocalData.parseJSON(data: objectData) as? [String: Any] {
                objects.append(object)
            }
            cursor = end + 1
        }
        return objects
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, start >= 0, bytes.count >= needle.count else { return nil }
        let lastStart = bytes.count - needle.count
        guard start <= lastStart else { return nil }
        for index in start...lastStart {
            if bytes[index..<(index + needle.count)].elementsEqual(needle) {
                return index
            }
        }
        return nil
    }

    private static func endOfJSONObject(in bytes: [UInt8], startingAt start: Int) -> Int? {
        var depth = 0
        var insideString = false
        var escaped = false

        for index in start..<bytes.count {
            let byte = bytes[index]
            if insideString {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == 34 {
                    insideString = false
                }
                continue
            }

            if byte == 34 {
                insideString = true
            } else if byte == 123 {
                depth += 1
            } else if byte == 125 {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func loadCache() -> DoubaoWorkScanCache? {
        guard let data = try? Data(contentsOf: AppPaths.doubaoWorkScanCache),
              let cache = try? JSONDecoder().decode(DoubaoWorkScanCache.self, from: data),
              cache.version == cacheVersion else {
            return nil
        }
        return cache
    }

    private static func saveCache(_ cache: DoubaoWorkScanCache) {
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: AppPaths.doubaoWorkScanCache, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: AppPaths.doubaoWorkScanCache.path
            )
        } catch {
            // Usage collection should continue if the optional cache cannot
            // be written in a restricted environment.
        }
    }
}
