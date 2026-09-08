import Foundation
import Testing
@testable import OcarinaTerminalContext

@Suite("What I asked the agent")
struct AgentTaskTests {

    private func transcript(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tasks-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func prompt(_ text: String, uuid: String, source: String = "typed", sidechain: Bool = false) -> String {
        """
        {"type":"user","uuid":"\(uuid)","promptSource":"\(source)","isSidechain":\(sidechain),\
        "timestamp":"2026-09-05T10:00:00Z","message":{"role":"user","content":"\(text)"}}
        """
    }

    /// A prompt typed mid-turn and picked up by the turn already running.
    private func absorbed(_ text: String, uuid: String) -> String {
        """
        {"type":"attachment","uuid":"\(uuid)","isSidechain":false,\
        "timestamp":"2026-09-05T10:00:00Z","attachment":{"type":"queued_command",\
        "prompt":"\(text)","commandMode":"prompt","origin":{"kind":"human"},\
        "timestamp":"2026-09-05T10:00:00Z"}}
        """
    }

    /// Background work reporting back, which comes through the same queue.
    private func notification(_ text: String, uuid: String) -> String {
        """
        {"type":"attachment","uuid":"\(uuid)","isSidechain":false,\
        "timestamp":"2026-09-05T10:00:00Z","attachment":{"type":"queued_command",\
        "prompt":"\(text)","commandMode":"task-notification","origin":null,\
        "timestamp":"2026-09-05T10:00:00Z"}}
        """
    }

    private let endTurn = #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#
    private let toolUse = #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#

    @Test("A typed prompt becomes a task")
    func typedPromptIsATask() throws {
        let url = try transcript([prompt("Add a login screen to the app", uuid: "a")])
        let tasks = AgentTaskSource.tasks(inTranscript: url)
        #expect(tasks.count == 1)
        #expect(tasks[0].prompt == "Add a login screen to the app")
    }

    @Test("Only what the human asked for counts")
    func onlyHumanPrompts() throws {
        // System and suggestion-accepted prompts are the app talking. Listing
        // them as the user's tasks would misreport who asked.
        let url = try transcript([
            prompt("real request", uuid: "a"),
            prompt("injected", uuid: "b", source: "system"),
            prompt("a follow-up offered to me", uuid: "c", source: "suggestion_accepted"),
        ])
        #expect(AgentTaskSource.tasks(inTranscript: url).count == 1)
    }

    @Test("A prompt that waited in the queue is still the user asking")
    func queuedPromptsAreTasks() throws {
        // Typed while the agent was busy and delivered as its own turn once
        // the one in front of it ended. The words are the user's either way.
        let url = try transcript([
            prompt("first", uuid: "a"), endTurn,
            prompt("second", uuid: "b", source: "queued"), endTurn,
        ])
        let tasks = AgentTaskSource.tasks(inTranscript: url)
        #expect(tasks.map(\.prompt) == ["first", "second"])
    }

    @Test("A prompt absorbed mid-turn is a task of its own")
    func absorbedPromptsAreTasks() throws {
        // The one that made a session of many requests list one. Typed while
        // the agent was working and picked up inside the running turn, it is
        // never written as a `user` row — only as an attachment on the turn
        // that swallowed it — so reading `user` rows alone loses every prompt
        // after the first.
        let url = try transcript([
            prompt("move to geist sans", uuid: "a"),
            absorbed("and jetbrains mono for the terminal", uuid: "b"),
            endTurn,
        ])
        let tasks = AgentTaskSource.tasks(inTranscript: url)
        #expect(tasks.map(\.prompt) == ["move to geist sans", "and jetbrains mono for the terminal"])
        // Both were answered by the one turn, so both close on its end.
        #expect(tasks.map(\.state) == [.finished, .finished])
    }

    @Test("A task notification is not a task")
    func notificationsAreNotTasks() throws {
        // Background work reporting back arrives through the same queue door,
        // with no human origin on it.
        let url = try transcript([
            prompt("real request", uuid: "a"),
            notification("Agent finished: 3 files changed", uuid: "b"),
        ])
        #expect(AgentTaskSource.tasks(inTranscript: url).count == 1)
    }

    @Test("Subagent chatter is not the user asking for anything")
    func sidechainsExcluded() throws {
        let url = try transcript([
            prompt("mine", uuid: "a"),
            prompt("subagent", uuid: "b", sidechain: true),
        ])
        #expect(AgentTaskSource.tasks(inTranscript: url).count == 1)
    }

    @Test("A turn that ended marks the task finished")
    func endTurnFinishes() throws {
        let url = try transcript([prompt("do a thing", uuid: "a"), toolUse, endTurn])
        #expect(AgentTaskSource.tasks(inTranscript: url)[0].state == .finished)
    }

    @Test("Work still in flight stays open")
    func toolUseIsStillWorking() throws {
        let url = try transcript([prompt("do a thing", uuid: "a"), toolUse])
        #expect(AgentTaskSource.tasks(inTranscript: url)[0].state == .working)
    }

    @Test("Only the newest task can be unfinished")
    func onlyTheLastIsOpen() throws {
        let url = try transcript([
            prompt("first", uuid: "a"), endTurn,
            prompt("second", uuid: "b"), endTurn,
            prompt("third", uuid: "c"), toolUse,
        ])
        let tasks = AgentTaskSource.tasks(inTranscript: url)
        #expect(tasks.map(\.state) == [.finished, .finished, .working])
    }

    @Test("The slug matches the layout Claude Code writes")
    func slug() {
        #expect(AgentTaskSource.slug(for: URL(fileURLWithPath: "/Users/vaibhav")) == "-Users-vaibhav")
    }

    @Test("A prompt with no title of its own still gets a row")
    func alwaysTitled() throws {
        // TitleFormatter returns nothing for a prompt with no subject; an
        // untitled row is worse than a blunt one.
        let url = try transcript([prompt("do it", uuid: "a")])
        #expect(AgentTaskSource.tasks(inTranscript: url)[0].title.isEmpty == false)
    }
}

@Suite("Task titles")
struct AgentTaskTitleTests {

