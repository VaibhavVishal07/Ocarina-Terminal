import Darwin
import Foundation
import Testing
@testable import OcarinaTerminalContext

@Suite("Tab activity")
struct ActivityTests {

    /// A pty with no child, so activity comes only from what is ingested.
    private func makeMonitor() throws -> (TerminalSessionMonitor, () -> Void) {
        var primary: Int32 = 0
        var replica: Int32 = 0
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }
        let monitor = TerminalSessionMonitor(ptyDescriptor: primary, shellName: "zsh")
        return (monitor, { close(primary); close(replica) })
    }

    @Test("A fresh terminal is idle")
    func startsIdle() async throws {
        let (monitor, cleanup) = try makeMonitor()
        defer { cleanup() }
        #expect(await monitor.snapshot().activity == .idle)
    }

    @Test("Shell integration drives running, finished and failed")
    func integrationDrivesActivity() async throws {
        let (monitor, cleanup) = try makeMonitor()
        defer { cleanup() }

        await monitor.ingest(Array("\u{1B}]133;C\u{07}".utf8))
        #expect(await monitor.snapshot().activity == .running)

        await monitor.ingest(Array("\u{1B}]133;D;0\u{07}".utf8))
        #expect(await monitor.snapshot().activity == .succeeded)

        await monitor.ingest(Array("\u{1B}]133;C\u{07}".utf8))
        #expect(await monitor.snapshot().activity == .running)

        await monitor.ingest(Array("\u{1B}]133;D;127\u{07}".utf8))
        #expect(await monitor.snapshot().activity == .failed(exitCode: 127))
    }

    @Test("A busy terminal is detected even without shell integration")
    func fallsBackToForegroundProcess() async throws {
        let pty = try PTYProcess(
            executable: "/bin/sh",
            arguments: ["-c", "exec sleep 30"],
            onOutput: { _ in }
        )
        defer { pty.terminate() }
        let monitor = TerminalSessionMonitor(ptyDescriptor: pty.primaryDescriptor, shellName: "zsh")

        for _ in 0..<40 {
            if await monitor.snapshot().foregroundProcessName == "sleep" { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(await monitor.snapshot().activity == .running)
    }

    @Test("A failing command turns the tab's dot red, end to end in a real zsh")
    func realShellReportsFailure() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-si-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let environment = ShellIntegration.environment(
            forShell: "/bin/zsh",
            supportDirectory: support
        )

        // The monitor is built after the pty, so output is buffered until then.
        let box = MonitorBox()
        let pty = try PTYProcess(
            executable: "/bin/zsh",
            arguments: ["-l"],
            environment: environment
        ) { bytes in
            box.forward(bytes)
        }
        defer { pty.terminate() }

        let monitor = TerminalSessionMonitor(ptyDescriptor: pty.primaryDescriptor, shellName: "zsh")
        box.attach(monitor)

        // Let the login shell finish starting before typing at it.
        try? await Task.sleep(for: .milliseconds(1000))
        pty.write(Array("false\n".utf8))

        var activity: TabActivity = .idle
        for _ in 0..<40 {
            activity = await monitor.snapshot().activity
            if case .failed = activity { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(activity == .failed(exitCode: 1))

        pty.write(Array("true\n".utf8))
        for _ in 0..<40 {
            activity = await monitor.snapshot().activity
            if activity == .succeeded { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(activity == .succeeded)
    }
}

/// Bridges the pty's background read callback to the monitor actor.
private final class MonitorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var monitor: TerminalSessionMonitor?
    private var pending: [[UInt8]] = []

    func attach(_ monitor: TerminalSessionMonitor) {
        lock.lock()
        self.monitor = monitor
        let backlog = pending
        pending = []
        lock.unlock()
        Task { for chunk in backlog { await monitor.ingest(chunk) } }
    }

    func forward(_ bytes: [UInt8]) {
        lock.lock()
        guard let monitor else {
            pending.append(bytes)
            lock.unlock()
            return
        }
        lock.unlock()
        Task { await monitor.ingest(bytes) }
    }
}
