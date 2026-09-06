import Foundation
import Testing
@testable import OcarinaTerminalContext
@testable import OcarinaUI

/// The naming that the tab strip and the task panel now share.
@Suite("Summarised names")
@MainActor
struct TaskSummariserTests {

    /// A cache of its own, so what the app has asked about cannot decide
    /// whether a test passes.
    private func summariser() -> TaskSummariser {
        TaskSummariser(cache: FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-titles-\(UUID().uuidString)")
            .appendingPathComponent("prompt-titles.json"))
    }

    @Test("The same question asked twice is one entry in the cache")
    func keyIgnoresLayout() {
        // Keyed by the words, so a prompt read from the tab's transcript and
        // the same prompt read for the panel are not asked about twice — and
        // so a title survives the transcript uuid it was first found under.
        let key = TaskSummariser.key(for: "Fix the payment flow")
        #expect(TaskSummariser.key(for: "  Fix the\n payment   flow  ") == key)
        #expect(TaskSummariser.key(for: "Fix the checkout flow") != key)
    }

    @Test("A tab shows the summarised name, and the filter's until it arrives")
    func tabPrefersTheSummary() {
        let summariser = summariser()
        let tab = TabItem(id: UUID(), title: "Toggle Option Near Right-hand")
        tab.summariser = summariser
        tab.activeTask = "can you move that toggle over to the right hand side please"
        tab.isConversation = true

        // Nothing has answered yet: the word filter's title is what is on
        // screen, which is the whole point of it running first.
        #expect(tab.title == "Toggle Option Near Right-hand")

        summariser.remember("Move toggle to right side", for: tab.activeTask!)
        #expect(tab.title == "Move toggle to right side")
    }

    @Test("A command line is left as the word filter read it")
    func commandsAreNotRewritten() {
        let summariser = summariser()
        let tab = TabItem(id: UUID(), title: "Dev Server")
        tab.summariser = summariser
        tab.activeTask = "npm run dev"

        // Not a conversation, so not a prompt, so not something a model that
        // writes to-do items should be asked about.
        summariser.remember("Run the development server", for: tab.activeTask!)
        #expect(tab.title == "Dev Server")
    }

    @Test("A hand-typed name is not something to improve on")
    func manualNameWins() {
        let summariser = summariser()
        let tab = TabItem(id: UUID(), title: "Payments")
        tab.summariser = summariser
        tab.activeTask = "fix the payment flow"
        tab.isConversation = true
        tab.isManuallyNamed = true

        summariser.remember("Fix payment flow", for: tab.activeTask!)
        #expect(tab.title == "Payments")
    }
}
