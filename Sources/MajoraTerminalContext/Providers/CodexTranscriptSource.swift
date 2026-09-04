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

    public func latestHumanPrompt(forWorkingDirectory directory: URL?) async -> String? {
        guard let directory else { return nil }
        let rollouts = JSONLReader.files(
            in: root,
            recursive: true,
            limit: searchLimit,
            where: { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }
        )

        for rollout in rollouts {
            guard matches(directory, rollout: rollout) else { continue }
            if let prompt = latestPrompt(in: rollout) { return prompt }
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

    private func latestPrompt(in rollout: URL) -> String? {
        for line in JSONLReader.tailLines(of: rollout).reversed() {
            guard let object = JSONLReader.object(line),
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message",
                  let message = payload["message"] as? String
            else { continue }

            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed.hasPrefix("<") { continue }
            return trimmed
        }
        return nil
    }
}
