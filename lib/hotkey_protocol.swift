import Foundation
import Darwin

struct HotkeyProcessIdentity: Codable, Equatable {
    let pid: Int32
    let startTime: TimeInterval
    let executable: String

    static func current() -> HotkeyProcessIdentity? {
        identity(for: ProcessInfo.processInfo.processIdentifier)
    }

    static func identity(for pid: Int32) -> HotkeyProcessIdentity? {
        var processInfo = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &processInfo, infoSize) == infoSize else {
            return nil
        }

        var executableBuffer = [CChar](repeating: 0, count: 4_096)
        let pathLength = proc_pidpath(pid, &executableBuffer, UInt32(executableBuffer.count))
        guard pathLength > 0 else { return nil }

        let startTime = TimeInterval(processInfo.pbi_start_tvsec)
            + TimeInterval(processInfo.pbi_start_tvusec) / 1_000_000
        return HotkeyProcessIdentity(pid: pid, startTime: startTime,
                                     executable: String(cString: executableBuffer))
    }
}

enum HotkeyMessageKind: String, Codable {
    case overlay
    case heartbeatRequest
    case heartbeatReply
    case barRestarting
    case requestAccess
}

struct HotkeyMessage: Codable {
    static let currentVersion = 1

    let version: Int
    let kind: HotkeyMessageKind
    let messageID: String
    let timestamp: TimeInterval
    let senderPID: Int32
    var overlayVisible: Bool?
    var overlayImmediate: Bool?
    var processIdentity: HotkeyProcessIdentity?
    var sessionID: String?

    init(kind: HotkeyMessageKind,
         messageID: String = UUID().uuidString,
         timestamp: TimeInterval = Date().timeIntervalSince1970,
         senderPID: Int32 = ProcessInfo.processInfo.processIdentifier,
         overlayVisible: Bool? = nil,
         overlayImmediate: Bool? = nil,
         processIdentity: HotkeyProcessIdentity? = nil,
         sessionID: String? = nil) {
        self.version = Self.currentVersion
        self.kind = kind
        self.messageID = messageID
        self.timestamp = timestamp
        self.senderPID = senderPID
        self.overlayVisible = overlayVisible
        self.overlayImmediate = overlayImmediate
        self.processIdentity = processIdentity
        self.sessionID = sessionID
    }

    var isCurrentVersion: Bool {
        version == Self.currentVersion
    }

    func isFresh(at now: TimeInterval = Date().timeIntervalSince1970,
                 maximumAge: TimeInterval) -> Bool {
        let age = now - timestamp
        return age >= 0 && age <= maximumAge
    }
}

enum HotkeyPaths {
    static var configDirectory: String {
        ProcessInfo.processInfo.environment["HUB_CONFIG_DIR"]
            ?? NSHomeDirectory() + "/.config/hub"
    }

    static var runtimeDirectory: String {
        if let directory = ProcessInfo.processInfo.environment["HUB_RUNTIME_DIR"] {
            return directory
        }
        let temporaryDirectory = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        let user = ProcessInfo.processInfo.environment["USER"] ?? "user"
        return temporaryDirectory + "/hub-" + user
    }

    static var barSocket: String { runtimeDirectory + "/hub-bar.sock" }
    static var hotkeysSocket: String { runtimeDirectory + "/hub-hotkeyd.sock" }
    static var statusFile: String { runtimeDirectory + "/hub-hotkeyd-status.json" }
    static var restartBudgetFile: String { runtimeDirectory + "/hub-hotkeyd-restarts.json" }
    static var lifecycleLockDirectory: String {
        ProcessInfo.processInfo.environment["HUB_LIFECYCLE_LOCK_DIR"]
            ?? runtimeDirectory + "/hub-lifecycle.lock"
    }
    static var sessionFile: String {
        ProcessInfo.processInfo.environment["HUB_SESSION_FILE"] ?? configDirectory + "/hub-session"
    }
    static var barPIDFile: String { configDirectory + "/hub_bar.pid" }
    static var barIdentityFile: String { configDirectory + "/hub_bar.identity" }
    static var logFile: String { configDirectory + "/hub.log" }
}