    @Test("A leading pasted link is not the task")
    func dropsLeadingURL() {
        let title = AgentTaskSource.title(
            from: "https://i.pinimg.com/736x/70/64/83/7064830.jpg Something like this, and a sound"
        )
        #expect(title.contains("pinimg") == false)
        #expect(title.isEmpty == false)
    }

    @Test("A summary is a handful of words, not the sentence")
    func isBrief() {
        let title = AgentTaskSource.title(
            from: "The toggle option should be near the right-hand side of the panel"
        )
        #expect(title.split(separator: " ").count <= 5)
        #expect(title.count <= 32)
        #expect(title.lowercased().contains("toggle"))
    }

    @Test("Words that carry nothing are dropped, in order")
    func dropsFiller() {
        #expect(AgentTaskSource.title(from: "The tooltip padding is breaking")
                == "Tooltip padding breaking")
    }

    @Test("A negation is never dropped")
    func keepsNegation() {
        // Losing the "not" turns a bug report into a request for the bug.
        let title = AgentTaskSource.title(from: "The tooltip is not going away when I hover away")
        #expect(title.lowercased().contains("not"))
    }

    @Test("Throat-clearing at the front goes")
    func dropsOpeners() {
        let title = AgentTaskSource.title(from: "Also, please just fix the login button on Safari")
        #expect(title.lowercased().hasPrefix("also") == false)
        #expect(title.lowercased().contains("login"))
    }

    @Test("The first sentence stands in for the whole prompt")
    func firstSentence() {
        let title = AgentTaskSource.title(
            from: "Add a dark mode toggle to settings. It should remember the choice."
        )
        #expect(title.lowercased().contains("remember") == false)
        #expect(title.lowercased().contains("dark"))
    }

    @Test("Stripping never leaves an empty row")
    func neverEmpty() {
        // A prompt made entirely of filler still has to show something.
        for prompt in ["do it", "can you", "the", "please"] {
            #expect(AgentTaskSource.title(from: prompt).isEmpty == false, "empty for '\(prompt)'")
        }
    }

    @Test("The result reads as a sentence, not a fragment mid-word")
    func sentenceCased() {
        let title = AgentTaskSource.title(from: "also the switch is too bright on the test build")
        #expect(title.first?.isUppercase == true)
        #expect(title.hasSuffix(",") == false)
    }
}

@Suite("Bulleted prompts")
struct AgentTaskBulletTests {
    @Test("A leading bullet is punctuation, not part of the task")
    func stripsBullet() {
        // The bullet goes; so does the article behind it, which is why this
        // starts at "To-do" rather than "The".
        #expect(
            AgentTaskSource.title(from: "- The to-do section: the tick should not be green")
                == "To-do section: tick not green"
        )
        #expect(AgentTaskSource.title(from: "* Fix the login button") == "Fix login button")
    }
}

