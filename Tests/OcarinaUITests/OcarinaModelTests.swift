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

    private func waitForTitle(_ tab: TabItem, toBecome expected: String) async -> Bool {
        for _ in 0..<80 {
            if tab.title == expected { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @Test("The task panel starts open and the switch closes it")
    func taskPanelToggles() {
        let model = OcarinaModel()
        // Open is the resting state: the panel is part of the window, and a
        // list you have to go and find is a list nobody reads.
        #expect(model.isTaskPanelVisible)

        model.setTaskPanel(visible: false)
        #expect(!model.isTaskPanelVisible)

        model.setTaskPanel(visible: true)
        #expect(model.isTaskPanelVisible)
        model.setTaskPanel(visible: false)
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

    @Test("Running a command renames the tab to what it is doing")
    func tabFollowsActivity() async throws {
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

        // Let the login shell finish starting before typing at it.
        try? await Task.sleep(for: .milliseconds(800))
        session.send(text: "exec python3 generate_report.py\n")

        #expect(await waitForTitle(tab, toBecome: "Generate Report"))
        // The secondary line names the process and where it is running.
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
}
