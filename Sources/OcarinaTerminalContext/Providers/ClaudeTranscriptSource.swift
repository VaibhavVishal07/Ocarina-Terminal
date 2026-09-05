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

    public func latestHumanPrompt(forWorkingDirectory directory: URL?) async -> String? {
        guard let directory else { return nil }
        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(Self.slug(for: directory), isDirectory: true)

        let transcripts = JSONLReader.files(
            in: projectDirectory,
            recursive: false,
            limit: 1,
            where: { $0.hasSuffix(".jsonl") }
        )
        guard let transcript = transcripts.first else { return nil }

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
            return trimmed
        }
        return nil
    }
}
