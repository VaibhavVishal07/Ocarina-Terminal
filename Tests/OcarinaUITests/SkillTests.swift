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

@MainActor
@Suite("The starting shelf")
struct SkillStarterTests {

    @Test("Every pick on the starting shelf is a real skill")
    func startersResolve() {
        // The two lists are edited by hand and separately: the picks live in
        // Swift, the catalogue in JSON, and a skill renamed upstream takes its
        // id with it. `starting(from:)` drops what it cannot find, so a hole is
        // silent — this is what makes it loud.
        let picks = SkillCatalog.starting(from: SkillCatalog.load())
        #expect(picks.count == SkillCatalog.starters.count,
                "\(SkillCatalog.starters.count - picks.count) starter(s) are not in the catalogue")
    }

    @Test("A starter says what you would want it for, not what the agent reads")
    func startersSpeakPlainly() {
        for pick in SkillCatalog.starting(from: SkillCatalog.load()) {
            // Not the skill's own description, which is addressed to the agent
            // that will follow it. If a pick's line ever becomes that text,
            // the shelf has quietly turned back into the catalogue.
            #expect(pick.plainly != pick.skill.description)
            #expect(pick.plainly != pick.skill.headline)
            // First person, and short enough to read in a glance down a list.
            #expect(pick.plainly.count <= 52, "\(pick.plainly) is a paragraph")
            #expect(pick.plainly.first?.isUppercase == true)
        }
    }

    @Test("Eight, and few enough to read to the end")
    func theShelfIsShort() {
        // The whole point of it. A starting shelf you have to scroll is the
        // two-hundred-row wall again, shorter.
        #expect(SkillCatalog.starters.count <= 10)
        #expect(Set(SkillCatalog.starters.map(\.id)).count == SkillCatalog.starters.count)
    }
}

@MainActor
@Suite("Installing without an agent")
struct SkillShelfTests {

    private func skill(_ name: String) -> Skill {
        Skill(
            id: "test/\(name)", name: name, description: "A test skill.",
            category: .workflow, author: "Nobody", repo: "test/repo",
            path: name, branch: "main", license: "MIT", installs: 0
        )
    }

    @Test("A press with no agent is kept, not dropped")
    func addingWithNoAgentQueues() {
        let shelf = SkillShelf()
        let one = skill("alpha")
        shelf.add(one, into: nil)

        #expect(shelf.queued == [one])
        // And it says so somewhere the browser being closed cannot take away.
        #expect(shelf.notice?.kind == .waiting)
        #expect(shelf.notice?.text.contains("alpha") == true)
        // The strip offers the one press that resolves it.
        #expect(shelf.notice?.action == "Start Claude")
    }

    @Test("Pressing twice is not two installs")
    func askingTwiceIsOneAsk() {
        let shelf = SkillShelf()
        let one = skill("alpha")
        shelf.add(one, into: nil)
        shelf.add(one, into: nil)
        #expect(shelf.queued.count == 1)
    }

    @Test("A queued skill can be taken back")
    func queuedCanBeCancelled() {
        let shelf = SkillShelf()
        let one = skill("alpha")
        shelf.add(one, into: nil)
        shelf.cancel(one)
        #expect(shelf.queued.isEmpty)
        // The strip goes with the last thing it was about. A "waiting for an
        // agent" line with nothing waiting is a lie the app tells itself.
        #expect(shelf.notice == nil)
    }

    @Test("The count includes what is only waiting")
    func waitingCounts() {
        // What the sidebar row is drawn from. Somebody who has asked for three
        // skills on a plain shell has three skills coming, and a row reading
        // nothing at all would say their presses went nowhere.
        let shelf = SkillShelf()
        shelf.add(skill("alpha"), into: nil)
        shelf.add(skill("beta"), into: nil)
        #expect(shelf.total >= 2)
    }

    @Test("Installed means installed where this agent reads, when there is one")
    func installedIsPerAgentWhenItCanBe() throws {
        // A skill in `~/.agents/skills` is not one Claude Code will read, and a
        // row saying "Installed" while Claude is in front of you is a claim
        // about the wrong directory. With no agent there is no such directory,
        // so the honest answer is the global one.
        let shelf = SkillShelf()
        let claude = try #require(SkillHome.forProcess("claude"))
        let codex = try #require(SkillHome.forProcess("codex"))
        let one = skill("gamma")

        #expect(shelf.has(one, in: claude) == false)
        #expect(shelf.has(one, in: nil) == false)
        #expect(claude.directory != codex.directory)
    }
}

@Suite("Design leads")
struct SkillPriorityTests {

    private var catalogue: [Skill] { SkillCatalog.load() }

    @Test("Design is the category the shelf leads with")
    func designLeadsTheCategories() {
        #expect(Skill.Category.ordered.first == .design)
        // And no category is dropped or repeated on the way to putting it
        // first — the pills are built from this list.
        #expect(Set(Skill.Category.ordered) == Set(Skill.Category.allCases))
        #expect(Skill.Category.ordered.count == Skill.Category.allCases.count)
    }

    @Test("An unsearched catalogue opens on design")
    func designLeadsTheCatalogue() {
        let rows = SkillCatalog.filter(catalogue, search: "", category: nil)
        #expect(rows.first?.category == .design, "got \(rows.first?.name ?? "nothing")")
        // Every design skill before every other one, not just the first.
        let lastDesign = rows.lastIndex { $0.category == .design }
        let firstOther = rows.firstIndex { $0.category != .design }
        #expect(lastDesign != nil && firstOther != nil)
        if let lastDesign, let firstOther { #expect(lastDesign < firstOther) }
    }

    @Test("What you typed still outranks the house order")
    func searchBeatsTheHouseOrder() {
        // A shelf that answered "pdf" with a design skill because design leads
        // the house order would be a search box that does not search.
        let hits = SkillCatalog.filter(catalogue, search: "pdf", category: nil)
        #expect(hits.first?.name.lowercased().contains("pdf") == true,
                "got \(hits.first?.name ?? "nothing")")
    }

    @Test("The starting shelf leads with design too")
    func designLeadsTheStarters() {
        // Pinned by id rather than by category, because the catalogue files
        // `frontend-design` under `web` — the registry's `design` category is
        // mostly software design (deep modules, design docs, brainstorming)
        // rather than the visual kind. This is the pick that says what sort of
        // app you have opened, whichever bucket its publisher put it in.
        let picks = SkillCatalog.starting(from: catalogue)
        #expect(picks.first?.skill.id == "anthropics/skills/frontend-design",
                "got \(picks.first?.skill.name ?? "nothing")")
    }
}
