import Foundation
import Testing
@testable import OcarinaUI

@Suite("Skills")
struct SkillTests {

    private var catalogue: [Skill] { SkillCatalog.load() }

    @Test("The bundled catalogue is there and every row is usable")
    func catalogueLoads() {
        let skills = catalogue
        #expect(skills.count >= 150, "only \(skills.count) skills in the bundle")
        #expect(Set(skills.map(\.id)).count == skills.count, "two skills share an id")

        for skill in skills {
            // The name is also the folder it installs as, so the spec's rules
            // about it are this app's rules about a path in somebody's home.
            #expect(!skill.name.isEmpty)
            #expect(skill.name.count <= 64, "\(skill.id) has an over-long name")
            #expect(!skill.name.contains("/"), "\(skill.id) has a path in its name")
            #expect(!skill.name.hasPrefix("."), "\(skill.id) installs as a dotfile")
            // A row with nothing to say about itself is a row nobody can
            // choose, and the description is what the agent reads too.
            #expect(!skill.description.isEmpty, "\(skill.id) has no description")
            #expect(skill.repo.contains("/"), "\(skill.id) has no owner/repo")
            #expect(!skill.path.isEmpty)
            #expect(SkillInstaller.isSafe(skill.path + "/SKILL.md"), "\(skill.id) has an unsafe path")
        }
    }

    @Test("Every agent in the dock has somewhere to put a skill")
    func everyAgentHasAHome() {
        // Claude Code reads its own directory; the other three read the
        // interoperable one, which is the whole reason a single catalogue can
        // serve all four.
        #expect(SkillHome.forProcess("claude")?.agent == "Claude Code")
        #expect(SkillHome.forProcess("Claude Code")?.agent == "Claude Code")
        #expect(SkillHome.forProcess("codex")?.agent == "Codex")
        #expect(SkillHome.forProcess("Gemini CLI")?.agent == "Gemini CLI")
        #expect(SkillHome.forProcess("opencode")?.agent == "OpenCode")

        #expect(SkillHome.forProcess("claude")?.directory.path.hasSuffix(".claude/skills") == true)
        for agent in ["codex", "gemini", "opencode"] {
            #expect(
                SkillHome.forProcess(agent)?.directory.path.hasSuffix(".agents/skills") == true,
                "\(agent) does not read the interoperable directory"
            )
        }
    }

    @Test("A shell is not an agent, and neither is something that merely looks like one")
    func onlyAgentsGetTheWayIn() {
        for process in ["zsh", "bash", "make", "vim", nil] {
            #expect(SkillHome.forProcess(process) == nil, "\(process ?? "nil") offered a skill home")
        }
        // The one a prefix test would have got wrong. Installing into
        // ~/.claude/skills because a command starts with the same six letters
        // is not a mistake worth being relaxed about.
        #expect(SkillHome.forProcess("claudette") == nil)
        #expect(SkillHome.forProcess("codexify") == nil)
    }

    @Test("A path out of somebody else's repository cannot escape the folder")
    func pathsAreChecked() {
        for bad in ["../outside", "a/../../b", "/etc/passwd", "~/.ssh/id_rsa",
                    "", "a//b", "./hidden", "scripts/../../../x"] {
            #expect(!SkillInstaller.isSafe(bad), "\(bad) was allowed")
        }
        for good in ["SKILL.md", "scripts/run.py", "references/REFERENCE.md", "assets/a/b.png"] {
            #expect(SkillInstaller.isSafe(good), "\(good) was rejected")
        }
    }

    @Test("Searching finds the skill you named before the ones that mention it")
    func searchPutsTheNameFirst() {
        let skills = catalogue
        let hits = SkillCatalog.filter(skills, search: "pdf", category: nil)
        #expect(!hits.isEmpty)
        // Somebody typing "pdf" wants the skill called pdf, not the eleven
        // that mention PDFs in passing.
        #expect(hits[0].name.lowercased().contains("pdf"), "got \(hits[0].name)")

        // A category on its own, and a category with a search on top of it.
        let design = SkillCatalog.filter(skills, search: "", category: .design)
        #expect(!design.isEmpty)
        #expect(design.allSatisfy { $0.category == .design })
        let both = SkillCatalog.filter(skills, search: "figma", category: .design)
        #expect(both.allSatisfy { $0.category == .design })
    }

    @Test("Every category on a chip has something behind it")
    func noEmptyFilters() {
        // A filter that always returns nothing is a filter that reads as
        // broken. If a category empties out, it should leave the enum too.
        let skills = catalogue
        for category in Skill.Category.allCases {
            let rows = SkillCatalog.filter(skills, search: "", category: category)
            #expect(!rows.isEmpty, "\(category.label) has no skills")
        }
    }

    /// Whether the machine running the tests can see GitHub at all.
    private static func gitHubIsReachable() async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.github.com/rate_limit")!)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    @Test("A skill installs, with everything in its folder, and comes back off")
    func installRoundTrip() async throws {
        // The whole path, against GitHub. Skipped without a network rather
        // than failed: a test suite that goes red on a train is a test suite
        // people stop running.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = SkillHome(agent: "Test", directory: root)

        let skill = try #require(
            catalogue.first { $0.repo == "anthropics/skills" && $0.name == "mcp-builder" }
                ?? catalogue.first { $0.repo == "anthropics/skills" }
        )

        // Asked once, up front, so an offline machine skips the test and a
        // broken installer still fails it. Swallowing every error instead made
        // this pass in fifteen milliseconds on a run where nothing happened at
        // all, which is the shape of a test nobody can trust.
        guard await Self.gitHubIsReachable() else { return }

        try await SkillInstaller.install(skill, into: home)

        #expect(home.has(skill))
        // A skill is a folder, not a file: `mcp-builder` brings a `scripts/`
        // directory with it, and an installer that fetched only the manifest
        // would pass every other check here.
        let landed = try FileManager.default.subpathsOfDirectory(
            atPath: home.location(of: skill).path
        )
        #expect(landed.contains("SKILL.md"))
        #expect(landed.count > 1, "only \(landed) arrived")
        #expect(home.installedNames().contains(skill.name))
        let manifest = home.location(of: skill).appendingPathComponent("SKILL.md")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        #expect(text.hasPrefix("---"), "SKILL.md did not arrive with its frontmatter")

        try SkillInstaller.remove(skill, from: home)
        #expect(!home.has(skill))
        #expect(home.installedNames().isEmpty)
    }
}