@Suite("Tasks belong to a tab")
struct AgentTaskSessionTests {

    /// Two agents open on one project write two transcripts side by side.
    /// Reading whichever was written to last showed each tab the other's work,
    /// and made switching tabs flash the list you had just left.
    @Test("A tab's tasks are its own conversation's, not the folder's")
    func tasksAreTabCentric() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-tabs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = URL(fileURLWithPath: "/Users/me/checkout")
        let folder = root.appendingPathComponent(
            AgentTaskSource.slug(for: directory), isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func write(_ name: String, prompt: String, created: Date, modified: Date) throws {
            let line = """
            {"type":"user","promptSource":"typed","uuid":"\(name)",\
            "message":{"role":"user","content":"\(prompt)"}}
            """
            let url = folder.appendingPathComponent("\(name).jsonl")
            try line.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.creationDate: created, .modificationDate: modified],
                ofItemAtPath: url.path
            )
        }

        let now = Date()
        // The older conversation is the one still being typed into, so it is
        // also the most recently *modified* — which is the trap.
        try write("first", prompt: "Rewrite the checkout page",
                  created: now.addingTimeInterval(-3600), modified: now)
        try write("second", prompt: "Add the watchlist endpoint",
                  created: now.addingTimeInterval(-600),
                  modified: now.addingTimeInterval(-300))

        let source = AgentTaskSource(root: root)

        // The tab whose agent started ten minutes ago gets the file that
        // appeared after it did, not the busier neighbour.
        let second = source.tasks(for: directory, startedAt: now.addingTimeInterval(-620))
        #expect(second.first?.prompt == "Add the watchlist endpoint")

        // And the tab that has been open an hour gets its own.
        let first = source.tasks(for: directory, startedAt: now.addingTimeInterval(-3610))
        #expect(first.first?.prompt == "Rewrite the checkout page")

        // The fingerprint follows the same file, or a poll would compare one
        // tab's list against another tab's signature and skip the read.
        #expect(source.signature(for: directory, startedAt: now.addingTimeInterval(-620))
                != source.signature(for: directory, startedAt: now.addingTimeInterval(-3610)))
    }

    /// A shell opened beside a working agent. It has no conversation, and the
    /// resume fallback used to hand it the neighbour's — so a terminal opened
    /// to run one `git status` came up carrying somebody else's task list with
    /// a task still in progress on it.
    @Test("A plain terminal opened mid-task has no tasks of its own")
    func aPlainShellInheritsNothing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-shell-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = URL(fileURLWithPath: "/Users/me/checkout")
        let folder = root.appendingPathComponent(
            AgentTaskSource.slug(for: directory), isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let now = Date()
        let line = """
        {"type":"user","promptSource":"typed","uuid":"a",\
        "message":{"role":"user","content":"Rewrite the checkout page"}}
        """
        let url = folder.appendingPathComponent("busy.jsonl")
        try line.write(to: url, atomically: true, encoding: .utf8)
        // Opened an hour ago and being typed into right now: older than the
        // new tab, and modified after it — which is what the fallback looks
        // for.
        try FileManager.default.setAttributes(
            [.creationDate: now.addingTimeInterval(-3600), .modificationDate: now],
            ofItemAtPath: url.path
        )

        let source = AgentTaskSource(root: root)
        let openedJustNow = now.addingTimeInterval(-5)

        // A shell. Nothing of its own, and nothing borrowed.
        #expect(source.tasks(for: directory, startedAt: openedJustNow,
                             agentInForeground: false).isEmpty)
        #expect(source.signature(for: directory, startedAt: openedJustNow,
                                 agentInForeground: false) == nil)

        // An agent in the same tab, resuming that conversation, still gets it.
        #expect(source.tasks(for: directory, startedAt: openedJustNow,
                             agentInForeground: true).count == 1)
    }

    @Test("A shell is not an agent, and `claude` is")
    func agentsAreNamed() {
        #expect(AgentTaskSource.isAgent("claude"))
        #expect(AgentTaskSource.isAgent("Claude"))
        #expect(!AgentTaskSource.isAgent("zsh"))
        #expect(!AgentTaskSource.isAgent(nil))
    }
}
