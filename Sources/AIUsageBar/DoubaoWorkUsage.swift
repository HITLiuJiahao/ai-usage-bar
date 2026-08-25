import Foundation

struct DoubaoWorkScanResult {
    let summary: LocalUsageSummary
    let responseCount: Int
    let hasLogFiles: Bool
}

private struct DoubaoWorkRequest {
    let date: Date
    let path: String
    let statusCode: Int?
    let requestSize: Double?
    let responseSize: Double?
    let durationMilliseconds: Double?
}

enum DoubaoWorkUsageScanner {
    private static let completionPaths: Set<String> = [
        "/chat/completion",
        "/samantha/chat/completion"
    ]

    static func scan() -> DoubaoWorkScanResult {
        let files = logFiles()
        var requests: [DoubaoWorkRequest] = []
        for file in files {
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { continue }
            for object in embeddedJSONObjects(in: data) {
                requests.append(contentsOf: extractRequests(in: object))
            }
        }

        var summary = LocalUsageSummary()
        var seen: Set<String> = []
        var responseCount = 0
        for request in requests.sorted(by: { $0.date < $1.date }) {
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

    private static func logFiles() -> [URL] {
        let roots = [AppPaths.doubaoWorkTeaDatabase, AppPaths.doubaoWorkSDKLogs]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: keys).isRegularFile) == true else { continue }
                let modifiedAt = (try? url.resourceValues(forKeys: keys).contentModificationDate)
                    ?? Date.distantPast
                candidates.append((url: url, modifiedAt: modifiedAt))
            }
        }

        return candidates
            .sorted { $0.modifiedAt < $1.modifiedAt }
            .map(\.url)
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
        let marker = Array("{\"events\":".utf8)
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
}
