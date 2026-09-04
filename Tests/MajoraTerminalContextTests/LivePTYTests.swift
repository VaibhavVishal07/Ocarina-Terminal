import Darwin
import Foundation
import Testing
@testable import MajoraTerminalContext

/// End-to-end against a real pty and a real child process.
@Suite("Live pty")
struct LivePTYTests {

    /// A pty with a child running `command` as its foreground process.
    private final class PTYFixture {
        let primary: Int32
        let replica: Int32
        let pid: pid_t

        init(command: String) throws {
            var primary: Int32 = 0
            var replica: Int32 = 0
            guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
                throw Failure.openpty
            }
            self.primary = primary
            self.replica = replica

            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            for descriptor in Int32(0)...Int32(2) {
                posix_spawn_file_actions_adddup2(&actions, replica, descriptor)
            }

            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            // The child needs its own session for the pty to become its
            // controlling terminal, which is what makes tcgetpgrp meaningful.
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

            var pid: pid_t = 0
            let parts: [String] = ["/bin/sh", "-c", command]
            var argv = parts.map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }

            guard posix_spawn(&pid, "/bin/sh", &actions, &attributes, &argv, environ) == 0 else {
                throw Failure.spawn
            }
            self.pid = pid
        }

        deinit {
            kill(pid, SIGKILL)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            close(primary)
            close(replica)
        }

        enum Failure: Error { case openpty, spawn }
    }

    /// The child needs a moment to exec and claim the terminal.
    private func waitForForegroundProcess(
        monitor: TerminalSessionMonitor,
        named name: String
    ) async -> TerminalSessionSnapshot? {
        for _ in 0..<40 {
            let snapshot = await monitor.snapshot()
            if snapshot.foregroundProcessName == name { return snapshot }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test("A snapshot reports the real foreground process, argv and cwd")
    func snapshotOfLiveProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("majora-pty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("generate_report.py")
        try "import time\ntime.sleep(30)\n".write(to: script, atomically: true, encoding: .utf8)

        let fixture = try PTYFixture(
            command: "cd \(directory.path) && exec python3 generate_report.py"
        )
        let monitor = TerminalSessionMonitor(ptyDescriptor: fixture.primary, shellName: "zsh")

        let snapshot = try #require(
            await waitForForegroundProcess(monitor: monitor, named: "generate_report"),
            "the child never became the foreground process"
        )

        #expect(snapshot.foregroundCommandLine.first.map(ProcessInspector.basename) == "python3")
        #expect(snapshot.foregroundCommandLine.contains("generate_report.py"))
        #expect(
            snapshot.workingDirectory?.resolvingSymlinksInPath()
                == directory.resolvingSymlinksInPath()
        )
    }

    @Test("A live session is named from what it is running")
    func namingFromLiveSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("majora-pty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("generate_report.py")
        try "import time\ntime.sleep(30)\n".write(to: script, atomically: true, encoding: .utf8)

        let fixture = try PTYFixture(
            command: "cd \(directory.path) && exec python3 generate_report.py"
        )
        let monitor = TerminalSessionMonitor(ptyDescriptor: fixture.primary, shellName: "zsh")
        let snapshot = try #require(
            await waitForForegroundProcess(monitor: monitor, named: "generate_report")
        )

        let context = await TabContextCoordinator.standard().refresh(snapshot)
        #expect(context.displayTitle == "Generate Report")
    }

    @Test("An idle shell is not mistaken for an activity")
    func idleShellSnapshot() async throws {
        let fixture = try PTYFixture(command: "exec sleep 30")
        let monitor = TerminalSessionMonitor(ptyDescriptor: fixture.primary, shellName: "zsh")
        _ = try #require(await waitForForegroundProcess(monitor: monitor, named: "sleep"))

        // `sleep` is a real foreground command, so it does name the tab; the
        // point here is that the pty plumbing reports it rather than the shell.
        let snapshot = await monitor.snapshot()
        #expect(snapshot.shellName == "zsh")
        #expect(snapshot.foregroundProcessName == "sleep")
    }

    @Test("Titles a program sets for itself reach the snapshot")
    func escapeSequenceTitleReachesSnapshot() async throws {
        let fixture = try PTYFixture(command: "exec sleep 30")
        let monitor = TerminalSessionMonitor(ptyDescriptor: fixture.primary)
        await monitor.ingest(Array("\u{1B}]0;Deploy Staging\u{07}".utf8))

        let snapshot = await monitor.snapshot()
        #expect(snapshot.escapeSequenceTitle == "Deploy Staging")
    }
}

@Suite("Naming service")
struct TabNamingServiceTests {

    @Test("Only changed titles are published")
    func publishesOnlyChanges() async throws {
        let coordinator = TabContextCoordinator(providers: [GenericProcessContextProvider()])
        let service = TabNamingService(coordinator: coordinator, interval: .milliseconds(20))

        var primary: Int32 = 0
        var replica: Int32 = 0
        try #require(openpty(&primary, &replica, nil, nil, nil) == 0)
        defer { close(primary); close(replica) }

        let monitor = TerminalSessionMonitor(ptyDescriptor: primary, shellName: "zsh")
        await service.attach(monitor)

        let updates = await service.updates()
        var iterator = updates.makeAsyncIterator()

        // Nothing owns this pty, so the tab settles on its shell fallback.
        await service.pollOnce()
        #expect(await iterator.next()?.displayTitle == "Zsh")

        // Repeated polls with unchanged context must not re-publish.
        await service.pollOnce()
        await service.pollOnce()

        await service.setManualTitle("Payments", for: monitor.tabID)
        #expect(await iterator.next()?.displayTitle == "Payments")

        let context = await service.context(for: monitor.tabID)
        #expect(context?.displayTitle == "Payments")
        #expect(context?.isAutoNamingEnabled == false)
    }

    @Test("Detaching a tab stops it being polled")
    func detachStopsPolling() async throws {
        let service = TabNamingService(coordinator: .standard())

        var primary: Int32 = 0
        var replica: Int32 = 0
        try #require(openpty(&primary, &replica, nil, nil, nil) == 0)
        defer { close(primary); close(replica) }

        let monitor = TerminalSessionMonitor(ptyDescriptor: primary, shellName: "zsh")
        await service.attach(monitor)
        await service.pollOnce()
        #expect(await service.context(for: monitor.tabID) != nil)

        await service.detach(tabID: monitor.tabID)
        await service.pollOnce()
        // The coordinator keeps what it knew; the service simply stops asking.
        #expect(await service.context(for: monitor.tabID)?.displayTitle == "Zsh")
    }
}
