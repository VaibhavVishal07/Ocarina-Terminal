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

    /// What a query found, and why.
    ///
    /// The `why` is not bookkeeping — the row underlines the words that earned
    /// the match, so a search that answered "UI design" with a skill whose
    /// description says *frontend* shows its working instead of looking like a
    /// mistake. See `SkillsView.highlighted`.
    public struct Match: Identifiable, Equatable, Sendable {
        public let skill: Skill
        /// The words actually found in the row's own text, lowercased.
        public let hits: Set<String>
        let score: Int
        public var id: String { skill.id }
    }

    /// Rows matching a search and a category, in the order they should be read.
    ///
    /// Kept as the shape callers already use. Everything interesting is in
    /// `search`.
    public static func filter(
        _ skills: [Skill],
        search text: String,
        category: Skill.Category?
    ) -> [Skill] {
        Self.search(skills, for: text, category: category).map(\.skill)
    }

    /// The catalogue, scored against a typed phrase.
    ///
    /// The filter this replaced asked whether the whole query appeared inside a
    /// name, a description or an author. That is the right question for `pdf`
    /// and the wrong one for every phrase a person actually types: **"UI
    /// design" matched none of the 216 skills**, because that pair of words in
    /// that order is in nobody's description.
    ///
    /// The obvious repair — split on spaces, keep using `contains` — is worse
    /// than the bug. `ui` is inside *build*, *require* and *quick*; `look` is
    /// inside *lookup*; and "make my app look good" came back led by an Azure
    /// resource browser. So three things had to change together:
    ///
    /// **Whole words.** Both sides are cut into words and compared as words, so
    /// *build* stops answering to `ui`. A term of three letters or more may
    /// also match the *start* of a word, which is what makes the list settle
    /// while you are still typing "desig".
    ///
    /// **Weighted by where it was found.** A hit in the name is worth six, in
    /// the category three, in the description two — because somebody typing
    /// `pdf` wants the skill called pdf, not the eleven that mention PDFs in
    /// passing. Exactly equalling the name is worth ten on top.
    ///
    /// **A table of near-words.** `ui` also looks for *interface*, *frontend*,
    /// *component*, *layout*, *css*; `design` for *visual*, *aesthetic*,
    /// *brand*, *typography*. A near-word is always worth less than the word
    /// itself, which is what keeps `api-and-interface-design` behind
    /// `frontend-design` on "UI design" rather than tied with it.
    ///
    /// This is a house call, like `Category.ordered` — thirty-odd lines of
    /// opinion about what people mean. It is not a search engine and it does
    /// not need to be: a phrase whose useful words are all absent is the empty
    /// state's problem, and the empty state has an agent one pane away.
    public static func search(
        _ skills: [Skill],
        for text: String,
        category: Skill.Category? = nil
    ) -> [Match] {
        let pool = category.map { wanted in skills.filter { $0.category == wanted } } ?? skills
        let terms = Self.terms(in: text)

        // Nothing typed: the house order, which puts design at the front. See
        // `Category.ordered`.
        guard !terms.isEmpty else {
            return pool.sorted { a, b in
                if a.category.leads != b.category.leads { return a.category.leads }
                return a.installs > b.installs
            }.map { Match(skill: $0, hits: [], score: 0) }
        }

        return pool.compactMap { skill -> Match? in
            let name = Self.words(skill.name)
            let describe = Self.words(skill.description)
            let kind: Set<String> = [skill.category.rawValue, skill.category.label.lowercased()]
            let by = Self.words(skill.author)

            var score = 0
            var hits: Set<String> = []

            for term in terms {
                // One score per term, at its strongest evidence — a word in
                // both the name and the description is one hit, not two, or a
                // long description would outrank the skill actually called
                // that.
                var best = 0
                if skill.name.lowercased() == term.literal { best = 16 }
                else if name.contains(term.literal) { best = 6 }
                else if Self.begins(name, with: term.literal) { best = 5 }
                else if kind.contains(term.literal) { best = 3 }
                else if describe.contains(term.literal) || by.contains(term.literal) { best = 2 }
                else if Self.begins(describe, with: term.literal) { best = 2 }
                if best > 0 { hits.insert(term.literal) }

                // Near-words, always under the word itself.
                if best < 4, let found = term.kin.first(where: name.contains) {
                    best = max(best, 4); hits.insert(found)
                } else if best < 2, let found = term.kin.first(where: kind.contains) {
                    best = max(best, 2); hits.insert(found)
                } else if best < 1, let found = term.kin.first(where: describe.contains) {
                    best = max(best, 1); hits.insert(found)
                }
                score += best
            }

            guard score > 0 else { return nil }
            return Match(skill: skill, hits: hits, score: score)
        }.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.skill.category.leads != b.skill.category.leads { return a.skill.category.leads }
            return a.skill.installs > b.skill.installs
        }
    }

    /// The phrase, as words worth searching for.
    ///
    /// Everything a sentence carries to be a sentence is dropped. "make my app
    /// look good" is four words of grammar and one of intent, and keeping the
    /// grammar is how the naive version ranked *azure-resource-lookup* first.
    private static func terms(in text: String) -> [Term] {
        var seen: Set<String> = []
        return words(text).sorted().compactMap { word in
            guard word.count > 1, !stopWords.contains(word), seen.insert(word).inserted
            else { return nil }
            return Term(literal: word, kin: Set(nearWords[word] ?? []).subtracting([word]))
        }
    }

    private struct Term { let literal: String; let kin: Set<String> }

    /// Words split on anything that is not a letter or a digit, lowercased.
    /// `front-end` becomes two words, which is why the table below carries
    /// both halves.
    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
    }

    /// Whether any word starts with this, for the letters typed so far. Two
    /// letters is too little — `ui` would prefix-match *unit* and *use*.
    private static func begins(_ pool: Set<String>, with stem: String) -> Bool {
        guard stem.count >= 3 else { return false }
        return pool.contains { $0.hasPrefix(stem) }
    }

    /// Grammar, and the words people wrap a request in. Not a general stop
    /// list: `test`, `write` and `check` are all real queries here.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "my", "me", "i", "im", "it", "its", "is", "are", "am",
        "to", "of", "for", "on", "in", "at", "by", "with", "from", "into",
        "and", "or", "but", "so", "that", "this", "these", "those",
        "do", "does", "did", "can", "could", "would", "should", "will",
        "want", "wants", "need", "needs", "like", "please", "help", "make",
        "makes", "made", "get", "gets", "how", "what", "when", "where", "which",
        "some", "any", "all", "more", "less", "thing", "things", "stuff",
        "something", "anything", "skill", "skills",
    ]

    /// What else a word might have been written as.
    ///
    /// Hand-written, and meant to stay that way — it is thirty opinions about
    /// this catalogue, not a thesaurus. Add to it when a search you expected to
    /// work does not. The rule for adding: only words that would appear in a
    /// skill's own `SKILL.md`, since that is the entire text being searched.
    private static let nearWords: [String: [String]] = [
        // No "design" here, deliberately. A near-word list must never contain
        // a word somebody is likely to have typed *alongside* this one: with
        // it, "UI design" scored the word design twice, and `codebase-design`
        // — which has nothing to do with a screen — tied `frontend-design` and
        // then won the tie on house order.
        "ui": ["interface", "frontend", "front", "end", "component", "layout",
               "css", "visual", "screen"],
        "design": ["visual", "aesthetic", "brand", "typography", "style",
                   "layout", "figma", "mockup", "ux"],
        "ux": ["design", "interface", "usability", "accessibility"],
        "frontend": ["ui", "interface", "css", "react", "component", "web"],
        "css": ["style", "styling", "tailwind", "ui", "frontend", "design"],
        "look": ["design", "visual", "aesthetic", "style"],
        "app": ["application", "frontend", "web", "ui"],
        "web": ["frontend", "http", "browser", "html", "site"],
        "test": ["testing", "tests", "spec", "unit", "coverage", "tdd"],
        "testing": ["test", "tests", "spec", "coverage", "tdd"],
        "bug": ["debug", "debugging", "error", "failure", "fix", "broken"],
        "debug": ["debugging", "bug", "error", "failure", "trace"],
        "fix": ["repair", "debug", "bug", "correct"],
        "review": ["reviewing", "critique", "audit", "feedback", "pr"],
        "pr": ["pull", "request", "review", "diff"],
        "commit": ["git", "message", "changelog", "version"],
        "git": ["commit", "branch", "merge", "diff", "repository"],
        "docs": ["documentation", "readme", "reference", "guide"],
        "documentation": ["docs", "readme", "reference", "guide"],
        "write": ["writing", "draft", "prose", "editing", "author"],
        "writing": ["write", "prose", "draft", "editing", "style"],
        "spreadsheet": ["excel", "xlsx", "csv", "sheet", "tabular"],
        "csv": ["spreadsheet", "tabular", "data", "xlsx"],
        "slides": ["presentation", "pptx", "deck", "powerpoint"],
        "chart": ["graph", "plot", "visualization", "dataviz", "diagram"],
        "database": ["sql", "postgres", "query", "schema", "migration"],
        "sql": ["database", "query", "postgres", "schema"],
        "deploy": ["deployment", "ship", "release", "hosting", "vercel"],
        "cloud": ["aws", "azure", "gcp", "infrastructure", "deploy"],
        "security": ["vulnerability", "audit", "secure", "auth", "secrets"],
        "auth": ["authentication", "login", "oauth", "session", "security"],
        "api": ["endpoint", "rest", "http", "interface", "client"],
        "speed": ["performance", "fast", "optimize", "latency", "profiling"],
        "performance": ["speed", "optimize", "profiling", "latency", "benchmark"],
        "refactor": ["refactoring", "cleanup", "restructure", "architecture"],
        "plan": ["planning", "spec", "design", "roadmap", "brief"],
        "research": ["search", "investigate", "sources", "reading"],
        "pdf": ["document", "documents", "print"],
        "agent": ["agents", "subagent", "orchestration", "workflow"],
    ]
}
