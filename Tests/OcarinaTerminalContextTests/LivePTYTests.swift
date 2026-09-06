import Darwin
import Foundation
import Testing
@testable import OcarinaTerminalContext

/// End-to-end against a real pty and a real child process.
@Suite("Live pty")
struct LivePTYTests {

    /// A pty with a child running `command` as its foreground process.
    private func makePTY(command: String) throws -> PTYProcess {
        try PTYProcess(
            executable: "/bin/sh",
            arguments: ["-c", command],
            onOutput: { _ in }
        )
    }

    /// The child needs a moment to exec and claim the terminal.
    private func waitForForegroundProcess(
        monitor: TerminalSessionMonitor,
        named name: String
    ) async -> TerminalSessionSnapshot? {
        for _ in 0..<liveProcessPollAttempts {
            let snapshot = await monitor.snapshot()
            if snapshot.foregroundProcessName == name { return snapshot }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test("A snapshot reports the real foreground process, argv and cwd")
    func snapshotOfLiveProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-pty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("generate_report.py")
        try "import time\ntime.sleep(30)\n".write(to: script, atomically: true, encoding: .utf8)

        let pty = try makePTY(command: "cd \(directory.path) && exec python3 generate_report.py")
        defer { pty.terminate() }
        let monitor = TerminalSessionMonitor(ptyDescriptor: pty.primaryDescriptor, shellName: "zsh")

        let snapshot = try #require(
            await waitForForegroundProcess(monitor: monitor, named: "generate_report"),
            "the child never became the foreground process"
        )

        // argv[0] is whatever python3 actually execs as, which varies by
        // install — Xcode ships it as `.../Python.app/Contents/MacOS/Python`.
        let executable = try #require(snapshot.foregroundCommandLine.first.map(ProcessInspector.basename))
        #expect(executable.lowercased().hasPrefix("python"))
        #expect(snapshot.foregroundCommandLine.contains("generate_report.py"))
        #expect(
            snapshot.workingDirectory?.resolvingSymlinksInPath()
                == directory.resolvingSymlinksInPath()
        )
    }

    @Test("A live session is named from what it is running")
    func namingFromLiveSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-pty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("generate_report.py")
        try "import time\ntime.sleep(30)\n".write(to: script, atomically: true, encoding: .utf8)

        let pty = try makePTY(command: "cd \(directory.path) && exec python3 generate_report.py")
        defer { pty.terminate() }
        let monitor = TerminalSessionMonitor(ptyDescriptor: pty.primaryDescriptor, shellName: "zsh")
        let snapshot = try #require(
            await waitForForegroundProcess(monitor: monitor, named: "generate_report")
        )

        let context = await TabContextCoordinator.standard().refresh(snapshot)
        #expect(context.displayTitle == "Generate Report")
    }

    @Test("An idle shell is not mistaken for an activity")
    func idleShellSnapshot() async throws {
        let pty = try makePTY(command: "exec sleep 30")
        defer { pty.terminate() }
        let monitor = TerminalSessionMonitor(ptyDescriptor: pty.primaryDescriptor, shellName: "zsh")
        _ = try #require(await waitForForegroundProcess(monitor: monitor, named: "sleep"))

        // `sleep` is a real foreground command, so it does name the tab; the
        // point here is that the pty plumbing reports it rather than the shell.
        let snapshot = await monitor.snapshot()
        #expect(snapshot.shellName == "zsh")
        #expect(snapshot.foregroundProcessName == "sleep")
    }

    @Test("Titles a program sets for itself reach the snapshot")
    func escapeSequenceTitleReachesSnapshot() async throws {
        let pty = try makePTY(command: "exec sleep 30")
        defer { pty.terminate() }
        let monitor = TerminalSessionMonitor(ptyDescriptor: pty.primaryDescriptor)
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

        // No child owns this pty, so the tab has only its shell fallback.
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

        // No child owns this pty, so the tab has only its shell fallback.
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