enum HotkeyDatagram {
    static let maximumMessageSize = 8192

    static func encode(_ message: HotkeyMessage) -> Data? {
        try? JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) -> HotkeyMessage? {
        guard let message = try? JSONDecoder().decode(HotkeyMessage.self, from: data),
              message.isCurrentVersion else {
            return nil
        }
        return message
    }

    @discardableResult
    static func send(_ message: HotkeyMessage, to path: String) -> Bool {
        guard let payload = encode(message),
              payload.count <= maximumMessageSize else {
            return false
        }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        guard setNonblocking(descriptor) else { return false }

        guard let sent = withSocketAddress(path, { address, length in
            payload.withUnsafeBytes { bytes in
                sendto(descriptor, bytes.baseAddress, payload.count, 0, address, length)
            }
        }) else {
            return false
        }
        return sent == payload.count
    }

    static func listen(at path: String,
                       queue: DispatchQueue,
                       handler: @escaping (HotkeyMessage) -> Void) throws -> HotkeyDatagramListener {
        try HotkeyDatagramListener(path: path, queue: queue, handler: handler)
    }

    fileprivate static func endpointIsActive(_ path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let result = withSocketAddress(path) { address, length in
            connect(descriptor, address, length)
        }
        return result == 0
    }

    fileprivate static func setNonblocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    fileprivate static func withSocketAddress<T>(
        _ path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
    ) -> T? {
        var address = sockaddr_un()
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count + 1 <= pathCapacity else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let copied = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                path.withCString { source in
                    strlcpy(destination, source, pathCapacity)
                }
            }
        }
        guard copied < pathCapacity else { return nil }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

private final class HotkeyDatagramResources {
    private let descriptor: Int32
    private let path: String
    private let lock = NSLock()
    private var isClosed = false

    init(descriptor: Int32, path: String) {
        self.descriptor = descriptor
        self.path = path
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        _ = Darwin.close(descriptor)
        _ = Darwin.unlink(path)
    }
}

final class HotkeyDatagramListener {
    private let descriptor: Int32
    private let resources: HotkeyDatagramResources
    private let path: String
    private let queue: DispatchQueue
    private let handler: (HotkeyMessage) -> Void
    private var source: DispatchSourceRead?

    fileprivate init(path: String,
                     queue: DispatchQueue,
                     handler: @escaping (HotkeyMessage) -> Void) throws {
        self.path = path
        self.queue = queue
        self.handler = handler

        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        _ = chmod((path as NSString).deletingLastPathComponent, mode_t(S_IRWXU))
        if HotkeyDatagram.endpointIsActive(path) {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE))
        }
        _ = unlink(path)
        let socketDescriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard socketDescriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard HotkeyDatagram.setNonblocking(socketDescriptor) else {
            let failure = errno
            close(socketDescriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        descriptor = socketDescriptor

        let bound = HotkeyDatagram.withSocketAddress(path) { address, length in
            bind(socketDescriptor, address, length)
        }
        guard let result = bound, result == 0 else {
            let failure = errno
            close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        _ = chmod(path, mode_t(S_IRUSR | S_IWUSR))
        resources = HotkeyDatagramResources(descriptor: descriptor, path: path)
    }

    func start() {
        guard source == nil else { return }
        let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.drainMessages()
        }
        readSource.setCancelHandler { [resources] in
            resources.close()
        }
        source = readSource
        readSource.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func drainMessages() {
        var buffer = [UInt8](repeating: 0, count: HotkeyDatagram.maximumMessageSize)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            guard count > 0 else {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            guard let message = HotkeyDatagram.decode(Data(buffer.prefix(count))) else { continue }
            handler(message)
        }
    }

    deinit {
        source?.cancel()
        resources.close()
    }
}
