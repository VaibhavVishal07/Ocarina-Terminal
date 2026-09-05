import Foundation
import Testing
@testable import OcarinaTerminalContext

@Suite("Child environment")
struct EnvironmentTests {

    @Test("A parent session's markers are dropped")
    func markersAreDropped() {
        var environment = [
            "CLAUDECODE": "1",
            "CLAUDE_CODE_CHILD_SESSION": "abc",
            "CLAUDE_CODE_MESSAGING_TOKEN": "secret",
            "CLAUDE_PID": "123",
            "CLAUDE_EFFORT": "high",
            "PATH": "/usr/bin",
            "HOME": "/Users/someone"
        ]

        PTYProcess.removeInheritedSessionMarkers(from: &environment)

        #expect(environment["CLAUDECODE"] == nil)
        #expect(environment["CLAUDE_CODE_CHILD_SESSION"] == nil)
        #expect(environment["CLAUDE_CODE_MESSAGING_TOKEN"] == nil)
        #expect(environment["CLAUDE_PID"] == nil)
        #expect(environment["CLAUDE_EFFORT"] == nil)
        // The machine and the user survive.
        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["HOME"] == "/Users/someone")
    }

    @Test("A user's own credentials and config are left alone")
    func credentialsSurvive() {
        var environment = [
            "ANTHROPIC_API_KEY": "sk-test",
            "CLAUDE_CONFIG_DIR": "~/.claude",
            "EDITOR": "vim"
        ]

        PTYProcess.removeInheritedSessionMarkers(from: &environment)

        // These are the user's, exported for their own use. Only session
        // identity is ours to drop.
        #expect(environment["ANTHROPIC_API_KEY"] == "sk-test")
        #expect(environment["CLAUDE_CONFIG_DIR"] == "~/.claude")
        #expect(environment["EDITOR"] == "vim")
    }

    @Test("A real shell on a real pty never sees the marker")
    func liveShellDoesNotInheritTheMarker() async throws {
        let collected = Collected()
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_CHILD_SESSION"] = "leaked-value"

        let pty = try PTYProcess(
            executable: "/bin/sh",
            arguments: ["-c", "echo MARKER=[$CLAUDE_CODE_CHILD_SESSION]"],
            environment: environment,
            onOutput: { bytes in collected.append(bytes) }
        )
        defer { pty.terminate() }

        for _ in 0..<60 where !collected.text.contains("MARKER=") {
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(collected.text.contains("MARKER=[]"))
        #expect(!collected.text.contains("leaked-value"))
    }
}

/// Output arrives on the pty's own queue.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []

    func append(_ more: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        bytes.append(contentsOf: more)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
