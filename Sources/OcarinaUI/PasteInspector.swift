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

        public var needsReview: Bool { !concerns.isEmpty || lineCount > 1 }
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
            lineCount: lines.count
        )
    }

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
