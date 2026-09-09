import Foundation
import Testing
@testable import OcarinaTerminalContext

/// One message is very often not one job.
///
/// The panel says what is outstanding, so a prompt asking for three things has
/// to be three rows — and a prompt asking for one thing in three sentences has
/// to stay one. Only the cuts the user made themselves are read: a list they
/// wrote as a list, and a sentence that opens by announcing another item.
@Suite("Splitting a prompt into asks")
struct AskSplittingTests {

    private func asks(_ prompt: String) -> [String] {
        AgentTaskSource.asks(in: prompt)
    }

    // MARK: - Lists

    @Test("A numbered list is one ask per number")
    func numberedList() {
        let split = asks("""
        1. Fix the tab naming
        2. Add tests for the project locator
        3. Update the design doc
        """)
        #expect(split == [
            "Fix the tab naming",
            "Add tests for the project locator",
            "Update the design doc"
        ])
    }

    @Test("A bulleted list is one ask per bullet")
    func bulletedList() {
        #expect(asks("- fix the naming\n- add the tests") == ["fix the naming", "add the tests"])
    }

    @Test("`1)` counts as much as `1.`")
    func parenthesisedNumbers() {
        #expect(asks("1) fix the naming\n2) add the tests").count == 2)
    }

    /// An item that runs onto a second line is still one item.
    @Test("A wrapped item stays one ask")
    func wrappedItem() {
        let split = asks("""
        - Fix the tab naming so that it walks up
          to the repository root
        - Add tests
        """)
        #expect(split == ["Fix the tab naming so that it walks up to the repository root", "Add tests"])
    }

    /// "Do the following:" is not a job, it is a colon.
    @Test("A lead-in ending in a colon is dropped")
    func leadInIsDropped() {
        #expect(asks("Please do the following:\n- fix naming\n- add tests").count == 2)
    }

    /// A sentence that asked for something before the list is its own row.
    @Test("A preamble that asked for something is kept")
    func preambleThatAsks() {
        let split = asks("""
        The tab is not picking up the project name at all.
        - fix the locator
        - add tests
        """)
        #expect(split.count == 3)
        #expect(split.first == "The tab is not picking up the project name at all.")
    }

    // MARK: - Announced items

    @Test("A sentence opening with \"Also\" is a second ask")
    func alsoAnnouncesAnItem() {
        let split = asks("Fix the tab naming. Also update the design doc.")
        #expect(split == ["Fix the tab naming.", "Also update the design doc."])
    }

    @Test("\"One more thing\" announces an item")
    func oneMoreThing() {
        #expect(asks("Fix the naming. One more thing, add the tests.").count == 2)
    }

    /// A sentence that merely follows another is part of it. The panel would be
    /// useless if every full stop made a row.
    @Test("An ordinary second sentence is not a second ask")
    func proseStaysWhole() {
        let prompt = "Fix the tab naming. It should walk up to the repository root."
        #expect(asks(prompt) == [prompt])
    }

    @Test("A paragraph of prose is one ask")
    func paragraphIsOneAsk() {
        let prompt = """
        The tab is yet not picking up the context of the project and the name \
        of the project. Work on it because that is one of the key features.
        """
        #expect(asks(prompt) == [prompt])
    }

    // MARK: - Things that look like lists and are not

    /// The hazard that would make this feature worse than no feature: a pasted
    /// diff is line after line opening with `-`.
    @Test("A pasted diff is not a list of tasks")
    func diffIsNotAList() {
        let prompt = """
        This patch is wrong:
        --- a/File.swift
        +++ b/File.swift
        - let x = 1
        - let y = 2
        """
        #expect(asks(prompt) == [prompt.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    @Test("A fenced block is not read for items")
    func fencedBlockIsIgnored() {
        let prompt = """
        Make this compile:
        ```
        1. one
        2. two
        ```
        """
        #expect(asks(prompt).count == 1)
    }

    /// A list is a list of jobs up to a point; past it, it is data somebody
    /// pasted and the panel must not turn into a copy of it.
    @Test("A very long list is data, not tasks")
    func longListIsData() {
        let prompt = (1...20).map { "- item \($0)" }.joined(separator: "\n")
        #expect(asks(prompt).count == 1)
    }

    /// Found against the user's own transcripts: a prompt carrying a block of
    /// pasted CSS became a to-do list of CSS properties, because every line of
    /// it opens with `-webkit-`. A bullet needs the space after it.
    @Test("A property that opens with a hyphen is not a bullet")
    func hyphenatedPropertyIsNotABullet() {
        let prompt = """
        Make the panel glassy:
        -webkit-backdrop-filter: blur(4px);
        -webkit-mask-composite: xor;
        """
        #expect(asks(prompt).count == 1)
    }

    /// Also found against real prompts: the request the whole message was
    /// about ended in a colon, so it was read as a lead-in and thrown away —
    /// leaving the panel listing four sub-points of a job it had dropped.
    @Test("A long preamble ending in a colon is still the ask")
    func longPreambleEndingInAColonIsKept() {
        let split = asks("""
        Build me a landing page for this tool and make it extremely clean. \
        It should answer these questions:
        - What is the separation?
        - What makes this product great?
        """)
        #expect(split.count == 3)
        #expect(split.first?.hasPrefix("Build me a landing page") == true)
    }

    @Test("A short lead-in ending in a colon is still dropped")
    func shortLeadInIsStillDropped() {
        #expect(asks("Here is what I need:\n- fix naming\n- add tests").count == 2)
    }

    @Test("A single item is not a list")
    func oneItemIsNotAList() {
        #expect(asks("- fix the naming").count == 1)
    }

    @Test("An empty-handed prompt still yields itself")
    func alwaysYieldsSomething() {
        #expect(asks("fix it") == ["fix it"])
    }
}
