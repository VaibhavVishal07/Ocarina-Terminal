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

    private let endTurn = #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#
    private let toolUse = #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#

    @Test("A typed prompt becomes a task")
    func typedPromptIsATask() throws {
        let url = try transcript([prompt("Add a login screen to the app", uuid: "a")])
        let tasks = AgentTaskSource.tasks(inTranscript: url)
        #expect(tasks.count == 1)
        #expect(tasks[0].prompt == "Add a login screen to the app")
    }

    @Test("Only what the human typed counts")
    func onlyTypedPrompts() throws {
        // queued, system and suggestion-accepted prompts are the app talking.
        // Listing them as the user's tasks would misreport who asked.
        let url = try transcript([
            prompt("real request", uuid: "a"),
            prompt("injected", uuid: "b", source: "system"),
            prompt("queued up", uuid: "c", source: "queued"),
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
