import Foundation
import Testing
@testable import OcarinaTerminalContext

/// Which project a terminal is in.
///
/// The tab is named after this, and it used to be read as "the folder the shell
/// is standing in" — which is the project only at the very top of a checkout.
@Suite("Project locator")
struct ProjectLocatorTests {

    /// A throwaway home directory, so the walk's stopping point is under the
    /// test's control rather than the machine's.
    private struct Sandbox {
        let home: URL

        init() throws {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("ocarina-project-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        @discardableResult
        func directory(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @discardableResult
        func file(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: url)
            return url
        }

        func root(of path: String) throws -> URL? {
            ProjectLocator.root(of: try directory(path), home: home)
        }

        func name(of path: String) throws -> String? {
            ProjectLocator.projectName(for: try directory(path), home: home)
        }

        func tearDown() { try? FileManager.default.removeItem(at: home) }
    }

    /// The bug: a terminal deep inside a repository was named for the folder it
    /// was standing in, so the codebase — the one thing you always know about a
    /// terminal — was the one thing the tab would not say.
    @Test("A directory inside a repository belongs to the repository")
    func walksUpToTheRepository() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.directory("checkout/.git")
        let root = try sandbox.root(of: "checkout/Sources/Feature")
        #expect(root?.lastPathComponent == "checkout")
    }

    @Test("The repository names the tab, humanized")
    func namesTheRepository() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.directory("ocarina-terminal/.git")
        #expect(try sandbox.name(of: "ocarina-terminal/Sources/OcarinaUI") == "Ocarina Terminal")
    }

    /// A submodule and a linked worktree both carry `.git` as a *file*.
    @Test("A .git file counts as much as a .git directory")
    func gitFileCounts() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("worktree/.git")
        #expect(try sandbox.root(of: "worktree/src")?.lastPathComponent == "worktree")
    }

    /// The nearest one, not the outermost: a repository checked out inside
    /// another is its own codebase and its own tab name.
    @Test("A nested repository is its own project")
    func nearestRepositoryWins() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.directory("outer/.git")
        try sandbox.directory("outer/vendor/inner/.git")
        #expect(try sandbox.root(of: "outer/vendor/inner/lib")?.lastPathComponent == "inner")
    }

    /// A manifest inside a repository must not outrank the repository: the
    /// walk settles version control over the whole path before it looks at
    /// manifests at all.
    @Test("A package inside a repository still says the repository")
    func versionControlBeatsAManifestFurtherDown() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.directory("monorepo/.git")
        try sandbox.file("monorepo/apps/web/package.json")
        #expect(try sandbox.root(of: "monorepo/apps/web/src")?.lastPathComponent == "monorepo")
    }

    @Test("A manifest marks the root where nothing is under version control")
    func manifestMarksTheRoot() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("scratch/Cargo.toml")
        #expect(try sandbox.root(of: "scratch/src/bin")?.lastPathComponent == "scratch")
    }

    @Test("An Xcode project marks the root")
    func xcodeProjectMarksTheRoot() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        try sandbox.directory("Player/Player.xcodeproj")
        #expect(try sandbox.root(of: "Player/Player/Views")?.lastPathComponent == "Player")
    }

    /// The old behaviour, kept: a folder that marks nothing is still the
    /// project, because a directory of scratch files is what you would call it.
    @Test("A plain folder is its own project")
    func plainFolderStandsAlone() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        #expect(try sandbox.root(of: "notes")?.lastPathComponent == "notes")
    }

    /// Home and the root of the disk are places, not projects. A tab in one has
    /// no project name to take, and falls back to what it is running.
    @Test("The home directory is not a project")
    func homeIsNotAProject() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        #expect(ProjectLocator.root(of: sandbox.home, home: sandbox.home) == nil)
        #expect(ProjectLocator.projectName(for: sandbox.home, home: sandbox.home) == nil)
    }

    @Test("The root of the disk is not a project")
    func diskRootIsNotAProject() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        #expect(ProjectLocator.root(of: URL(fileURLWithPath: "/"), home: sandbox.home) == nil)
    }

    /// The walk stops at home rather than climbing into `/Users` and out to the
    /// disk — a repository above your home directory is not your project.
    @Test("The walk stops at home")
    func stopsAtHome() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        // A marker on home itself is the one case where the walk could return
        // home, and it must still refuse.
        try sandbox.directory(".git")
        #expect(try sandbox.root(of: "notes")?.lastPathComponent == "notes")
    }
}
