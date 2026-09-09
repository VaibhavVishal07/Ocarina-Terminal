import Foundation
import Testing
@testable import OcarinaTerminalContext
@testable import OcarinaUI

/// Drives the SwiftUI model against a real shell on a real pty.
@Suite("Ocarina model")
@MainActor
struct OcarinaModelTests {

    private func makeProjectDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Waits for a name to arrive, generously.
    ///
    /// 24 seconds, which is absurd for a thing that takes well under one on an
    /// idle machine — and the number is about the machine, not the feature.
    /// This test boots a real login shell and `exec`s a real Python into it,
    /// and the suite runs its suites concurrently: at 8 seconds it failed
    /// roughly one full run in three while passing every time it was run on
    /// its own. A test that cries wolf at that rate costs more than the minute
    /// it saves, because it makes every green run afterwards worth less.
    private func waitForTitle(_ tab: TabItem, toBecome expected: String) async -> Bool {
        for _ in 0..<240 {
            if tab.title == expected { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// There is no switch any more, and no ⌘J. The panel is shown whenever an
    /// agent is in front of the selected tab, which is the only condition
    /// left — a list of outstanding work you can turn off is a list you turn
    /// off and then do not have when it matters.
    @Test("Tasks poll from the moment the model starts, with nothing to turn on")
    func taskPollingIsUnconditional() {
        let model = OcarinaModel()
        model.startWatchingTasks()
        // Nothing to assert about a switch: what matters is that asking for
        // the list never depends on one.
        #expect(model.tasks.isEmpty)
    }

    @Test("Nothing shells out for names until the terminal is used")
    func summariserWaitsForInput() throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }

        // Summarising runs the `claude` binary, and a subprocess asks for its
        // permissions in Ocarina's name. A window that has only just opened has
        // asked for nothing, so it must not have earned that yet.
        #expect(!model.summarisingAllowed)
    }

    @Test("Typing is what lets the summariser run")
    func inputAllowsSummarising() throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }
        #expect(!model.summarisingAllowed)

