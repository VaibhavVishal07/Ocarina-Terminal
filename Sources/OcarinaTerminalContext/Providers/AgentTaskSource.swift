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

    /// Tasks for one terminal, oldest first.
    ///
    /// `startedAt` is when the agent in that tab started, and it is what makes
    /// this a tab's list rather than a folder's. Without it the panel read
    /// whichever transcript in the directory had been written to last — so two
    /// tabs open on one project showed each other's tasks, and switching
    /// between them showed the first tab's list for as long as it took the
    /// next poll to overwrite it.
    ///
    /// `agentInForeground` says whether this tab is running an agent at all.
    /// A plain shell opened while an agent works in another tab is not doing
    /// any of that agent's work, and listing its task as in progress made a
    /// new terminal look busy the moment it opened.
    public func tasks(
        for directory: URL,
        startedAt: Date? = nil,
        agentInForeground: Bool = true,
        limit: Int = 50
    ) -> [AgentTask] {
        let folder = root.appendingPathComponent(Self.slug(for: directory), isDirectory: true)
        guard let transcript = JSONLReader.session(
            in: folder, startedAt: startedAt, allowingResumed: agentInForeground
        ) else { return [] }
        return Self.tasks(inTranscript: transcript, limit: limit)
    }

    /// The binaries whose transcripts this reads.
    ///
    /// One name, because there is one transcript format here: `claude` writes
    /// the files under `~/.claude/projects` and nothing else does. Codex and
    /// the rest name tabs through their own sources; they do not fill this
    /// panel, so a tab running one of them has no tasks to inherit either.
    public static let agentNames: Set<String> = ["claude"]

    /// Whether the process at the front of a terminal is an agent this can read.
    public static func isAgent(_ process: String?) -> Bool {
        guard let process else { return false }
        return agentNames.contains(process.lowercased())
    }

    /// Cheap fingerprint of the transcript this directory would read.
    ///
    /// The panel polls, and a poll that re-parses an unchanged file is pure
    /// waste — on a large transcript, a fifth of a second of it. Comparing a
    /// path, a size and a modification date costs one `stat`.
    public func signature(
        for directory: URL,
        startedAt: Date? = nil,
        agentInForeground: Bool = true
    ) -> String? {
        let folder = root.appendingPathComponent(Self.slug(for: directory), isDirectory: true)
        guard let transcript = JSONLReader.session(
                  in: folder, startedAt: startedAt, allowingResumed: agentInForeground
              ),
              let values = try? transcript.resourceValues(
                  forKeys: [.fileSizeKey, .contentModificationDateKey]
              )
        else { return nil }
        let size = values.fileSize ?? 0
        let stamp = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(transcript.path):\(size):\(stamp)"
    }

    /// The same slug Claude Code uses for a project folder.
    static func slug(for directory: URL) -> String {
        var slug = ""
        for character in directory.path {
            slug.append(character == "/" || character == "." || character == "_" ? "-" : character)
        }
        return slug
    }

    /// Walks a transcript once, in order.
    ///
    /// A prompt becomes a task; a later `end_turn` closes whichever tasks are
    /// still open. More than one can be open at once, because a prompt typed
    /// while the agent is working is answered inside the turn already running.
    static func tasks(inTranscript url: URL, limit: Int = 50) -> [AgentTask] {
        guard let blob = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }

        var tasks: [AgentTask] = []
        var openIndices: [Int] = []

        /// A prompt, and the task it opens.
        func ask(_ prompt: String, id: String, at askedAt: Date?) {
            tasks.append(
                AgentTask(
                    id: id,
                    title: Self.title(from: prompt),
                    prompt: prompt,
                    askedAt: askedAt ?? Date(),
                    state: .working
                )
            )
            openIndices.append(tasks.count - 1)
        }

        // Only a few kinds of line matter, and a transcript is mostly none of
        // them: the bulk of it is assistant turns carrying tool results, some
        // of them enormous. Decoding and JSON-parsing all of that to find a few
        // dozen prompts cost about half a second on a 32MB file — on the main
        // thread, at the moment the panel opened.
        //
        // A byte search for the markers throws almost every line out before it
        // is ever turned into a String.
        for line in blob.jsonLines() {
            guard line.range(of: Self.typedMarker) != nil
                    || line.range(of: Self.queuedMarker) != nil
                    || line.range(of: Self.absorbedMarker) != nil
                    || line.range(of: Self.endTurnMarker) != nil
            else { continue }
            guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }

            // Subagent traffic is the agent talking to itself, not the user
            // asking for anything.
            if row["isSidechain"] as? Bool == true { continue }

            switch row["type"] as? String {
            case "user":
                // What a human typed, whether it went straight in or waited in
                // the queue for the turn in front of it to end. System and
                // suggestion-accepted prompts are the app talking, and listing
                // them as the user's tasks would be a lie about who asked.
                guard let source = row["promptSource"] as? String,
                      source == "typed" || source == "queued",
                      let prompt = Self.text(from: row["message"]),
                      !prompt.isEmpty
                else { continue }

                ask(prompt, id: row["uuid"] as? String ?? UUID().uuidString,
                    at: Self.date(row["timestamp"]))

            case "attachment":
                // A prompt typed while the agent was working and picked up
                // inside the turn already running. It never becomes a `user`
                // row at all — the queue hands it to the running turn and
                // records it as an attachment on that turn — so a panel
                // reading only `user` rows loses every prompt after the first
                // one in a turn, and a session of eight requests lists one.
                //
                // The other half of the queue is the `queued` source above:
                // whichever way a queued prompt is delivered it is recorded
                // once, in one shape or the other, so neither is double-read.
                guard let attachment = row["attachment"] as? [String: Any],
                      attachment["type"] as? String == "queued_command",
                      // Task notifications come through the same door with no
                      // origin at all. This is the half a person typed.
                      (attachment["origin"] as? [String: Any])?["kind"] as? String == "human",
                      let prompt = (attachment["prompt"] as? String)?.trimmed,
                      !prompt.isEmpty
                else { continue }

                ask(prompt, id: row["uuid"] as? String ?? UUID().uuidString,
                    at: Self.date(attachment["timestamp"]) ?? Self.date(row["timestamp"]))

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

    private static let typedMarker = Data(#""promptSource":"typed""#.utf8)
    private static let queuedMarker = Data(#""promptSource":"queued""#.utf8)
    private static let absorbedMarker = Data(#""type":"queued_command""#.utf8)
    private static let endTurnMarker = Data(#""stop_reason":"end_turn""#.utf8)

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

private extension Data {
    /// The file's lines, as slices, without decoding any of them.
    ///
    /// `String(contentsOf:)` on a 32MB transcript allocates and validates the
    /// whole thing before a single line has been looked at. Splitting on the
    /// newline byte costs nothing and lets the caller decode only what it wants.
    func jsonLines() -> [Data] {
        var lines: [Data] = []
        var start = startIndex
        while let newline = self[start...].firstIndex(of: 0x0A) {
            if newline > start { lines.append(self[start..<newline]) }
            start = index(after: newline)
        }
        if start < endIndex { lines.append(self[start..<endIndex]) }
        return lines
    }
}
