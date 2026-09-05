import Foundation

/// One thing the user asked an agent to do.
public struct AgentTask: Sendable, Identifiable, Equatable {
    public let id: String
    /// The prompt, trimmed to something you can read down a narrow column.
    public let title: String
    /// The prompt as typed, for the tooltip.
    public let prompt: String
    public let askedAt: Date
    public let state: State

    public init(id: String, title: String, prompt: String, askedAt: Date, state: State) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.askedAt = askedAt
        self.state = state
    }

    public enum State: Sendable, Equatable {
        /// The agent is still on it.
        case working
        /// The agent stopped. Deliberately not called "done" — see the note on
        /// `AgentTaskSource`.
        case finished
    }
}

/// Reads what has been asked of an agent in a directory, from the transcript
/// the agent writes anyway.
///
/// ## Why prompts and not the agent's own to-do list
///
/// Claude Code has a `TodoWrite` tool, and its calls land in the transcript
/// with real sub-tasks and real statuses. It would be a better source in every
/// way except availability: it is used at the model's discretion, and across
/// the fourteen transcripts this was built against it appears zero times. A
/// panel built on it is blank most of the time, so the spine is what the user
/// typed, which is always there.
///
/// ## Why "finished" and not "done"
///
/// The completion signal is `stop_reason: "end_turn"`, which means the agent
/// stopped talking. It does not mean the work succeeded, or that it did what
/// was meant. A task the agent abandoned looks exactly like one it nailed, so
/// the word has to be one this data can support.
public struct AgentTaskSource: Sendable {
    private let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Tasks for a working directory, oldest first.
    public func tasks(for directory: URL, limit: Int = 50) -> [AgentTask] {
        let folder = root.appendingPathComponent(Self.slug(for: directory), isDirectory: true)
        guard let transcript = newestTranscript(in: folder) else { return [] }
        return Self.tasks(inTranscript: transcript, limit: limit)
    }

    /// The same slug Claude Code uses for a project folder.
    static func slug(for directory: URL) -> String {
        var slug = ""
        for character in directory.path {
            slug.append(character == "/" || character == "." || character == "_" ? "-" : character)
        }
        return slug
    }

    private func newestTranscript(in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return da < db
            }
    }

    /// Walks a transcript once, in order.
    ///
    /// A prompt becomes a task; a later `end_turn` closes whichever tasks are
    /// still open. Only the newest can be open at the end, because a turn has
    /// to finish before the next prompt is answered.
    static func tasks(inTranscript url: URL, limit: Int = 50) -> [AgentTask] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var tasks: [AgentTask] = []
        var openIndices: [Int] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Subagent traffic is the agent talking to itself, not the user
            // asking for anything.
            if row["isSidechain"] as? Bool == true { continue }

            switch row["type"] as? String {
            case "user":
                // Only what a human typed. Queued, system and
                // suggestion-accepted prompts are the app talking, and listing
                // them as the user's tasks would be a lie about who asked.
                guard row["promptSource"] as? String == "typed",
                      let prompt = Self.text(from: row["message"]),
                      !prompt.isEmpty
                else { continue }

                tasks.append(
                    AgentTask(
                        id: row["uuid"] as? String ?? UUID().uuidString,
                        title: Self.title(from: prompt),
                        prompt: prompt,
                        askedAt: Self.date(row["timestamp"]) ?? Date(),
                        state: .working
                    )
                )
                openIndices.append(tasks.count - 1)

            case "assistant":
                guard let message = row["message"] as? [String: Any],
                      message["stop_reason"] as? String == "end_turn"
                else { continue }
                for index in openIndices {
                    let open = tasks[index]
                    tasks[index] = AgentTask(
                        id: open.id,
                        title: open.title,
                        prompt: open.prompt,
                        askedAt: open.askedAt,
                        state: .finished
                    )
                }
                openIndices.removeAll()

            default:
                continue
            }
        }

        return Array(tasks.suffix(limit))
    }

    /// A prompt is either a plain string or content blocks; take the text.
    private static func text(from message: Any?) -> String? {
        guard let message = message as? [String: Any] else { return nil }
        if let plain = message["content"] as? String { return plain.trimmed }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        let joined = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
        return joined.trimmed
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    /// A few words you can scan, not the sentence you typed.
    ///
    /// Two things were tried and both are worse. `TitleFormatter`, which names
    /// tabs, takes the first four words and title-cases them: run over these
    /// prompts it gives "The Switch On The" and "Instead Of What I". Clipping
    /// the raw sentence keeps the meaning but spends the whole line on "The
    /// toggle option should be…" before reaching the point.
    ///
    /// So: drop the throat-clearing at the front, drop the words that carry no
    /// information, and keep the rest in the order they were said. Negations
    /// are never dropped — losing a "not" reverses the task.
    ///
    /// This is a heuristic and reads a little telegraphically. It is meant to
    /// be recognised, not read; the sentence as typed is on hover.
    static func title(from prompt: String, wordLimit: Int = 5, limit: Int = 32) -> String {
        var flat = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        for marker in ["- ", "* ", "\u{2022} "] where flat.hasPrefix(marker) {
            flat = String(flat.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }

        // A prompt that opens with a pasted link is about what follows it.
        while flat.lowercased().hasPrefix("http") {
            guard let space = flat.firstIndex(of: " ") else { break }
            flat = String(flat[flat.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        }

        if let stop = flat.firstIndex(where: { ".?!".contains($0) }) {
            let first = String(flat[..<stop]).trimmingCharacters(in: .whitespaces)
            if first.count >= 12 { flat = first }
        }

        var words = flat.split(separator: " ").map(String.init)

        // Openers that say nothing about the task.
        let openers: Set<String> = ["also", "and", "so", "now", "okay", "ok", "please", "just"]
        while let first = words.first,
              openers.contains(first.lowercased().trimmingCharacters(in: .punctuationCharacters)),
              words.count > 3 {
            words.removeFirst()
        }

        let kept = words.filter { word in
            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return !Self.filler.contains(bare)
        }
        // Only use the stripped version while it still reads as a phrase.
        if kept.count >= 2 { words = kept }

        var title = words.prefix(wordLimit).joined(separator: " ")
        if title.count > limit, let space = title.prefix(limit).lastIndex(of: " ") {
            title = String(title.prefix(limit)[..<space])
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))

        // Sentence case: the first word was mid-sentence once the filler went.
        guard let first = title.first else { return flat }
        return first.uppercased() + title.dropFirst()
    }

    /// Words that carry no information in a four-word summary. Negations are
    /// deliberately absent — dropping "not" turns a bug report into a request
    /// for the bug.
    private static let filler: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "am", "do", "does", "did", "have", "has", "had", "will", "shall",
        "would", "could", "should", "can", "may", "might", "of", "to", "in",
        "on", "at", "for", "with", "that", "this", "these", "those", "there",
        "here", "it", "its", "i", "you", "we", "my", "me", "your", "our",
        "and", "or", "but", "if", "then", "from", "by", "as", "very", "some",
        "sort", "kind", "like", "any", "all", "let", "lets", "us", "want",
        "need", "make", "sure", "also", "too", "more", "much", "so", "up",
    ]

}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
