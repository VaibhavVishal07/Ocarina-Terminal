import Foundation

/// One agent on the first-run board.
///
/// The board is what somebody sees on the day they install Ocarina, before
/// there is a single tab open. A terminal with nothing in it is not a starting
/// point for the person this app is for — it is the end of the road — and the
/// question they actually have is "what do I put in here". This is the answer,
/// spelled out as four things you can press.
public struct AgentTool: Identifiable, Sendable, Equatable {
    /// The same id as the `Recipe` in the bundled catalogue, which is where the
    /// install command comes from. One id rather than a command repeated here:
    /// a plate and a recipe that disagree about what "Claude Code" installs is
    /// a bug nobody would find until it ran.
    public let id: String
    /// What to look for on the `PATH`, and what to type to start it.
    public let executable: String
    /// The one word under the icon.
    ///
    /// One word, not the product's full name. Four labels sitting in a row are
    /// read as a set — the eye compares them — and "Claude Code", "Gemini CLI"
    /// and "Codex CLI" compared side by side are mostly the words they have in
    /// common. The distinguishing word is the whole label.
    public let label: String
    /// The full name, for anything that reads the screen aloud.
    public let name: String
    /// The shape it wears. See `AgentMark`.
    public let mark: AgentMark
    /// Who makes it and what it does to your files, in one line.
    ///
    /// Not a pitch. Somebody choosing between three names they have never seen
    /// needs to know which company is behind each one and what it is going to
    /// do — "reads and edits your files" is a fact they can decide on, where
    /// "your AI pair programmer" is not. It is not drawn on the screen, which
    /// stays four icons and four words; it is what a screen reader is told,
    /// and the only place the answer is written down.
    public let blurb: String
}

/// The agents the board offers, and whether each is on this machine.
public enum AgentCatalog {
    /// Three, and then everything else behind the "+".
    ///
    /// Short on purpose. A wall of twelve names is the same problem as the
    /// empty terminal it replaced: no way to tell which one to press. These
    /// three are the ones with a bundled recipe, so every plate on the board
    /// can actually do the thing it offers.
    public static let all: [AgentTool] = [
        AgentTool(
            id: "claude-code",
            executable: "claude",
            label: "Claude",
            name: "Claude Code",
            mark: .burst,
            blurb: "By Anthropic. Reads and edits your files."
        ),
        AgentTool(
            id: "gemini-cli",
            executable: "gemini",
            label: "Gemini",
            name: "Gemini CLI",
            mark: .spark,
            blurb: "By Google. Asks and edits from the shell."
        ),
        AgentTool(
            id: "codex-cli",
            executable: "codex",
            label: "Codex",
            name: "Codex CLI",
            mark: .hexagon,
            blurb: "By OpenAI. Writes and runs code for you."
        ),
    ]

    /// Whether the tool is here.
    ///
    /// Asked when the board appears rather than cached at launch: installing
    /// one of these is the single most likely thing to happen while the app is
    /// open, and the board is the screen you come back to afterwards.
    public static func isInstalled(
        _ tool: AgentTool,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = ErrorHelp.defaultExtraDirectories()
    ) -> Bool {
        ErrorHelp.location(of: tool.executable, path: path, extraDirectories: extraDirectories) != nil
    }

    /// Installed first, then the rest.
    ///
    /// The tool somebody wants to open should be the one their hand goes to
    /// without reading, and on the second launch onwards that is whichever one
    /// they installed. A fixed order would have them hunting past two things
    /// they do not have to reach the one they use every day.
    public static func ordered(byInstalled installed: Set<String>) -> [AgentTool] {
        all.filter { installed.contains($0.id) } + all.filter { !installed.contains($0.id) }
    }

    /// The ids of everything installed, which is what the screen draws from.
    public static func installedIDs(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = ErrorHelp.defaultExtraDirectories()
    ) -> Set<String> {
        Set(all.filter { isInstalled($0, path: path, extraDirectories: extraDirectories) }.map(\.id))
    }
}