        model.session(for: tab.id)?.type("x")
        #expect(model.summarisingAllowed)
    }

    @Test("A new tab starts named for where it is")
    func newTabUsesProjectName() throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }

        #expect(!tab.title.isEmpty)
        #expect(model.selectedTabID == tab.id)
        #expect(model.session(for: tab.id) != nil)
    }

    /// The rule that replaced "the tab is named after the work".
    ///
    /// A long-running command used to rename the tab to what it was doing. The
    /// name is the project now and it holds while the work changes underneath
    /// it — what the tab is *doing* is the dot's job, and the panel's, and the
    /// menu bar's. This asserts the holding.
    @Test("Running a command does not rename the tab")
    func nameSurvivesTheWork() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "import time\ntime.sleep(60)\n".write(
            to: directory.appendingPathComponent("generate_report.py"),
            atomically: true,
            encoding: .utf8
        )

        let model = OcarinaModel(
            namingService: TabNamingService(interval: .milliseconds(50))
        )
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }
        let session = try #require(model.session(for: tab.id))
        model.start()
        let named = tab.title

        try? await Task.sleep(for: .milliseconds(800))
        session.send(text: "exec python3 generate_report.py\n")
        // Long enough that the old behaviour would certainly have renamed it.
        try? await Task.sleep(for: .seconds(3))

        #expect(tab.title == named, "the project name has to outlast the work")
        // The secondary line still names the process and where it is running,
        // which is where "what it is doing" belongs.
        #expect(tab.subtitle?.contains(directory.lastPathComponent) == true)
    }

    @Test("An empty rename leaves the tab's name alone")
    func emptyRenameIsIgnored() throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }
        let original = tab.title

        model.rename(tab.id, to: "")
        model.rename(tab.id, to: "   ")

        // Clicking away from an empty rename field falls back to the name the
        // tab already had, rather than clearing it.
        #expect(tab.title == original)
        #expect(!tab.isManuallyNamed)
    }

    @Test("A hand-typed name wins and stops automatic naming")
    func manualRenameWins() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel(
            namingService: TabNamingService(interval: .milliseconds(50))
        )
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }
        let session = try #require(model.session(for: tab.id))
        model.start()

        model.rename(tab.id, to: "Payments")
        #expect(tab.title == "Payments")
        #expect(tab.isManuallyNamed)

        try? await Task.sleep(for: .milliseconds(800))
        session.send(text: "exec sleep 60\n")
        try? await Task.sleep(for: .milliseconds(1200))

        #expect(tab.title == "Payments")
    }

    @Test("Closing a tab removes it and selects another")
    func closingTabs() throws {
        let model = OcarinaModel()
        let first = model.newTab()
        let second = model.newTab()

        #expect(model.selectedTabID == second.id)
        model.closeTab(second.id)
        #expect(model.tabs.map(\.id) == [first.id])
        #expect(model.selectedTabID == first.id)

        model.closeTab(first.id)
        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
    }

    @Test("Closing the tab you are in lands on its neighbour, not the first tab")
    func closingSelectsNeighbour() throws {
        let model = OcarinaModel()
        let first = model.newTab()
        _ = model.newTab()
        let third = model.newTab()
        let fourth = model.newTab()

        model.selectTab(third.id)
        model.closeTab(third.id)
        // The tab that took its place in the column, not the top of the list.
        #expect(model.selectedTabID == fourth.id)

        // Closing the last one in the column has no tab after it, so the
        // selection falls back a row rather than off the end.
        model.closeTab(fourth.id)
        #expect(model.selectedTabID == model.tabs.last?.id)
        #expect(model.tabs.count == 2)

        // A tab that is already gone must not move the selection.
        let selected = model.selectedTabID
        model.closeTab(third.id)
        #expect(model.selectedTabID == selected)
        #expect(model.tabs.count == 2)

        // And a tab that is still open always has a session behind it, which
        // is what decides whether the landing screen is drawn.
        #expect(model.selectedSession != nil)
        _ = first
    }

    // MARK: - Moving between sessions

    private func windowWithTabs(_ count: Int) -> (OcarinaModel, [TabItem]) {
        let model = OcarinaModel()
        let made = (0..<count).map { _ in model.newTab() }
        return (model, made)
    }

    @Test("Next and previous walk the column and wrap")
    func steppingWrapsRoundTheColumn() {
        let (model, tabs) = windowWithTabs(3)
        defer { tabs.forEach { model.closeTab($0.id) } }

        // A new tab selects itself, so we start on the last one.
        #expect(model.selectedTabID == tabs[2].id)
        model.selectNextTab()
        #expect(model.selectedTabID == tabs[0].id)
        model.selectPreviousTab()
        #expect(model.selectedTabID == tabs[2].id)
        model.selectPreviousTab()
        #expect(model.selectedTabID == tabs[1].id)
    }

    @Test("One session has nowhere to step to")
    func steppingNeedsSomewhereToGo() {
        let (model, tabs) = windowWithTabs(1)
        defer { tabs.forEach { model.closeTab($0.id) } }
        model.selectNextTab()
        #expect(model.selectedTabID == tabs[0].id)
    }

    @Test("Going to a position counts from one, and ignores what is not there")
    func goingToAPosition() {
        let (model, tabs) = windowWithTabs(3)
        defer { tabs.forEach { model.closeTab($0.id) } }

        model.selectTab(at: 1)
        #expect(model.selectedTabID == tabs[0].id)
        model.selectTab(at: 3)
        #expect(model.selectedTabID == tabs[2].id)

        // Out of range does nothing rather than clamping: ⌘7 with three tabs
        // open is a slip, and landing on the third answers a question that was
        // not asked.
        model.selectTab(at: 7)
        #expect(model.selectedTabID == tabs[2].id)
        model.selectTab(at: 0)
        #expect(model.selectedTabID == tabs[2].id)
    }

    @Test("The palette's order is what you looked at last, not what you made last")
    func recencyLeadsThePalette() {
        let (model, tabs) = windowWithTabs(4)
        defer { tabs.forEach { model.closeTab($0.id) } }

        model.selectTab(tabs[0].id)
        model.selectTab(tabs[2].id)
        // Most recent first, then the rest in the order they were visited,
        // and the column's own order behind that.
        #expect(model.tabsByRecency.map(\.id).prefix(3)
                == [tabs[2].id, tabs[0].id, tabs[3].id])
        // Every open session is in it — the palette's list is never shorter
        // than the sidebar's.
        #expect(Set(model.tabsByRecency.map(\.id)) == Set(tabs.map(\.id)))
    }

    @Test("A closed session leaves the order with it")
    func closingLeavesNoGhost() {
        let (model, tabs) = windowWithTabs(3)
        model.selectTab(tabs[0].id)
        model.closeTab(tabs[0].id)
        defer { tabs.dropFirst().forEach { model.closeTab($0.id) } }

        #expect(!model.tabsByRecency.contains { $0.id == tabs[0].id })
        #expect(model.tabsByRecency.count == 2)
        // And whatever the close landed on is now the most recent, so the
        // palette does not open on the tab you just left.
        #expect(model.tabsByRecency.first?.id == model.selectedTabID)
    }

    // MARK: - Ringing

    @Test("A ring in the tab you are looking at is not news")
    func ringingWhereYouAlreadyAre() {
        let model = OcarinaModel()
        let a = model.newTab(), b = model.newTab()
        defer { [a, b].forEach { model.closeTab($0.id) } }

        // b is selected — it was made last.
        model.session(for: b.id)?.onBell?()
        #expect(!b.needsAttention, "you are here; you can see the prompt")

        model.session(for: a.id)?.onBell?()
        #expect(a.needsAttention)
        #expect(a.displayActivity == .needsYou)
    }

    @Test("Looking at a tab is the answer to it")
    func lookingSettlesIt() {
        let model = OcarinaModel()
        let a = model.newTab(), b = model.newTab()
        defer { [a, b].forEach { model.closeTab($0.id) } }

        model.session(for: a.id)?.onBell?()
        #expect(a.needsAttention)
        model.selectTab(a.id)
        // No button, no dismiss: anything else would be a second thing to do
        // after the thing you already did.
        #expect(!a.needsAttention)
        #expect(a.displayActivity == a.activity)
    }

    @Test("A failed tab keeps its number rather than its ring")
    func failureOutranksTheRing() {
        let model = OcarinaModel()
        let a = model.newTab(), b = model.newTab()
        defer { [a, b].forEach { model.closeTab($0.id) } }

        a.activity = .failed(exitCode: 127)
        model.session(for: a.id)?.onBell?()
        #expect(a.needsAttention)
        // The mark is still recorded — it did ring — but the column draws the
        // failure, because a number is worth more than a ring.
        #expect(a.displayActivity == .failed(exitCode: 127))
    }
}
