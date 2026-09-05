import Foundation
import Testing
@testable import MajoraTerminalContext
@testable import MajoraUI

/// Drives the SwiftUI model against a real shell on a real pty.
@Suite("Majora model")
@MainActor
struct MajoraModelTests {

    private func makeProjectDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("majora-ui-\(UUID().uuidString)", isDirectory: true)
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

    @Test("A new tab starts named for where it is")
    func newTabUsesProjectName() throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = MajoraModel()
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

        let model = MajoraModel(
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

    @Test("A hand-typed name wins and stops automatic naming")
    func manualRenameWins() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = MajoraModel(
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
        let model = MajoraModel()
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
}
