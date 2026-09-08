import Foundation
import OcarinaTerminalContext

/// One skill: a folder of instructions an agent loads when a task calls for it.
///
/// Skills are the same format for every agent in the dock. `SKILL.md` with a
/// name and a description in its frontmatter, and whatever `scripts/`,
/// `references/` and `assets/` the author wanted beside it — that is the whole
/// specification, and Claude Code, Codex, Gemini CLI and OpenCode all read it.
/// What differs between them is only *where on disk they look*, which is what
/// `SkillHome` is for.
public struct Skill: Codable, Identifiable, Sendable, Equatable, Hashable {
    /// `owner/repo/folder`, which is what the registry calls it and what makes
    /// two skills of the same name from different authors different rows.
    public let id: String
    /// The folder it installs as, and the name the agent will know it by.
    public let name: String
    /// What it does and when to use it — the agent reads this to decide
    /// whether to open the skill at all, so it is also the honest blurb for a
    /// person deciding whether to install it.
    public let description: String
    public let category: Category
    /// Who publishes it, in the form a person would recognise: "Anthropic",
    /// not "anthropics".
    public let author: String
    /// `owner/repo` on GitHub. Shown on every row, and not decoration: a skill
    /// is instructions an agent will follow, so who wrote it is the single
    /// most important thing on the card.
    public let repo: String
    /// The folder inside that repo holding `SKILL.md`.
    public let path: String
    public let branch: String
    public let license: String
    /// How many times the registry has seen it installed. Used only to order
    /// the list — a popular skill is not a good one, but with two hundred of
    /// them something has to decide what you see first.
    public let installs: Int

    /// The one line a card carries.
    ///
    /// Descriptions in this format are written for the agent, and the agent
    /// reads all of it — they open with what the skill does and then spend a
    /// sentence or three on when to reach for it and which words should
    /// trigger it. On a card the first sentence is the whole of what a person
    /// choosing needs, and the rest arrived as a line clipped mid-word, on
    /// every card, which is the sort of thing that makes a page look broken
    /// rather than full.
    ///
    /// The full text is still on the card's tool tip, where the "use this
    /// when" half is worth having.
    public var headline: String {
        var line = description
        // The first sentence, when there is more than one and it is long
        // enough to stand alone. `.` also ends abbreviations, so a very short
        // first piece is taken as one of those rather than as a sentence.
        if let stop = line.firstIndex(where: { ".!?".contains($0) }) {
            let first = String(line[line.startIndex..<stop])
            if first.count >= 24 { line = first }
        }
        line = line.trimmingCharacters(in: .whitespaces)
        guard line.count > Self.headlineLimit else { return line }
        // Cut at a word, not a letter.
        let clipped = line.prefix(Self.headlineLimit)
        let cut = clipped.lastIndex(of: " ").map { String(clipped[clipped.startIndex..<$0]) }
        return (cut ?? String(clipped)) + "…"
    }

    /// About what fits on one line of a card at this width.
    ///
    /// Deliberately short of what the label can hold. Whichever of the two
    /// cuts the line, the ellipsis should be this one — it lands on a word,
    /// where the label's lands wherever the pixels ran out.
    static let headlineLimit = 48

    public var web: URL? {
        URL(string: "https://github.com/\(repo)/tree/\(branch)/\(path)")
    }

    public enum Category: String, Codable, Sendable, CaseIterable, Hashable {
        case workflow, testing, cloud, data, web, security, writing, design, documents

        /// The mark on a card, so the grid can be scanned by kind before a
        /// word of it has been read.
        ///
        /// One shape each, and the simplest one that means the thing: a card
        /// this size gives the glyph fourteen points, and at fourteen points a
        /// detailed symbol is a smudge.
        public var symbol: String {
            switch self {
            case .workflow: "arrow.right"
            case .testing: "checkmark"
            case .cloud: "cloud"
            case .data: "cylinder"
            case .web: "globe"
            case .security: "lock"
            case .writing: "pencil"
            case .design: "circle.lefthalf.filled"
            case .documents: "doc"
            }
        }

