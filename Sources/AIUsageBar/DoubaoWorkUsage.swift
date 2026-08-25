import Foundation

struct DoubaoWorkScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let hasLogFiles: Bool
}

private struct DoubaoWorkRequest: Codable {
    let date: Date
    let path: String
    let statusCode: Int?
    let requestSize: Double?
    let responseSize: Double?
    let durationMilliseconds: Double?
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

private struct DoubaoWorkScanCache: Codable {
    let version: Int
    let files: [String: DoubaoWorkFileEntry]
}

enum DoubaoWorkUsageScanner {
    private static let cacheVersion = 1
    private static let cacheOverlapBytes: Int64 = 2 * 1024 * 1024
    private static let completionPaths: Set<String> = [
        "/chat/completion",
        "/samantha/chat/completion"
    ]
    private static let eventMarker = Data("{\"events\":".utf8)

    static func scan() -> DoubaoWorkScanResult {
        let files = logFiles()
        let previous = loadCache()
        var current: [String: DoubaoWorkFileEntry] = [:]
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

            current[key] = DoubaoWorkFileEntry(
                size: file.size,
                modifiedAt: file.modifiedAt,
                requests: requests
            )
            cacheDirty = true
        }

        if let previous, Set(previous.files.keys) != Set(current.keys) {
            cacheDirty = true
        }
        if cacheDirty {
            saveCache(DoubaoWorkScanCache(version: cacheVersion, files: current))
        }

        var summary = LocalUsageSummary()
        var seen: Set<String> = []
        var responseCount = 0
        for request in current.values
            .flatMap(\.requests)
            .sorted(by: { $0.date < $1.date }) {
            guard isSuccessful(request.statusCode) else { continue }
            let key = deduplicationKey(for: request)
            guard seen.insert(key).inserted else { continue }
            summary.add(date: request.date, tokens: nil, requests: 1)
            responseCount += 1
        }

        return DoubaoWorkScanResult(
            summary: summary,
            responseCount: responseCount,
            hasLogFiles: !files.isEmpty
        )
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
                  completionPaths.contains(path),
                  let date = LocalData.date(event["local_time_ms"] ?? params["req_end_ms"]) else {
                return nil
            }

            let statusCode = LocalData.number(params["status_code"]).map { Int($0.rounded()) }
            return DoubaoWorkRequest(
                date: date,
                path: path,
                statusCode: statusCode,
                requestSize: LocalData.number(params["req_size"]),
                responseSize: LocalData.number(params["rsp_size"]),
                durationMilliseconds: LocalData.number(params["req2rsp_dur_ms"])
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
        var seen: Set<String> = []
        return (existing + incoming).filter { seen.insert(deduplicationKey(for: $0)).inserted }
    }

    private static func deduplicationKey(for request: DoubaoWorkRequest) -> String {
        let timestamp = Int((request.date.timeIntervalSince1970 * 1_000).rounded())
        return [
            String(timestamp),
            request.path,
            String(request.statusCode ?? -1),
            String(request.requestSize ?? -1),
            String(request.responseSize ?? -1),
            String(request.durationMilliseconds ?? -1)
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
