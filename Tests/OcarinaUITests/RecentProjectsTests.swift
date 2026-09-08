import Foundation
import Testing
@testable import OcarinaUI

@Suite("Recent projects")
@MainActor
struct RecentProjectsTests {

    /// A store of its own per test, so one never reads another's file — or the
    /// developer's real list.
    private func store() -> (RecentProjects, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-recents-\(UUID().uuidString).json")
        return (RecentProjects(url: url), url)
    }

    private func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-proj-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Your home is not a project")
    func homeIsNotAProject() {
        // A terminal opens in your home when it has nowhere better to be, so
        // recording it would put the one folder you did not choose at the top
        // of a list of folders you did.
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(!RecentProjects.isProject(home))
        #expect(!RecentProjects.isProject(URL(fileURLWithPath: "/")))
        #expect(RecentProjects.isProject(home.appendingPathComponent("Developer/thing")))
    }

    @Test("The newest visit is first")
    func newestFirst() throws {
        var (recents, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try folder("a"), b = try folder("b")
        defer { [a, b].forEach { try? FileManager.default.removeItem(at: $0) } }

        recents.note(a)
        recents.note(b)
        #expect(recents.recent().map(\.path) == [b.standardizedFileURL.path,
                                                 a.standardizedFileURL.path])
        // Going back to the older one puts it in front again.
        recents.note(a)
        #expect(recents.recent().first?.path == a.standardizedFileURL.path)
    }

    @Test("A plain shell does not erase the agent the folder is known for")
    func aShellDoesNotForgetTheAgent() throws {
        var (recents, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try folder("a")
        defer { try? FileManager.default.removeItem(at: a) }

        recents.note(a, agent: "claude")
        // Walking through the project in zsh is not evidence that you have
        // stopped using Claude there.
        recents.note(a, agent: nil)
        #expect(recents.recent().first?.agent == "claude")
        // Actually running something else is.
        recents.note(a, agent: "codex")
        #expect(recents.recent().first?.agent == "codex")
    }

    @Test("A folder that is gone is not offered")
    func deletedFoldersAreDropped() throws {
        var (recents, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try folder("a"), b = try folder("b")
        defer { try? FileManager.default.removeItem(at: b) }

        recents.note(a)
        recents.note(b)
        try FileManager.default.removeItem(at: a)
        // Dropped on the way out, not on the way in: projects move and come
        // back, and forgetting one the moment it is unmounted loses it.
        #expect(recents.recent().map(\.path) == [b.standardizedFileURL.path])
    }

    @Test("The list survives the app closing")
    func itPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-recents-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try folder("a")
        defer { try? FileManager.default.removeItem(at: a) }

        var first = RecentProjects(url: url)
        first.note(a, agent: "claude")

        let second = RecentProjects(url: url)
        #expect(second.recent().first?.path == a.standardizedFileURL.path)
        #expect(second.recent().first?.agent == "claude")
    }

    @Test("Only five reach the screen")
    func theListIsCapped() throws {
        var (recents, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        var made: [URL] = []
        for i in 0..<8 {
            let f = try folder("p\(i)")
            made.append(f)
            recents.note(f)
        }
        defer { made.forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(recents.recent().count == RecentProjects.shown)
        #expect(recents.recent().first?.path == made.last?.standardizedFileURL.path)
    }

    @Test("A path reads back as a name and a tilde")
    func namesAndPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let project = RecentProject(path: home + "/Developer/ocarina-terminal",
                                    lastOpened: Date(), agent: "claude")
        // Tidied the way a tab's fallback name is, so a project reads the same
        // here as it does in the sidebar.
        #expect(project.name == "Ocarina Terminal")
        #expect(project.shortPath == "~/Developer/ocarina-terminal")
    }
}
