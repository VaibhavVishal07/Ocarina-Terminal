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

    /// A session file appears after its process does, never before it. The
    /// second of slack is for clock granularity, not for a real gap: widening
    /// it lets a neighbouring session that started moments earlier qualify.
    static let launchTolerance: TimeInterval = 1

    /// Which transcript belongs to *this* terminal.
    ///
    /// Picking the most recently written file names a tab after whichever
    /// conversation typed last — which, with two agents open on one project,
    /// is regularly the other tab's, and with none open is a session that
    /// ended hours ago. Binding to the process start time is what makes a tab
    /// show its own work.
    ///
    /// A session writes its file on its first prompt rather than at launch, so
    /// two sessions started close together can still be told apart only by the
    /// order their files appear in. That order is usually the order they
    /// started in; when it is not, the worst case is the old behaviour.
    private func transcript(in directory: URL, startedAt: Date?) -> URL? {
        let files = JSONLReader.files(
            in: directory,
            recursive: false,
            limit: Int.max,
            where: { $0.hasSuffix(".jsonl") }
        )
        guard let startedAt else { return files.first }

        // The session this terminal opened: the first file created once the
        // process existed.
        let threshold = startedAt.addingTimeInterval(-Self.launchTolerance)
        let own = files
            .map { ($0, JSONLReader.creationDate(of: $0)) }
            .filter { $0.1 >= threshold }
            .min { $0.1 < $1.1 }
        if let own { return own.0 }

        // `--continue` and `--resume` reopen a file older than the process, so
        // fall back to the newest one this process can have written.
        return files.first { JSONLReader.modificationDate(of: $0) >= threshold }
    }

    /// Recent human prompts, most recent first.
    private func prompts(in transcript: URL) -> [String] {
        var found: [String] = []
        for line in JSONLReader.tailLines(of: transcript).reversed() {
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
