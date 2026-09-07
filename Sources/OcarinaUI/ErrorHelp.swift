import Foundation

/// Turning a failure into a question you can ask.
///
/// A command fails and prints something the person who ran it cannot read. For
/// the user this app is for, that is not an inconvenience — it is where the
/// session ends, because there is nothing they can do next. The app already
/// knows the command failed and what is on the screen, and an agent is usually
/// installed a tab away. This connects the two.
public enum ErrorHelp {

    /// Agents worth asking, and the command that starts each with a question.
    /// Ordered: whichever is installed first is offered.
    private static let agents = ["claude", "gemini", "codex"]

    /// The native Claude installer puts its launcher in `~/.local/bin`, which
    /// is not always on the `PATH` of a process the user did not start from a
    /// shell. Injectable rather than appended unconditionally, so "no agent
    /// anywhere" is a state that can actually be asked for.
    public static func defaultExtraDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin"]
    }

    /// The first agent installed, or nil if the user has none yet.
    ///
    /// Looked up on each press rather than cached: installing an agent is the
    /// single most likely thing to change while the app is open, and a stale
    /// "no agent" answer would send someone back to the drawer they just used.
    public static func installedAgent(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = defaultExtraDirectories()
    ) -> String? {
        located(path: path, extraDirectories: extraDirectories)?.name
    }

    /// The agent's name *and* where it actually is.
    ///
    /// The path matters to anything that runs the agent itself rather than
    /// typing its name at a shell. An app launched from Finder inherits a
    /// minimal `PATH` that does not include `~/.local/bin`, so `env claude`
    /// fails there even though the file is plainly present — which is exactly
    /// how the to-do summariser silently did nothing.
    public static func located(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = defaultExtraDirectories()
    ) -> (name: String, url: URL)? {
        for agent in agents {
            if let url = location(of: agent, path: path, extraDirectories: extraDirectories) {
                return (agent, url)
            }
        }
        return nil
    }

    /// Where one named executable is, searching the same places `located` does.
    ///
    /// Split out because the first-run board asks a different question: not
    /// "is there an agent" but "is *this* one here", once per plate. Both
    /// questions have to be answered by the same search, or the board would
    /// show Claude Code as missing on a machine where the error banner is
    /// happily offering it.
    public static func location(
        of executable: String,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = defaultExtraDirectories()
    ) -> URL? {
        let search = (path ?? "").split(separator: ":").map(String.init) + extraDirectories
        for directory in search {
            let candidate = "\(directory)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Where the excerpt is parked for the agent to read.
    ///
    /// A file, rather than the text inlined into the command: terminal output
    /// has quotes, newlines and escape sequences in it, and pasting that into a
    /// shell command line is how you turn a failed build into a second, worse
    /// problem. One short line goes to the prompt; the mess stays on disk.
    static var excerptURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ocarina", isDirectory: true)
            .appendingPathComponent("last-error.txt")
    }

    /// Writes the excerpt and returns the command to type, or nil if there is
    /// no agent to ask.
    public static func command(explaining output: String, agent: String? = installedAgent()) -> String? {
        guard let agent else { return nil }
        let url = excerptURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard (try? output.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }

        // Asks for the explanation *and* the fix, in that order, and says who
        // is asking. "Explain simply" is not politeness — it is the difference
        // between an answer this user can act on and one that needs its own
        // explanation.
        let question = """
        Read \(url.path) — it is the output of a command that just failed in my \
        terminal. Explain simply what went wrong and exactly what to do next. \
        I am new to the terminal.
        """
        return "\(agent) \(shellQuoted(question))"
    }

    /// Single-quoted for the shell, with embedded quotes escaped the only way
    /// single quotes allow.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