        /// The order the filter pills are offered in, and the order a
        /// catalogue with nothing else to sort by comes out in.
        ///
        /// **Design first.** This is a house call rather than a fact about the
        /// catalogue: the app is opinionated about how things look, the people
        /// who choose it are choosing it for that, and the row a shelf leads
        /// with is the row that gets installed. The rest keep the order they
        /// are declared in, which runs roughly from what everybody needs to
        /// what only some do.
        public static let ordered: [Category] = [.design] + allCases.filter { $0 != .design }

        /// Whether this is the category the shelf leads with.
        var leads: Bool { self == .design }

        /// The word on the filter pill.
        public var label: String {
            switch self {
            case .workflow: "Workflow"
            case .testing: "Testing"
            case .cloud: "Cloud"
            case .data: "Data"
            case .web: "Web"
            case .security: "Security"
            case .writing: "Writing"
            case .design: "Design"
            case .documents: "Documents"
            }
        }
    }
}

/// Where an agent looks for skills.
///
/// One format, four directories. `~/.agents/skills` is the interoperable one —
/// Codex reads only that, and Gemini CLI and OpenCode read it in preference to
/// their own — so three of the four land there and share what they install.
/// Claude Code reads `~/.claude/skills` and does not read `.agents`, so it gets
/// its own, and installing the same skill for both writes it twice rather than
/// linking: a symlink into another tool's directory is a thing somebody has to
/// discover the hard way when they uninstall one of them.
public struct SkillHome: Sendable, Equatable {
    /// The agent this is the home for, as the dock names it.
    public let agent: String
    public let directory: URL

    public static func directory(named path: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(path, isDirectory: true)
    }

    /// The home for whatever is in front of a terminal, or nil if what is in
    /// front of it is not an agent.
    ///
    /// Matched on the foreground process rather than on the tab's generated
    /// name, because the name is a guess about a conversation and this decides
    /// which directory in somebody's home gets written to.
    ///
    /// What arrives here is either an executable — `claude` — or the display
    /// name a provider gave it — `Claude Code` — so the first word is what is
    /// compared, whole. A prefix test would have matched `claudette`, and
    /// installing into `~/.claude/skills` because a command happened to start
    /// with the same six letters is not a mistake worth being relaxed about.
    public static func forProcess(_ process: String?) -> SkillHome? {
        guard let first = process?.lowercased()
            .split(whereSeparator: \.isWhitespace).first.map(String.init)
        else { return nil }
        for (executable, agent, path) in table where executable == first {
            return SkillHome(agent: agent, directory: directory(named: path))
        }
        return nil
    }

    /// The executable, the name to show, and where that agent reads skills.
    private static let table: [(String, String, String)] = [
        ("claude", "Claude Code", ".claude/skills"),
        ("codex", "Codex", ".agents/skills"),
        ("gemini", "Gemini CLI", ".agents/skills"),
        ("opencode", "OpenCode", ".agents/skills"),
    ]

    /// Every home, for the tests and for anything that has to say what the
    /// four of them are.
    public static var all: [SkillHome] {
        table.map { SkillHome(agent: $0.1, directory: directory(named: $0.2)) }
    }

    public func location(of skill: Skill) -> URL {
        directory.appendingPathComponent(skill.name, isDirectory: true)
    }

    /// Whether the skill is already on disk here. The presence of `SKILL.md`,
    /// not of the folder: an install that died half way leaves a folder.
    public func has(_ skill: Skill) -> Bool {
        FileManager.default.fileExists(
            atPath: location(of: skill).appendingPathComponent("SKILL.md").path
        )
    }

    /// What is installed here, whether or not this app put it there.
    public func installedNames() -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return Set(contents.filter { url in
            FileManager.default.fileExists(
                atPath: url.appendingPathComponent("SKILL.md").path
            )
        }.map(\.lastPathComponent))
    }
}

