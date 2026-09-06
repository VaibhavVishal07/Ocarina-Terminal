import Foundation

/// Reads `~/.claude/projects/<slug>/<session>.jsonl`.
///
/// Records look like:
/// `{"type":"user","message":{"role":"user","content":"Fix the checkout page."},
///   "isSidechain":false,"origin":{"kind":"human"},"cwd":"/Users/me/project"}`
///
/// Tool results arrive as `type: "user"` too, but with an array `content` — so
/// a string `content` is what separates a person from the harness.
public struct ClaudeTranscriptSource: LLMTranscriptSource {
    let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    /// `/Users/me/my.project` -> `-Users-me-my-project`
    static func slug(for directory: URL) -> String {
        var slug = ""
        for character in directory.path {
            slug.append(character == "/" || character == "." || character == "_" ? "-" : character)
        }
        return slug
    }

    public func latestPrompts(for query: TranscriptQuery) async -> TranscriptReading? {
        guard let directory = query.workingDirectory else { return nil }
        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(Self.slug(for: directory), isDirectory: true)

        guard let transcript = transcript(
            in: projectDirectory,
            startedAt: query.sessionStartedAt
        ) else { return nil }

        let prompts = prompts(in: transcript)
        guard !prompts.isEmpty else { return nil }
        return TranscriptReading(
            prompts: prompts,
            sessionID: transcript.deletingPathExtension().lastPathComponent
        )
    }

    /// Whether the last thing in the transcript is the agent stopping.
    ///
    /// Walked backwards from the end, taking the first record that is either a
    /// prompt or the end of a turn — whichever comes last is what is happening
    /// now. A small tail is plenty: the answer is always in the last handful
    /// of records, and reading half a megabyte every two seconds to find it
    /// would cost more than the dot is worth.
    public func isAwaitingUser(for query: TranscriptQuery) async -> Bool? {
        guard let directory = query.workingDirectory else { return nil }
        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(Self.slug(for: directory), isDirectory: true)
        guard let transcript = JSONLReader.session(
            in: projectDirectory,
            startedAt: query.sessionStartedAt
        ) else { return nil }

        for line in JSONLReader.tailLines(of: transcript, maxBytes: 64 * 1024).reversed() {
            let endsTurn = line.contains(#""stop_reason":"end_turn""#)
            let isPrompt = line.contains(#""promptSource":"typed""#)
            guard endsTurn || isPrompt else { continue }
            // A prompt after the last end-of-turn means the agent has been
            // asked something and has not finished answering it.
            return endsTurn
        }
        return nil
    }

    /// Kept as the name other code reaches for; the rule itself is shared with
    /// the task panel, so a tab's name and a tab's task list can never end up
    /// reading two different conversations.
    static var launchTolerance: TimeInterval { JSONLReader.launchTolerance }

    private func transcript(in directory: URL, startedAt: Date?) -> URL? {
        JSONLReader.session(in: directory, startedAt: startedAt)
    }

    /// The prompts that open this conversation, oldest first.
    ///
    /// Reading the *end* of the file named the tab after whatever was typed
    /// last, so a tab renamed itself on essentially every command — which is
    /// the opposite of what a name is for. You pick a tab out of a column by
    /// remembering where it is and what it was called, and both of those are
    /// destroyed by a title that keeps moving.
    ///
    /// The opening ask is the one record in a session that cannot change, so
    /// naming from it is what makes a tab hold still for as long as the
    /// conversation lasts. The current task is not lost: it is the subtitle,
    /// the tooltip and the task panel, all of which are free to move.
    private func prompts(in transcript: URL) -> [String] {
        var found: [String] = []
        for line in JSONLReader.headLines(of: transcript) {
            guard let object = JSONLReader.object(line),
                  object["type"] as? String == "user",
                  object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any],
                  // An array payload is a tool result, not something typed.
                  let content = message["content"] as? String
            else { continue }

            if let origin = object["origin"] as? [String: Any],
               let kind = origin["kind"] as? String, kind != "human" { continue }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Slash commands and harness chatter are not tasks.
            if trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed.hasPrefix("<") { continue }
            found.append(trimmed)
            if found.count == transcriptPromptWindow { break }
        }
        return found
    }
}
