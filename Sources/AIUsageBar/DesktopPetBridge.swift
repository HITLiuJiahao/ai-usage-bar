import Darwin
import Foundation

/// Local-only newline-delimited JSON relay for agent hooks. The socket lives
/// inside this user's Application Support directory and is created with owner
/// read/write permissions; no network port is opened.
final class PetEventSocketServer {
    static let socketURL = DesktopPetStorage.storageDirectory.appendingPathComponent("events.sock")

    private weak var store: DesktopPetStore?
    private let queue = DispatchQueue(label: "com.local.aiusagebar.desktop-pet-events", qos: .utility)
    private var listeningFD: Int32 = -1
    private var isStopped = false

    init(store: DesktopPetStore) {
        self.store = store
    }

    func start() {
        guard listeningFD < 0 else { return }
        do {
            try FileManager.default.createDirectory(
                at: DesktopPetStorage.storageDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        let path = Self.socketURL.path
        guard path.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else { return }
        path.withCString { _ = Darwin.unlink($0) }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 12) == 0 else {
            Darwin.close(fd)
            path.withCString { _ = Darwin.unlink($0) }
            return
        }
        path.withCString { _ = Darwin.chmod($0, mode_t(0o600)) }
        listeningFD = fd
        isStopped = false

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        guard listeningFD >= 0 else { return }
        isStopped = true
        Darwin.close(listeningFD)
        listeningFD = -1
        Self.socketURL.path.withCString { _ = Darwin.unlink($0) }
    }

    deinit {
        stop()
    }

    private func acceptLoop() {
        while !isStopped {
            var clientAddress = sockaddr()
            var addressLength = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = Darwin.accept(listeningFD, &clientAddress, &addressLength)
            guard clientFD >= 0 else {
                if isStopped { break }
                continue
            }
            handle(clientFD: clientFD)
            Darwin.close(clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = Darwin.recv(clientFD, &bytes, bytes.count, 0)
        guard count > 0 else { return }
        let payload = Data(bytes.prefix(Int(count)))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in payload.split(separator: 10) {
            guard let event = try? decoder.decode(PetHookEvent.self, from: Data(line)) else { continue }
            Task { @MainActor [weak store] in
                store?.consume(event)
            }
        }
        _ = "ok\n".withCString { reply in
            Darwin.send(clientFD, reply, strlen(reply), 0)
        }
    }
}

enum PetEventCommand {
    /// Returns true when the executable was invoked as the event client. This
    /// lets any hook call `AIUsageBar pet-event …` without launching a second
    /// menubar app instance.
    static func runIfNeeded(arguments: [String] = CommandLine.arguments) -> Bool {
        guard arguments.dropFirst().first == "pet-event" else { return false }
        let values = parse(Array(arguments.dropFirst(2)))
        guard let provider = values["provider"],
              let state = values["state"]
        else {
            FileHandle.standardError.write(Data("Usage: AIUsageBar pet-event --provider <id> --state <working|waiting|blocked|done> [--project <path>] [--message <text>] [--model <name>] [--tokens <n>] [--requests <n>] [--session <id>]\n".utf8))
            return true
        }
        let event = PetHookEvent(
            provider: provider,
            state: state,
            projectPath: values["project"],
            sessionID: values["session"],
            message: values["message"],
            model: values["model"],
            tokens: values["tokens"].flatMap(Double.init),
            requests: values["requests"].flatMap(Double.init),
            timestamp: Date()
        )
        if !send(event) {
            FileHandle.standardError.write(Data("AI Usage Bar desktop-pet relay is not running.\n".utf8))
        }
        return true
    }

    static func exampleCommand() -> String {
        let executable = Bundle.main.executablePath ?? "AIUsageBar"
        return "\"\(executable)\" pet-event --provider codex --state working --project \"$PWD\" --message \"Working\""
    }

    private static func parse(_ arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                index += 1
                continue
            }
            let key = String(argument.dropFirst(2))
            let next = index + 1
            if next < arguments.count, !arguments[next].hasPrefix("--") {
                result[key] = arguments[next]
                index += 2
            } else {
                result[key] = "true"
                index += 1
            }
        }
        return result
    }

    private static func send(_ event: PetHookEvent) -> Bool {
        let path = PetEventSocketServer.socketURL.path
        guard path.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else { return false }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var payload = try? encoder.encode(event) else { return false }
        payload.append(10)
        return payload.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            return Darwin.send(fd, baseAddress, bytes.count, 0) == bytes.count
        }
    }
}
