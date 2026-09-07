import Foundation
import Testing
@testable import OcarinaUI

@Suite("The first-run board")
struct AgentCatalogTests {

    /// A directory with a fake executable in it, for asking the locator a
    /// question with a known answer.
    private func directory(containing executables: [String]) throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-board-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for name in executables {
            let url = base.appendingPathComponent(name)
            try Data().write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return base.path
    }

    @Test("Every plate on the board has a recipe that can install it")
    func platesCanDeliver() {
        // The whole promise of the board is that pressing a plate does the
        // thing it names. A plate whose id has no recipe behind it falls
        // through to opening the drawer instead — which is not wrong, but it
        // is not what the plate said, and nobody would notice until a first
        // run on somebody else's machine.
        let recipes = RecipeCatalog.bundled().flatMap(\.items)
        for tool in AgentCatalog.all {
            let recipe = recipes.first { $0.id == tool.id }
            #expect(recipe != nil, "\(tool.id) is on the board with no recipe to install it")
            #expect(
                recipe?.command.isEmpty == false,
                "\(tool.id) has a recipe with nothing to run"
            )
        }
    }

    @Test("Nothing on the PATH means nothing on the board is lit")
    func nothingInstalled() {
        #expect(AgentCatalog.installedIDs(path: "", extraDirectories: []).isEmpty)
        for tool in AgentCatalog.all {
            #expect(AgentCatalog.isInstalled(tool, path: "", extraDirectories: []) == false)
        }
    }

    @Test("A tool is found wherever it actually is, PATH or not")
    func findsWhatIsThere() throws {
        let onPath = try directory(containing: ["claude"])
        // The native Claude installer puts its launcher somewhere a Finder
        // launch does not have on PATH, so the extra directories have to be
        // searched as thoroughly as PATH itself — that is the case that makes
        // the board say "INSTALL" next to something already installed.
        let offPath = try directory(containing: ["gemini"])

        let ids = AgentCatalog.installedIDs(path: onPath, extraDirectories: [offPath])
        #expect(ids == ["claude-code", "gemini-cli"])
    }

    @Test("A file that is not executable is not an install")
    func ignoresNonExecutables() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-board-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("codex")
        try Data().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        #expect(AgentCatalog.installedIDs(path: base.path, extraDirectories: []).isEmpty)
    }

    @Test("Installed tools come first, and nothing is lost in the sorting")
    func installedLeads() {
        // The tool somebody reaches for without reading is the one they have.
        let ordered = AgentCatalog.ordered(byInstalled: ["codex-cli"])
        #expect(ordered.first?.id == "codex-cli")
        #expect(Set(ordered.map(\.id)) == Set(AgentCatalog.all.map(\.id)))
        #expect(ordered.count == AgentCatalog.all.count)

        // With nothing installed the order is the one the catalogue declares,
        // rather than something the sort invented.
        #expect(AgentCatalog.ordered(byInstalled: []).map(\.id) == AgentCatalog.all.map(\.id))
    }

    @Test("Every tool is telling the row something different")
    func distinct() {
        // Four icons side by side are read by their differences. Two tools
        // wearing the same mark, or the same one-word label, is a row you
        // cannot pick out of — and it is the kind of thing that arrives by
        // copy-paste when a fourth tool is added.
        #expect(Set(AgentCatalog.all.map(\.mark)).count == AgentCatalog.all.count)
        #expect(Set(AgentCatalog.all.map(\.label)).count == AgentCatalog.all.count)
        for tool in AgentCatalog.all {
            #expect(tool.label.isEmpty == false)
            #expect(tool.label.contains(" ") == false, "\(tool.id) needs one word under its icon")
            #expect(tool.blurb.isEmpty == false)
        }
    }

    @Test("Launch holds the landing screen once, and only once")
    func firstLaunchOnly() {
        // The screen is the answer to "I just installed this, now what", so a
        // tab opened over it hides the answer.
        #expect(OcarinaModel.opensTabAtLaunch(isFirstLaunch: true, installed: []) == false)
        // But only that once. Somebody who has decided to use Ocarina as a
        // plain terminal has made a choice, and meeting them with the same
        // pitch every morning is nagging rather than helping.
        #expect(OcarinaModel.opensTabAtLaunch(isFirstLaunch: false, installed: []))
        // And never when there is something installed to run in the tab.
        #expect(OcarinaModel.opensTabAtLaunch(isFirstLaunch: true, installed: ["claude-code"]))
    }
}
