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

    /// The other half of the same complaint: a terminal opened *inside* a
    /// repository was named for whichever folder it landed in, so `Sources`
    /// and `Tests` were two tabs that said nothing about the codebase they
    /// were both in.
    @Test("A tab opened inside a repository is named for the repository")
    func namedForTheRepository() throws {
        let repository = try projectDirectory()
        defer { try? FileManager.default.removeItem(at: repository) }
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let inside = repository.appendingPathComponent("Sources/OcarinaUI", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: inside)
        defer { model.closeTab(tab.id) }

        let expected = TitleFormatter.humanize(repository.lastPathComponent)
        #expect(tab.project == expected)
        #expect(tab.title == expected)
    }

    /// Home is a place, not a project. A tab there has no project name to take
    /// and falls back to what it is running — the behaviour project naming was
    /// brought in to replace, kept for the one case it is still right for.
    @Test("A tab in the home directory has no project")
    func homeIsNotAProject() throws {
        let model = OcarinaModel()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tab = model.newTab(workingDirectory: home)
        defer { model.closeTab(tab.id) }
        #expect(tab.project == nil)
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

/// Where a tab's work is looked for.
///
/// Agents write their transcripts per project directory, so the folder a tab
/// reports is what finds its conversation. Reading the *launch* directory meant
/// a tab opened at home and then `cd`-ed into a repository looked for its
/// agent's work in the home folder and found none — an empty task panel for a
/// conversation happening in front of you.
@MainActor
@Suite("A tab's current folder")
struct CurrentDirectoryTests {

    private func directory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-cwd-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Before anything is observed, the launch directory stands")
    func fallsBackToLaunchDirectory() throws {
        let launched = try directory("launched")
        defer { try? FileManager.default.removeItem(at: launched) }
        let session = TerminalSession(workingDirectory: launched)
        defer { session.close() }
        #expect(session.currentDirectory == launched)
    }

    @Test("What the kernel reports wins over where the pty started")
    func observedWins() throws {
        let launched = try directory("launched"), moved = try directory("moved")
        defer {
            try? FileManager.default.removeItem(at: launched)
            try? FileManager.default.removeItem(at: moved)
        }
        let session = TerminalSession(workingDirectory: launched)
        defer { session.close() }
        session.observedDirectory = moved
        #expect(session.currentDirectory == moved)
    }
}