/// The bundled list.
///
/// Bundled rather than fetched. A registry query is one more thing between
/// somebody and a working agent, it is a third party's uptime, and the only
/// public endpoint returns names and install counts with no descriptions at
/// all — a browser built on it would be a list of two hundred words. This ships
/// what was read out of each skill's own `SKILL.md`, so every row says what the
/// skill says about itself, and the modal opens instantly and offline.
///
/// The cost is that it goes out of date, which is why every row links to the
/// repository it came from.
public enum SkillCatalog {
    public static func load() -> [Skill] {
        guard let url = PackagedResources.bundle.url(
            forResource: "skills", withExtension: "json", subdirectory: "Skills"
        ), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Skill].self, from: data)) ?? []
    }

    /// The handful somebody who has never installed one should see first.
    ///
    /// Two hundred and sixteen rows is not a shelf, it is a search box with a
    /// list attached, and it only works if you already know what you are
    /// looking for. Somebody who has just found out that skills exist does not
    /// — so the browser opens on eight of them and the other two hundred are
    /// one press away.
    ///
    /// Eight and not twenty. The point of a starting shelf is that it can be
    /// read to the end; a shelf you have to scroll is the wall again, shorter.
    ///
    /// They are chosen to be useful before you have decided what you are
    /// building — checking, debugging, looking things up, handling the file
    /// formats everyone has — rather than to be the eight most installed,
    /// which is how you end up recommending Prisma to somebody who has not
    /// got a database.
    ///
    /// The line is written here rather than taken from the skill. A skill's
    /// own description is written *for the agent* — "Use when encountering any
    /// bug, test failure, or unexpected behavior, before proposing fixes" is
    /// addressed to the reader that will follow it, and it is the right text
    /// for that reader. It is not an answer to "what would I want this for",
    /// which is the only question somebody on this screen is asking. So each
    /// pick carries one line in the first person, and the skill's own name and
    /// author sit under it, because who wrote the instructions your agent will
    /// follow is still most of the decision.
    public static let starters: [(id: String, plainly: String)] = [
        // First, for the same reason design leads the categories: this is the
        // pick that says what kind of app you have opened.
        ("anthropics/skills/frontend-design",
         "Make a web page that looks designed"),
        ("mattpocock/skills/code-review",
         "Check my code before I commit it"),
        ("obra/superpowers/systematic-debugging",
         "Work out why something is broken"),
        ("mattpocock/skills/research",
         "Look something up and write down what it found"),
        ("anthropics/skills/pdf",
         "Read and write PDFs"),
        ("anthropics/skills/docx",
         "Read and write Word documents"),
        ("mattpocock/skills/git-guardrails-claude-code",
         "Stop me running a git command I cannot undo"),
        ("obra/superpowers/test-driven-development",
         "Write the test before the code"),
    ]

    /// The starters, resolved against the catalogue, in the order above.
    ///
    /// An id that is not in the catalogue is dropped rather than drawn as a
    /// blank: the two lists are edited by hand and separately, and a shelf
    /// with a hole in it is a worse failure than a shelf of seven.
    public static func starting(from skills: [Skill]) -> [(skill: Skill, plainly: String)] {
        let byID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        return starters.compactMap { pick in
            byID[pick.id].map { (skill: $0, plainly: pick.plainly) }
        }
    }

    /// Rows matching a search and a category, in the order they should be read.
    ///
    /// Name before description: somebody typing "pdf" wants the skill called
    /// pdf at the top, not the eleven that mention PDFs in passing.
    public static func filter(
        _ skills: [Skill],
        search: String,
        category: Skill.Category?
    ) -> [Skill] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = category.map { wanted in skills.filter { $0.category == wanted } } ?? skills

        // Nothing typed: the house order, which puts design at the front. See
        // `Category.ordered`.
        guard !needle.isEmpty else {
            return pool.sorted { a, b in
                if a.category.leads != b.category.leads { return a.category.leads }
                return a.installs > b.installs
            }
        }

        return pool.filter {
            $0.name.lowercased().contains(needle)
                || $0.description.lowercased().contains(needle)
                || $0.author.lowercased().contains(needle)
        }.sorted { a, b in
            // What you typed wins over everything. A shelf that answered
            // "pdf" with a design skill because design leads the house order
            // would be a search box that does not search.
            let (first, second) = (a.name.lowercased().contains(needle),
                                   b.name.lowercased().contains(needle))
            if first != second { return first }
            if a.category.leads != b.category.leads { return a.category.leads }
            return a.installs > b.installs
        }
    }
}
