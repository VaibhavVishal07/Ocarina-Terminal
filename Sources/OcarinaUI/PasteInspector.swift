import Foundation

/// Looks at what is about to be pasted and decides whether to say something.
///
/// Pasting from a web page is not an edge case for this user — it is *the*
/// workflow. They are following instructions they cannot read, and the terminal
/// is the one place where following instructions can delete their work. The
/// answer is not to block it: they are usually right, and a terminal that
/// argues is a terminal they stop using. It is to say, in one line, what the
/// thing does before it runs.
public enum PasteInspector {

    public struct Concern: Sendable, Equatable, Identifiable {
        public var id: String { note }
        /// What to tell them, in their words.
        public let note: String
        /// Whether this is "know what you're doing" or "this can destroy
        /// something". Only the second gets a confirm.
        public let isDestructive: Bool
    }

    public struct Reading: Sendable, Equatable, Identifiable {
        /// The text itself identifies the reading: a second paste of the same
        /// thing is the same question, and a different one replaces the sheet.
        public var id: String { text }
        public let text: String
        public let concerns: [Concern]
        /// More than one command, which is the thing people paste without
        /// noticing: the copy button on a docs page often takes three lines.
        public let lineCount: Int
        /// Whether any of this reads as something a shell would run.
        ///
        /// Dictation is the case that forced this. Wispr Flow inserts what you
        /// said as a paste, and what you say to an agent is paragraphs — so
        /// every dictated sentence with a line break in it was met with "this
        /// is 4 separate commands, not one", over text that is not a command
        /// at all. The sheet is for the moment before you run something you
        /// did not read. Prose is never that moment.
        public let looksLikeCommands: Bool

        public var needsReview: Bool {
            // Anything that can destroy something is said out loud whatever
            // shape it arrived in: the cost of a needless sheet is a click,
            // and the cost of a missed `rm -rf` is the afternoon.
            if isDestructive { return true }
            guard looksLikeCommands else { return false }
            return !concerns.isEmpty || lineCount > 1
        }
        public var isDestructive: Bool { concerns.contains(where: \.isDestructive) }
    }

    /// Patterns worth a word. Deliberately short: a list that fires on
    /// everything trains people to click through it, which is worse than
    /// having no list.
    private static let rules: [(pattern: String, note: String, destructive: Bool)] = [
        ("rm -rf", "Deletes files and folders permanently. There is no Trash and no undo.", true),
        ("rm -fr", "Deletes files and folders permanently. There is no Trash and no undo.", true),
        ("sudo", "Runs as administrator. It can change any file on the Mac, not just yours.", true),
        ("mkfs", "Erases and reformats a disk.", true),
        ("dd if=", "Writes raw data straight to a disk. Getting the target wrong erases it.", true),
        (":(){", "A fork bomb. It will freeze the Mac.", true),
        ("git push --force", "Overwrites the shared history. Other people's work can be lost.", true),
        ("git reset --hard", "Throws away every change you have not committed.", true),
        ("chmod 777", "Makes a file writable by anything on the machine.", false),
        ("curl", "Downloads something from the internet.", false),
        ("wget", "Downloads something from the internet.", false),
        ("| bash", "Runs a downloaded script immediately, without you seeing it first.", false),
        ("| sh", "Runs a downloaded script immediately, without you seeing it first.", false),
        ("eval", "Builds a command out of text and runs it.", false),
    ]

    public static func read(_ text: String) -> Reading {
        let lowered = text.lowercased()
        var seen = Set<String>()
        var concerns: [Concern] = []

        for rule in rules where lowered.contains(rule.pattern) {
            // Two rules can describe the same danger — `rm -rf` and `rm -fr`
            // say the same sentence — and repeating it reads as noise.
            guard seen.insert(rule.note).inserted else { continue }
            concerns.append(Concern(note: rule.note, isDestructive: rule.destructive))
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return Reading(
            text: text,
            // Destructive first: if there is one dangerous thing in here, it is
            // the sentence that has to be read.
            concerns: concerns.sorted { $0.isDestructive && !$1.isDestructive },
            lineCount: lines.count,
            looksLikeCommands: lines.contains { isCommandShaped(String($0)) }
        )
    }

    /// Whether one line reads as a command rather than as something said.
    ///
    /// Two things separate them, and neither needs a dictionary of binaries.
    /// A command opens with a bare lowercase word — `brew`, `git`, `./setup` —
    /// where a sentence opens with a capital, an article, or a bullet. And a
    /// command is short unless it is punctuated with shell syntax; a clause
    /// that runs past a dozen words with no pipe, no flag and no path in it is
    /// somebody talking.
    static func isCommandShaped(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.split(separator: " ").first.map(String.init) else { return false }

        // Shell syntax settles it before anything else is asked, so a `for`
        // loop is not mistaken for a sentence beginning "for".
        if trimmed.contains(where: { Self.shellPunctuation.contains($0) }) { return true }

        if first.hasPrefix("./") || first.hasPrefix("/") || first.hasPrefix("~/") { return true }

        // A sentence can open lowercase — dictation rarely capitalises — so
        // the opening word being bare is not enough on its own. No shell
        // command has ever begun with "the".
        let bare = first.allSatisfy { $0.isLowercase || $0.isNumber || "_-.".contains($0) }
        guard bare,
              first.contains(where: \.isLetter),
              !Self.sentenceOpeners.contains(first.trimmingCharacters(in: .punctuationCharacters))
        else { return false }

        if trimmed.contains(" -") { return true }
        return trimmed.split(separator: " ").count <= Self.conversationalWordCount
    }

    /// Words that open a sentence and never a command. Short enough to be
    /// obvious rather than a grammar: this is here to stop one clipped
    /// dictated clause — "the switch is too bright" — reading as a command
    /// because it happened to be four words long.
    private static let sentenceOpeners: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "there", "then",
        "i", "you", "we", "they", "he", "she", "it", "my", "our", "your",
        "and", "but", "or", "if", "so", "also", "when", "while", "because",
        "is", "are", "was", "were", "be", "been", "do", "does", "did", "done",
        "have", "has", "had", "can", "could", "should", "would", "will",
        "please", "just", "now", "no", "not", "yes", "ok", "okay", "hey",
        "how", "what", "why", "who", "where", "which", "let", "lets", "as",
        "for", "with", "from", "of", "to", "in", "on", "at", "by", "about",
    ]

    /// Syntax with no meaning outside a shell. A line carrying any of it is a
    /// command however long it is.
    private static let shellPunctuation: Set<Character> = ["|", "&", ";", "$", ">", "<", "`", "*"]

    /// Past this many words, a line with no shell syntax in it is a sentence.
    /// Real commands do get long — but they get long on flags and paths, which
    /// the check above has already caught.
    private static let conversationalWordCount = 12

    /// Text with a trailing newline runs the moment it lands. That turns a
    /// paste into an execution the user never confirmed, so the newline is
    /// taken off and they press Return themselves.
    /// Tested against `\r\n` on purpose. Swift treats CRLF as a single
    /// `Character`, so `hasSuffix("\n")` is false for text copied off a web
    /// page with Windows line endings — which is most of it. Asking the
    /// character whether it is a newline covers every form.
    public static func withoutTrailingNewline(_ text: String) -> String {
        var trimmed = text
        while let last = trimmed.last, last.isNewline { trimmed.removeLast() }
        return trimmed
    }
}
