import Foundation

/// Provides per-instance namespacing so multiple Odyssey processes can run simultaneously.
///
/// Usage:  `open -n Odyssey.app --args --instance my-project`
///
/// When no `--instance` flag is passed, defaults to `"default"`.
/// All file paths, ports, and UserDefaults are namespaced under the instance name.
enum InstanceConfig {

    static let name: String = {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--instance"), idx + 1 < args.count {
            return args[idx + 1]
        }
        if tryAcquireLock(for: "default") { return "default" }
        return "instance-\(UUID().uuidString.prefix(8).lowercased())"
    }()

    // Held open for process lifetime so the flock stays acquired.
    nonisolated(unsafe) private static var _lockFd: Int32 = -1

    private static func tryAcquireLock(for instanceName: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".odyssey/instances/\(instanceName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockPath = dir.appendingPathComponent(".instance.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            _lockFd = fd
            return true
        }
        close(fd)
        return false
    }

    static let isDefault: Bool = name == "default"

    // MARK: - Directories

    static let baseDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".odyssey/instances/\(name)", isDirectory: true)
    }()

    static let dataDirectory: URL = baseDirectory.appendingPathComponent("data", isDirectory: true)
    static let blackboardDirectory: URL = baseDirectory.appendingPathComponent("blackboard", isDirectory: true)
    static let logDirectory: URL = baseDirectory.appendingPathComponent("logs", isDirectory: true)

    /// Ensures all instance directories exist on disk.
    static func ensureDirectories() {
        let fm = FileManager.default
        for dir in [dataDirectory, blackboardDirectory, logDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - UserDefaults

    static let userDefaultsSuiteName: String = "com.odyssey.app.\(name)"

    nonisolated(unsafe) static let userDefaults: UserDefaults = {
        UserDefaults(suiteName: userDefaultsSuiteName) ?? .standard
    }()

    // MARK: - Port Allocation

    /// Finds an available TCP port by binding to port 0 and reading the OS-assigned port.
    static func findFreePort() -> Int {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else { return 0 }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian

        var bindAddr = addr
        let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 0 }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var assignedAddr = sockaddr_in()
        let nameResult = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(sock, sockPtr, &len)
            }
        }
        guard nameResult == 0 else { return 0 }

        return Int(UInt16(bigEndian: assignedAddr.sin_port))
    }
}
