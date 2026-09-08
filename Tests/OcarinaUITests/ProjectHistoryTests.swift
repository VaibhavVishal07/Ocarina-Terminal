import Foundation
import OcarinaTerminalContext
import Testing
@testable import OcarinaUI

/// The cross-session task history: tabs in, folders out.
@Suite("Project history")
struct ProjectHistoryTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func task(_ title: String, _ minutes: Double, _ state: AgentTask.State = .finished)
        -> AgentTask
    {
        AgentTask(
            id: title, title: title, prompt: "please \(title)",
            askedAt: start.addingTimeInterval(minutes * 60), state: state
        )
    }

    private func reading(
        _ tabTitle: String, in path: String, _ tasks: [AgentTask], id: UUID = UUID()
    ) -> ProjectHistory.Reading {
        ProjectHistory.Reading(
            tabID: id, tabTitle: tabTitle,
            directory: URL(fileURLWithPath: path), tasks: tasks
        )
    }

    @Test("Tabs are gathered under the folder they are working in")
    func groupsByFolder() {
        let history = ProjectHistory.group([
            reading("Fix nav", in: "/Users/x/portfolio", [task("Fix mobile navigation", 1)]),
            reading("Themes", in: "/Users/x/ocarina", [task("Add five themes", 2)]),
        ], current: nil)

        #expect(history.count == 2)
        #expect(Set(history.map(\.name)) == ["portfolio", "ocarina"])
    }

    /// The heading is the folder's own name, not the whole path — a column
    /// 230pt wide cannot show `/Users/x/Projects/portfolio` and the last
    /// component is the part anybody would say out loud.
    @Test("A folder is named by its last component")
    func folderName() {
        let history = ProjectHistory.group(
            [reading("t", in: "/Users/x/Projects/portfolio", [task("a", 1)])], current: nil
        )
        #expect(history.first?.name == "portfolio")
    }

    @Test("The folder you are in leads")
    func currentLeads() {
        let history = ProjectHistory.group([
            // Asked more recently, and still second.
            reading("Themes", in: "/Users/x/ocarina", [task("Add themes", 90)]),
            reading("Fix nav", in: "/Users/x/portfolio", [task("Fix nav", 1)]),
        ], current: URL(fileURLWithPath: "/Users/x/portfolio"))

        #expect(history.first?.name == "portfolio")
        #expect(history.first?.isCurrent == true)
        #expect(history.last?.isCurrent == false)
    }

    @Test("Otherwise the most recently asked folder leads")
    func recencyLeads() {
        let history = ProjectHistory.group([
            reading("Old", in: "/Users/x/alpha", [task("ages ago", 1)]),
            reading("New", in: "/Users/x/beta", [task("just now", 500)]),
        ], current: nil)
        #expect(history.map(\.name) == ["beta", "alpha"])
    }

    @Test("Newest ask first inside a folder")
    func newestFirst() {
        let history = ProjectHistory.group([
            reading("t", in: "/Users/x/p", [task("first", 1), task("third", 30), task("second", 10)]),
        ], current: nil)
        #expect(history.first?.entries.map(\.task.title) == ["third", "second", "first"])
    }

    /// A terminal where no agent has been asked anything is not history, it is
    /// an empty terminal — and a heading with nothing under it is worse than no
    /// heading.
    @Test("A tab with nothing asked in it gets no heading")
    func emptyTabsDropped() {
        let history = ProjectHistory.group([
            reading("Shell", in: "/Users/x/quiet", []),
            reading("Work", in: "/Users/x/busy", [task("something", 1)]),
        ], current: nil)
        #expect(history.map(\.name) == ["busy"])
    }

    /// Two tabs in one folder is one heading, and the only case where a row has
    /// to say which tab it came from.
    @Test("Two tabs in one folder share a heading and are marked as shared")
    func twoTabsOneFolder() {
        let history = ProjectHistory.group([
            reading("Server", in: "/Users/x/app", [task("run the dev server", 5)]),
            reading("Tests", in: "/Users/x/app", [task("write the tests", 6)]),
        ], current: nil)

        #expect(history.count == 1)
        #expect(history.first?.isShared == true)
        #expect(history.first?.entries.count == 2)
    }

    @Test("One tab in a folder is not shared")
    func oneTabNotShared() {
        let history = ProjectHistory.group(
            [reading("Only", in: "/Users/x/app", [task("a", 1), task("b", 2)])], current: nil
        )
        #expect(history.first?.isShared == false)
    }

    /// `/tmp` and `/private/tmp` are the same folder. Two headings for one
    /// project is exactly the failure this view exists to fix.
    @Test("The same folder reached by two paths is one heading")
    func pathsAreStandardised() {
        let history = ProjectHistory.group([
            reading("A", in: "/tmp", [task("a", 1)]),
            reading("B", in: "/private/tmp", [task("b", 2)]),
        ], current: URL(fileURLWithPath: "/tmp"))

        #expect(history.count == 1)
        #expect(history.first?.isCurrent == true)
    }

    @Test("Working asks are counted per folder")
    func workingCount() {
        let history = ProjectHistory.group([
            reading("t", in: "/Users/x/p", [
                task("done", 1), task("still going", 2, .working), task("also going", 3, .working),
            ]),
        ], current: nil)
        #expect(history.first?.working == 2)
    }

    /// Every row has to name a tab that can be selected, or the click has
    /// nowhere to go.
    @Test("Every entry carries the tab it came from")
    func entriesCarryTheirTab() {
        let server = UUID()
        let tests = UUID()
        let history = ProjectHistory.group([
            reading("Server", in: "/Users/x/app", [task("run", 5)], id: server),
            reading("Tests", in: "/Users/x/app", [task("test", 6)], id: tests),
        ], current: nil)

        let entries = try? #require(history.first).entries
        #expect(entries?.first(where: { $0.task.title == "run" })?.tabID == server)
        #expect(entries?.first(where: { $0.task.title == "test" })?.tabID == tests)
    }

    @Test("Nothing open is an empty history, not a crash")
    func nothingOpen() {
        #expect(ProjectHistory.group([], current: nil).isEmpty)
    }
}
