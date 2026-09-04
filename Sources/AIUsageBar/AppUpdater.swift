import AppKit
import Combine
import CryptoKit
import Foundation

struct AppUpdateRelease: Equatable {
    let tag: String
    let downloadURL: URL
    let sha256: String
    let assetName: String
    let releaseURL: URL
}

enum AppUpdateFailure: Error, Equatable {
    case noRelease
    case network
    case invalidMetadata
    case untrustedURL
    case missingChecksum
    case checksumMismatch
    case invalidPackage
    case appLocationUnavailable
    case installation
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppUpdateRelease)
    case downloading(Double)
    case installing
    case failed(AppUpdateFailure)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }
}

/// Checks the public GitHub Releases feed and installs a verified Apple
/// Silicon application bundle in the same spirit as Tokei's updater.
///
/// The updater deliberately has no account or token requirements. Release
/// metadata is public, and the downloaded archive must pass both the GitHub
/// asset SHA-256 check and a local bundle/signature check before installation.
final class AppUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AppUpdater()

    static let repositoryOwner = "HITLiuJiahao"
    static let repositoryName = "ai-usage-bar"
    static let automaticCheckInterval: TimeInterval = 6 * 60 * 60

    private static let lastCheckDefaultsKey = "aiUsageBar.lastUpdateCheck"
    private static let currentVersionFallback = "0.2.0"

    @Published private(set) var state: AppUpdateState = .idle

    private let fileManager = FileManager.default
    private let metadataURL = URL(
        string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest"
    )!
    private var session: URLSession!
    private var automaticCheckTimer: Timer?
    private var metadataTask: URLSessionDataTask?
    private var downloadTask: URLSessionDownloadTask?
    private var expectedSHA256: String?
    private var activeRelease: AppUpdateRelease?
    private var isManualCheck = false

    static var currentVersion: String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return currentVersionFallback
        }
        return value
    }

    private override init() {
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 5 * 60
        session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
    }

    deinit {
        automaticCheckTimer?.invalidate()
        metadataTask?.cancel()
        downloadTask?.cancel()
        session.invalidateAndCancel()
    }

    func startAutomaticChecks() {
        guard automaticCheckTimer == nil else { return }

        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.automaticCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForUpdate(manual: false)
        }
        timer.tolerance = 5 * 60
        automaticCheckTimer = timer

        guard shouldCheckAutomatically else { return }
        // Let the menu-bar app finish its first local scan before making the
        // optional network request. A failed update check must never delay UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdate(manual: false)
        }
    }

    func checkForUpdate(manual: Bool = true) {
        guard !state.isBusy else { return }
        // A visible update should stay available until the user installs it,
        // rather than being replaced by a later background check.
        if case .available = state { return }

        metadataTask?.cancel()
        metadataTask = nil
        isManualCheck = manual
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckDefaultsKey)
        state = .checking

        var request = URLRequest(
            url: metadataURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AIUsageBar/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        metadataTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.handleMetadataResponse(data: data, response: response, error: error)
        }
        metadataTask?.resume()
    }

    func installUpdate() {
        guard case .available(let release) = state else { return }
        guard Self.isAllowedDownloadSourceURL(release.downloadURL) else {
            state = .failed(.untrustedURL)
            return
        }
        guard let appURL = installedAppURL,
              appURL.pathExtension.lowercased() == "app",
              fileManager.fileExists(atPath: appURL.path) else {
            state = .failed(.appLocationUnavailable)
            return
        }
        guard fileManager.isWritableFile(
            atPath: appURL.deletingLastPathComponent().path
        ) else {
            state = .failed(.appLocationUnavailable)
            return
        }

        activeRelease = release
        expectedSHA256 = release.sha256
        state = .downloading(0)
        downloadTask?.cancel()
        downloadTask = session.downloadTask(with: release.downloadURL)
        downloadTask?.resume()
    }

    private var installedAppURL: URL? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension.lowercased() == "app" else { return nil }
        return bundleURL
    }

    private var shouldCheckAutomatically: Bool {
        guard let lastCheck = UserDefaults.standard.object(
            forKey: Self.lastCheckDefaultsKey
        ) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= Self.automaticCheckInterval
    }

    private func handleMetadataResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) {
        metadataTask = nil

        if let error, (error as NSError).code == NSURLErrorCancelled {
            return
        }

        guard error == nil,
              let httpResponse = response as? HTTPURLResponse,
              Self.isAllowedMetadataURL(httpResponse.url),
              let responseData = data else {
            finishCheck(.failure(.network))
            return
        }

        if httpResponse.statusCode == 404 {
            finishCheck(.failure(.noRelease))
            return
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            finishCheck(.failure(.network))
            return
        }

        guard let json = try? JSONSerialization.jsonObject(
            with: responseData,
            options: []
        ) as? [String: Any],
        let tag = Self.releaseTag(from: json) else {
            finishCheck(.failure(.invalidMetadata))
            return
        }

        guard Self.isNewerVersion(tag, than: Self.currentVersion) else {
            finishCheck(.success(nil))
            return
        }

        guard let release = Self.validatedRelease(from: json, tag: tag) else {
            finishCheck(.failure(.invalidMetadata))
            return
        }
        finishCheck(.success(release))
    }

    private func finishCheck(_ result: Result<AppUpdateRelease?, AppUpdateFailure>) {
        switch result {
        case .success(let release):
            if let release {
                state = .available(release)
            } else {
                setTransientState(.upToDate, delay: isManualCheck ? 4 : 2)
            }
        case .failure(let failure):
            if isManualCheck {
                setTransientState(.failed(failure), delay: 6)
            } else {
                state = .idle
            }
        }
    }

    private func setTransientState(_ nextState: AppUpdateState, delay: TimeInterval) {
        state = nextState
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.state == nextState else { return }
            self.state = .idle
        }
    }

    // MARK: - Download validation

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard downloadTask.taskIdentifier == self.downloadTask?.taskIdentifier else {
            return
        }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        state = .downloading(min(max(progress, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard downloadTask.taskIdentifier == self.downloadTask?.taskIdentifier else {
            return
        }
        guard let finalURL = downloadTask.response?.url,
              Self.isAllowedDownloadResponseURL(finalURL) else {
            failDownload(.untrustedURL)
            return
        }
        guard let expectedSHA256,
              let activeRelease else {
            failDownload(.missingChecksum)
            return
        }

        let workspace: UpdateWorkspace
        do {
            workspace = try UpdateWorkspace.create(using: fileManager)
        } catch {
            failDownload(.installation)
            return
        }

        do {
            let archiveURL = workspace.archiveURL
            try fileManager.moveItem(at: location, to: archiveURL)
            guard try Self.sha256(of: archiveURL) == expectedSHA256 else {
                throw AppUpdateValidationError.checksumMismatch
            }
            try Self.extractArchive(archiveURL, to: workspace.extractionURL)
            guard let candidateURL = Self.findCandidateApp(in: workspace.extractionURL),
                  Self.validateCandidate(
                    candidateURL,
                    expectedVersion: activeRelease.tag,
                    currentVersion: Self.currentVersion
                  ) else {
                throw AppUpdateValidationError.invalidPackage
            }

            self.expectedSHA256 = nil
            self.activeRelease = nil
            self.downloadTask = nil
            install(
                workspace: workspace,
                candidateURL: candidateURL,
                appURL: installedAppURL!
            )
        } catch let error as AppUpdateValidationError {
            try? fileManager.removeItem(at: workspace.rootURL)
            failDownload(error.failure)
        } catch {
            try? fileManager.removeItem(at: workspace.rootURL)
            failDownload(.invalidPackage)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectURL = request.url else {
            completionHandler(nil)
            return
        }

        let isDownload = task.taskIdentifier == downloadTask?.taskIdentifier
        let allowed = isDownload
            ? Self.isAllowedDownloadResponseURL(redirectURL)
            : Self.isAllowedMetadataURL(redirectURL)
        if !allowed, isDownload {
            failDownload(.untrustedURL)
        }
        completionHandler(allowed ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task.taskIdentifier == downloadTask?.taskIdentifier,
              let error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        failDownload(.network)
    }

    private func failDownload(_ failure: AppUpdateFailure) {
        expectedSHA256 = nil
        activeRelease = nil
        downloadTask = nil
        setTransientState(.failed(failure), delay: 6)
    }

    // MARK: - Install

    private func install(
        workspace: UpdateWorkspace,
        candidateURL: URL,
        appURL: URL
    ) {
        state = .installing
        let backupURL = appURL.deletingLastPathComponent().appendingPathComponent(
            "\(appURL.lastPathComponent).aiusagebar-backup-\(workspace.identifier)"
        )

        do {
            try Self.installerScript.write(
                to: workspace.scriptURL,
                atomically: true,
                encoding: .utf8
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: workspace.scriptURL.path
            )
        } catch {
            try? fileManager.removeItem(at: workspace.rootURL)
            setTransientState(.failed(.installation), delay: 6)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            workspace.scriptURL.path,
            candidateURL.path,
            appURL.path,
            workspace.rootURL.path,
            backupURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? fileManager.removeItem(at: workspace.rootURL)
            setTransientState(.failed(.installation), delay: 6)
            return
        }

        // The helper owns the replacement and reopens the app after this
        // process exits, so the current bundle is never copied over itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.terminate(nil)
        }
    }

    private static let installerScript = """
    #!/bin/bash
    set -u

    if [ "$#" -ne 4 ]; then
        exit 2
    fi

    CANDIDATE_PATH="$1"
    APP_PATH="$2"
    WORK_DIR="$3"
    BACKUP_PATH="$4"
    OLD_MOVED=0

    cleanup() {
        /bin/rm -rf "$WORK_DIR"
    }

    restore() {
        if [ "$OLD_MOVED" -eq 1 ]; then
            /bin/rm -rf "$APP_PATH"
            /bin/mv "$BACKUP_PATH" "$APP_PATH" >/dev/null 2>&1 || true
            OLD_MOVED=0
        fi
    }

    validate_app() {
        local candidate="$1"
        local plist="$candidate/Contents/Info.plist"
        [ -f "$plist" ] || return 1
        /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null \
            | /usr/bin/grep -Fxq 'com.local.aiusagebar' || return 1
        /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null \
            | /usr/bin/grep -Fxq 'AIUsageBar' || return 1
        [ -x "$candidate/Contents/MacOS/AIUsageBar" ] || return 1
        /usr/bin/codesign --verify --deep --strict "$candidate" >/dev/null 2>&1 || return 1
    }

    fail() {
        restore
        cleanup
        /usr/bin/open -n "$APP_PATH" >/dev/null 2>&1 || true
        exit 1
    }

    trap fail HUP INT TERM
    /bin/sleep 1
    [ -d "$CANDIDATE_PATH" ] || fail
    [ -d "$APP_PATH" ] || fail
    validate_app "$CANDIDATE_PATH" || fail
    [ ! -e "$BACKUP_PATH" ] || /bin/rm -rf "$BACKUP_PATH" || fail
    /bin/mv "$APP_PATH" "$BACKUP_PATH" || fail
    OLD_MOVED=1
    /bin/cp -R "$CANDIDATE_PATH" "$APP_PATH" || fail
    /usr/bin/xattr -cr "$APP_PATH" >/dev/null 2>&1 || true
    validate_app "$APP_PATH" || fail
    /usr/bin/open -n "$APP_PATH" >/dev/null 2>&1 || fail
    /bin/rm -rf "$BACKUP_PATH" || fail
    OLD_MOVED=0
    cleanup
    exit 0
    """
}

private enum AppUpdateValidationError: Error {
    case checksumMismatch
    case invalidPackage

    var failure: AppUpdateFailure {
        switch self {
        case .checksumMismatch:
            return .checksumMismatch
        case .invalidPackage:
            return .invalidPackage
        }
    }
}

private struct UpdateWorkspace {
    let identifier: String
    let rootURL: URL
    let archiveURL: URL
    let extractionURL: URL
    let scriptURL: URL

    static func create(using fileManager: FileManager) throws -> UpdateWorkspace {
        let identifier = UUID().uuidString.lowercased()
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "aiusagebar-update-\(identifier)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return UpdateWorkspace(
            identifier: identifier,
            rootURL: rootURL,
            archiveURL: rootURL.appendingPathComponent("AIUsageBar.zip"),
            extractionURL: rootURL.appendingPathComponent("payload", isDirectory: true),
            scriptURL: rootURL.appendingPathComponent("install.sh")
        )
    }
}

private extension AppUpdater {
    static let metadataHosts: Set<String> = ["api.github.com"]
    static let downloadSourceHosts: Set<String> = ["github.com"]
    static let downloadRedirectHosts: Set<String> = [
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com",
        "github-releases.githubusercontent.com"
    ]

    static func releaseTag(from json: [String: Any]) -> String? {
        guard let raw = json["tag_name"] as? String else { return nil }
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    static func validatedRelease(
        from json: [String: Any],
        tag: String
    ) -> AppUpdateRelease? {
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }

        let candidates = assets.compactMap { asset -> AppUpdateRelease? in
            guard let name = asset["name"] as? String,
                  name.lowercased().hasSuffix(".zip"),
                  !name.lowercased().contains("source"),
                  let rawURL = asset["browser_download_url"] as? String,
                  let url = URL(string: rawURL),
                  isAllowedDownloadSourceURL(url),
                  let digest = normalizedSHA256(asset["digest"] as? String) else {
                return nil
            }
            let releaseURL = (json["html_url"] as? String).flatMap(URL.init)
                ?? URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases")!
            return AppUpdateRelease(
                tag: tag,
                downloadURL: url,
                sha256: digest,
                assetName: name,
                releaseURL: releaseURL
            )
        }

        #if arch(arm64)
        let architectureMarkers = ["arm64", "aarch64", "universal"]
        #else
        let architectureMarkers = ["x86_64", "amd64", "universal"]
        #endif

        for marker in architectureMarkers {
            if let candidate = candidates.first(where: {
                $0.assetName.lowercased().contains(marker)
            }) {
                return candidate
            }
        }

        // A single generic ZIP is acceptable when the release has no
        // architecture suffix; the bundle validation below remains required.
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func isNewerVersion(_ remote: String, than local: String) -> Bool {
        guard let remoteParts = versionParts(remote),
              let localParts = versionParts(local) else {
            return false
        }
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    static func sameVersion(_ left: String, _ right: String) -> Bool {
        versionParts(left) == versionParts(right)
    }

    static func versionParts(_ raw: String) -> [Int]? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") { value.removeFirst() }
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }
        let numbers = components.compactMap { Int($0) }
        return numbers.count == components.count ? numbers : nil
    }

    static func normalizedSHA256(_ raw: String?) -> String? {
        guard var digest = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        if digest.hasPrefix("sha256:") {
            digest.removeFirst("sha256:".count)
        }
        guard digest.utf8.count == 64,
              digest.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            return nil
        }
        return digest
    }

    static func isAllowedMetadataURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return isAllowedHTTPSURL(url, hosts: metadataHosts)
    }

    static func isAllowedDownloadSourceURL(_ url: URL) -> Bool {
        isAllowedHTTPSURL(url, hosts: downloadSourceHosts)
    }

    static func isAllowedDownloadResponseURL(_ url: URL) -> Bool {
        isAllowedHTTPSURL(
            url,
            hosts: downloadSourceHosts.union(downloadRedirectHosts)
        )
    }

    static func isAllowedHTTPSURL(_ url: URL, hosts: Set<String>) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              hosts.contains(host),
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.port == nil || components.port == 443 else {
            return false
        }
        return true
    }

    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func extractArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard runProcess(
            "/usr/bin/ditto",
            ["-x", "-k", archiveURL.path, destinationURL.path]
        ) else {
            throw AppUpdateValidationError.invalidPackage
        }
    }

    static func findCandidateApp(in extractionURL: URL) -> URL? {
        let fileManager = FileManager.default
        let directURL = extractionURL.appendingPathComponent(
            "AIUsageBar.app",
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        guard let values = try? directURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
              values.isSymbolicLink != true else {
            return nil
        }
        return directURL
    }

    static func validateCandidate(
        _ appURL: URL,
        expectedVersion: String,
        currentVersion: String
    ) -> Bool {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
              ) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == "com.local.aiusagebar",
              plist["CFBundleExecutable"] as? String == "AIUsageBar",
              let candidateVersion = plist["CFBundleShortVersionString"] as? String,
              isNewerVersion(candidateVersion, than: currentVersion),
              sameVersion(candidateVersion, expectedVersion) else {
            return false
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/AIUsageBar")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return false
        }
        return runProcess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", appURL.path]
        )
    }

    static func runProcess(_ executablePath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
