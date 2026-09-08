import Foundation
import OcarinaTerminalContext
import Testing
@testable import OcarinaUI

/// What a tab is called.
///
/// It used to be the work: the prompt, through a word filter, then through a
/// model that rewrote it as a to-do item. A name that changes every time you
/// ask for something is not a name — you cannot learn the column and you cannot
/// point at a tab. It is the project now.
@MainActor
@Suite("Tab naming")
struct TabNamingTests {

    private func tab(_ fallback: String, project: String? = nil) -> TabItem {
        let item = TabItem(id: UUID(), title: fallback)
        item.project = project
        return item
    }

    @Test("A tab is called after the folder it is in")
    func theProjectNamesIt() {
        #expect(tab("Fix Checkout Page", project: "Ocarina").title == "Ocarina")
    }

    /// The old behaviour, kept for the case it was always right for: a shell in
    /// a directory that is not a project has no project name to take.
    @Test("With no project, the generated name stands in")
    func fallsBackWhereThereIsNoProject() {
        #expect(tab("Dev Server").title == "Dev Server")
    }

    @Test("A hand-typed name beats the project")
    func manualWins() {
        let item = tab("Payments", project: "Ocarina")
        item.isManuallyNamed = true
        #expect(item.title == "Payments")
    }

    /// The one thing a column of project names must not do is print the same
    /// word twice.
    @Test("Two tabs in one folder are told apart")
    func repeatsAreNumbered() {
        let a = tab("a", project: "Ocarina")
        let b = tab("b", project: "Portfolio")
        let c = tab("c", project: "Ocarina")
        OcarinaModel.renumber([a, b, c])

        // The first keeps the bare name, so a tab is never renamed because
        // another tab appeared beside it.
        #expect(a.title == "Ocarina")
        #expect(b.title == "Portfolio")
        #expect(c.title == "Ocarina 2")
    }

    @Test("A third in the same folder keeps counting")
    func threeInAFolder() {
        let tabs = [tab("a", project: "Ocarina"), tab("b", project: "Ocarina"),
                    tab("c", project: "Ocarina")]
        OcarinaModel.renumber(tabs)
        #expect(tabs.map(\.title) == ["Ocarina", "Ocarina 2", "Ocarina 3"])
    }

    /// Closing the second of two takes the numeral off the one that is left —
    /// otherwise a lone tab sits there called "Ocarina 2".
    @Test("The numeral goes when the other tab does")
    func closingRenumbers() {
        let a = tab("a", project: "Ocarina")
        let b = tab("b", project: "Ocarina")
        OcarinaModel.renumber([a, b])
        #expect(b.title == "Ocarina 2")

        OcarinaModel.renumber([a])
        #expect(a.title == "Ocarina")
    }

    @Test("A tab with no project is left alone by the numbering")
    func plainTabsAreUntouched() {
        let shell = tab("Dev Server")
        OcarinaModel.renumber([tab("a", project: "Ocarina"), shell])
        #expect(shell.projectOrdinal == nil)
        #expect(shell.title == "Dev Server")
    }
}

/// Where a new tab opens, which is what decides whether it has a name at all.
@MainActor
@Suite("New tab placement")
struct NewTabPlacementTests {

    private func projectDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-newtab-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The bug this fixes: ⌘T opened in the home directory, home is not a
    /// project, so the tab had no project name and fell back to naming itself
    /// after whatever was running — which looked exactly like project naming
    /// had never shipped.
    @Test("A new tab opens where the current one is, and takes its name")
    func inheritsTheDirectory() throws {
        let directory = try projectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let first = model.newTab(workingDirectory: directory)
        defer { model.closeTab(first.id) }

        // No directory given — the way ⌘T and the sidebar's button call it.
        let second = model.newTab()
        defer { model.closeTab(second.id) }

        #expect(model.session(for: second.id)?.workingDirectory == directory)
        #expect(second.project == first.project)
        #expect(second.project != nil, "a tab in a project must have a project name")
        // And the two are told apart rather than printed twice.
        #expect(first.title != second.title)
    }

    @Test("An explicit directory still wins")
    func explicitDirectoryWins() throws {
        let a = try projectDirectory(), b = try projectDirectory()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }

        let model = OcarinaModel()
        let first = model.newTab(workingDirectory: a)
        defer { model.closeTab(first.id) }
        let second = model.newTab(workingDirectory: b)
        defer { model.closeTab(second.id) }

        #expect(model.session(for: second.id)?.workingDirectory == b)
    }
}
