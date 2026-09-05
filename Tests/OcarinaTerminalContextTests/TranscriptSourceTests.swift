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
        let reading = await source.latestPrompts(
            for: TranscriptQuery(workingDirectory: workingDirectory)
        )
        #expect(reading?.prompts.first == "Fix the payment failure state on the checkout page.")
        #expect(reading?.sessionID == "session")
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
        let reading = await source.latestPrompts(
            for: TranscriptQuery(workingDirectory: URL(fileURLWithPath: "/Users/me/checkout"))
        )
        #expect(reading?.prompts.first == "Add the watchlist API endpoint.")
    }

    /// Writes a transcript carrying one human prompt, with explicit timestamps.
    private func writeClaudeSession(
        _ name: String,
        prompt: String,
        in directory: URL,
        created: Date,
        modified: Date
    ) throws {
        let url = directory.appendingPathComponent("\(name).jsonl")
        let line = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"\#(prompt)"}}"#
        try line.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.creationDate: created, .modificationDate: modified],
            ofItemAtPath: url.path
        )
    }

    private func claudeProject(in root: URL, for directory: URL) throws -> URL {
        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(ClaudeTranscriptSource.slug(for: directory), isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        return projectDirectory
    }

    @Test("A tab reads its own session, not whichever one wrote most recently")
    func claudeSessionIsBoundToTheProcess() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let workingDirectory = URL(fileURLWithPath: "/Users/me/checkout")
        let projectDirectory = try claudeProject(in: root, for: workingDirectory)
        let launch = Date()

        // A conversation from this morning, still the most recently written
        // file in the directory — this is what used to name every new tab.
        try writeClaudeSession(
            "stale",
            prompt: "Install the release build on this Mac.",
            in: projectDirectory,
            created: launch.addingTimeInterval(-3600),
            modified: launch.addingTimeInterval(60)
        )
        try writeClaudeSession(
            "mine",
            prompt: "Add the watchlist endpoint.",
            in: projectDirectory,
            created: launch.addingTimeInterval(5),
            modified: launch.addingTimeInterval(10)
        )

        let reading = await ClaudeTranscriptSource(root: root).latestPrompts(
            for: TranscriptQuery(workingDirectory: workingDirectory, sessionStartedAt: launch)
        )
        #expect(reading?.sessionID == "mine")
        #expect(reading?.prompts.first == "Add the watchlist endpoint.")
    }

    @Test("A resumed session predates its process, so a live file still counts")
    func claudeResumedSession() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let workingDirectory = URL(fileURLWithPath: "/Users/me/checkout")
        let projectDirectory = try claudeProject(in: root, for: workingDirectory)
        let launch = Date()

        // `claude --continue` reopens yesterday's file and writes into it.
        try writeClaudeSession(
            "resumed",
            prompt: "Finish the watchlist endpoint.",
            in: projectDirectory,
            created: launch.addingTimeInterval(-86_400),
            modified: launch.addingTimeInterval(30)
        )
        // A session that ended before this process started must not win.
        try writeClaudeSession(
            "abandoned",
            prompt: "Something else entirely.",
            in: projectDirectory,
            created: launch.addingTimeInterval(-7200),
            modified: launch.addingTimeInterval(-7000)
        )

        let reading = await ClaudeTranscriptSource(root: root).latestPrompts(
            for: TranscriptQuery(workingDirectory: workingDirectory, sessionStartedAt: launch)
        )
        #expect(reading?.sessionID == "resumed")
    }

    @Test("With no live session in the directory, a tab says nothing")
    func claudeNoLiveSession() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let workingDirectory = URL(fileURLWithPath: "/Users/me/checkout")
        let projectDirectory = try claudeProject(in: root, for: workingDirectory)
        let launch = Date()

        try writeClaudeSession(
            "yesterday",
            prompt: "Install the release build on this Mac.",
            in: projectDirectory,
            created: launch.addingTimeInterval(-86_400),
            modified: launch.addingTimeInterval(-86_000)
        )

        let reading = await ClaudeTranscriptSource(root: root).latestPrompts(
            for: TranscriptQuery(workingDirectory: workingDirectory, sessionStartedAt: launch)
        )
        #expect(reading == nil)
    }

    @Test("A missing transcript directory is silence, not a crash")
    func missingTranscripts() async {
        let source = ClaudeTranscriptSource(root: URL(fileURLWithPath: "/nonexistent-ocarina-root"))
        let reading = await source.latestPrompts(
            for: TranscriptQuery(workingDirectory: URL(fileURLWithPath: "/Users/me/checkout"))
        )
        #expect(reading == nil)
    }
}