@MainActor
@Suite("The way in to skills")
struct SkillIngressTests {

    @Test("A tab running an agent offers a skill home; a shell does not")
    func ingressFollowsTheTab() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-ingress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }

        // A fresh tab is a shell until something says otherwise.
        tab.processName = "zsh"
        #expect(model.skillHome == nil)

        // What the coordinator actually puts here is the provider's display
        // name, not the executable — this is the value the row is gated on.
        tab.processName = "Claude Code"
        #expect(model.skillHome?.agent == "Claude Code")
        #expect(model.skillHome?.directory.path.hasSuffix(".claude/skills") == true)

        tab.processName = "Codex"
        #expect(model.skillHome?.agent == "Codex")

        // And a tab that has never been named at all.
        tab.processName = nil
        #expect(model.skillHome == nil)
    }

    @Test("The pty wins over the tab's name for it")
    func groundTruthWins() throws {
        // The row decides which directory in somebody's home gets written to,
        // so it reads what is actually at the front of the terminal. The tab's
        // own name for that process has been through a naming engine that
        // publishes on its own schedule, and is the fallback rather than the
        // answer — a shell that has just had an agent started inside it is
        // exactly the case where the two disagree.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-truth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = OcarinaModel()
        let tab = model.newTab(workingDirectory: directory)
        defer { model.closeTab(tab.id) }

        // The tab still thinks it is a shell; the pty says otherwise.
        tab.processName = "zsh"
        model.noteForegroundForTesting("claude")
        #expect(model.skillHome?.agent == "Claude Code")

        // And the other way: the pty knows the agent has exited.
        model.noteForegroundForTesting("zsh")
        tab.processName = "Claude Code"
        #expect(model.skillHome == nil)
    }
}
