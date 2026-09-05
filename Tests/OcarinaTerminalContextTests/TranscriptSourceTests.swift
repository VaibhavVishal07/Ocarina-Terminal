import Foundation
import Testing
@testable import OcarinaTerminalContext

/// Fixtures mirror records taken from real transcripts on disk.
@Suite("Local session metadata")
struct TranscriptSourceTests {

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Claude transcripts yield the latest typed prompt, not tool results")
    func claudeTranscript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let workingDirectory = URL(fileURLWithPath: "/Users/me/checkout")
        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(ClaudeTranscriptSource.slug(for: workingDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        let lines = [
            #"{"type":"user","isSidechain":false,"origin":{"kind":"human"},"message":{"role":"user","content":"Fix the payment failure state on the checkout page."}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":"Looking."}}"#,
            // Tool results also arrive as type "user" but with an array payload.
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            // Sidechain traffic belongs to a subagent, not the user.
            #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"search the repo"}}"#
        ]
        try lines.joined(separator: "\n").write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let source = ClaudeTranscriptSource(root: root)
        let prompt = await source.latestHumanPrompt(forWorkingDirectory: workingDirectory)
        #expect(prompt == "Fix the payment failure state on the checkout page.")
    }

    @Test("Claude slugs match the on-disk project directory naming")
    func claudeSlug() {
        #expect(ClaudeTranscriptSource.slug(for: URL(fileURLWithPath: "/Users/me")) == "-Users-me")
        #expect(ClaudeTranscriptSource.slug(for: URL(fileURLWithPath: "/a/b.c")) == "-a-b-c")
    }

    @Test("Codex rollouts are matched to a terminal by their session cwd")
    func codexTranscript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let day = root.appendingPathComponent("2026/09/03", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

        func write(_ name: String, cwd: String, prompt: String) throws {
            let lines = [
                #"{"type":"session_meta","payload":{"cwd":"\#(cwd)","originator":"Codex CLI"}}"#,
                #"{"type":"event_msg","payload":{"type":"user_message","message":"\#(prompt)"}}"#
            ]
            try lines.joined(separator: "\n").write(
                to: day.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        try write("rollout-other.jsonl", cwd: "/Users/me/elsewhere", prompt: "unrelated work")
        try write("rollout-match.jsonl", cwd: "/Users/me/checkout", prompt: "Add the watchlist API endpoint.")

        let source = CodexTranscriptSource(root: root)
        let prompt = await source.latestHumanPrompt(
            forWorkingDirectory: URL(fileURLWithPath: "/Users/me/checkout")
        )
        #expect(prompt == "Add the watchlist API endpoint.")
    }

    @Test("A missing transcript directory is silence, not a crash")
    func missingTranscripts() async {
        let source = ClaudeTranscriptSource(root: URL(fileURLWithPath: "/nonexistent-ocarina-root"))
        let prompt = await source.latestHumanPrompt(
            forWorkingDirectory: URL(fileURLWithPath: "/Users/me/checkout")
        )
        #expect(prompt == nil)
    }
}
