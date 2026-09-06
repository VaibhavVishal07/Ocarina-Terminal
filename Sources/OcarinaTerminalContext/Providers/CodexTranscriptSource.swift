import Foundation

/// Reads `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*.jsonl`.
///
/// The first record is `session_meta` carrying `payload.cwd`, which is how a
/// rollout is matched to a terminal. Prompts appear as
/// `{"type":"event_msg","payload":{"type":"user_message","message":"..."}}`.
public struct CodexTranscriptSource: LLMTranscriptSource {
    let root: URL
    /// Rollouts are per-session, so a handful of recent files covers any tab
    /// the user currently has open.
    let searchLimit: Int

    public init(root: URL? = nil, searchLimit: Int = 12) {
        self.root = root ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        self.searchLimit = searchLimit
    }

    public func latestPrompts(for query: TranscriptQuery) async -> TranscriptReading? {
        guard let directory = query.workingDirectory else { return nil }
        var rollouts = JSONLReader.files(
            in: root,
            recursive: true,
            limit: searchLimit,
            where: { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }
        )

        // Two codex sessions on one project write two rollouts with the same
        // cwd; only the one created alongside this process is this tab's.
        if let startedAt = query.sessionStartedAt {
            let threshold = startedAt.addingTimeInterval(-ClaudeTranscriptSource.launchTolerance)
            let own = rollouts.filter { JSONLReader.creationDate(of: $0) >= threshold }
            if !own.isEmpty {
                rollouts = own.sorted { JSONLReader.creationDate(of: $0) < JSONLReader.creationDate(of: $1) }
            }
        }

        for rollout in rollouts {
            guard matches(directory, rollout: rollout) else { continue }
            let prompts = prompts(in: rollout)
            guard !prompts.isEmpty else { continue }
            return TranscriptReading(
                prompts: prompts,
                sessionID: rollout.deletingPathExtension().lastPathComponent
            )
        }
        return nil
    }

    private func matches(_ directory: URL, rollout: URL) -> Bool {
        guard let head = JSONLReader.firstLine(of: rollout),
              let object = JSONLReader.object(head),
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let cwd = payload["cwd"] as? String
        else { return false }
        return URL(fileURLWithPath: cwd).standardizedFileURL == directory.standardizedFileURL
    }

    /// The prompts that open this conversation, oldest first. See the note on
    /// `ClaudeTranscriptSource.prompts(in:)` for why the head and not the tail.
    private func prompts(in rollout: URL) -> [String] {
        var found: [String] = []
        for line in JSONLReader.headLines(of: rollout) {
            guard let object = JSONLReader.object(line),
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message",
                  let message = payload["message"] as? String
            else { continue }

            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed.hasPrefix("<") { continue }
            found.append(trimmed)
            if found.count == transcriptPromptWindow { break }
        }
        return found
    }
}
