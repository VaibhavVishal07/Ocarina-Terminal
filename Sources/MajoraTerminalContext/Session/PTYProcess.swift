import Darwin
import Foundation

/// A child process running on its own pty.
///
/// Majora owns the pty rather than delegating it to the terminal widget,
/// because the naming layer needs the descriptor: `ProcessInspector` asks it
/// what currently holds the foreground, and the read loop forwards output to
/// both the renderer and `TerminalSessionMonitor.ingest`.
public final class PTYProcess: @unchecked Sendable {
    public enum Failure: Error, Sendable {
        case couldNotOpenPTY(errno: Int32)
    }

    /// The descriptor Majora reads and writes; the child holds the other end.
    public let primaryDescriptor: Int32
    public let pid: pid_t

    private let queue: DispatchQueue
    private let source: DispatchSourceRead
    private let lock = NSLock()
    private var isRunning = true

    /// - Parameter onOutput: called off the main thread with each chunk read.
    public init(
        executable: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        arguments: [String] = ["-l"],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        columns: Int = 80,
        rows: Int = 24,
        onOutput: @escaping @Sendable ([UInt8]) -> Void
    ) throws {
        // forkpty is openpty + fork + login_tty in one call, and login_tty is
        // the part that matters: it runs setsid and TIOCSCTTY in the child so
        // the pty becomes its controlling terminal. Without that, tcgetpgrp on
        // our end reports nothing and the naming layer is blind — dup2 alone
        // does not acquire a ctty, and zsh in particular ends up detached.
        var size = winsize(
            ws_row: UInt16(rows), ws_col: UInt16(columns),
            ws_xpixel: 0, ws_ypixel: 0
        )

        var resolved = environment ?? ProcessInfo.processInfo.environment
        resolved["TERM"] = resolved["TERM"] ?? "xterm-256color"

        // Allocated before the fork: only async-signal-safe calls are legal
        // between forkpty and execve.
        let cExecutable = strdup(executable)
        var cArguments = ([executable] + arguments).map { strdup($0) } + [nil]
        var cEnvironment = resolved.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let cDirectory = workingDirectory.map { strdup($0.path) }
        defer {
            free(cExecutable)
            cArguments.forEach { free($0) }
            cEnvironment.forEach { free($0) }
            if let cDirectory { free(cDirectory) }
        }

        var primary: Int32 = 0
        let childPID = forkpty(&primary, nil, nil, &size)
        guard childPID >= 0 else {
            throw Failure.couldNotOpenPTY(errno: errno)
        }
        if childPID == 0 {
            if let cDirectory { _ = chdir(cDirectory) }
            _ = execve(cExecutable, &cArguments, &cEnvironment)
            _exit(127)
        }

        primaryDescriptor = primary
        pid = childPID

        queue = DispatchQueue(label: "majora.pty.\(childPID)")
        source = DispatchSource.makeReadSource(fileDescriptor: primary, queue: queue)

        let descriptor = primary
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else { return }
            onOutput(Array(buffer.prefix(count)))
        }
        source.resume()
    }

    deinit {
        terminate()
    }

    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        _ = bytes.withUnsafeBytes { Darwin.write(primaryDescriptor, $0.baseAddress, $0.count) }
    }

    public func resize(columns: Int, rows: Int) {
        var size = winsize(
            ws_row: UInt16(rows), ws_col: UInt16(columns),
            ws_xpixel: 0, ws_ypixel: 0
        )
        _ = ioctl(primaryDescriptor, TIOCSWINSZ, &size)
    }

    public func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false

        source.cancel()
        kill(pid, SIGHUP)
        var status: Int32 = 0
        waitpid(pid, &status, WNOHANG)
        close(primaryDescriptor)
    }
}
