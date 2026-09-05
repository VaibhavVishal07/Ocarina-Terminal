import Foundation

/// What a transcript source needs in order to find the right session.
///
/// The working directory narrows the search; the process start time settles it.
/// A directory routinely holds many sessions — several of them live at once —
/// so the directory alone cannot say which conversation belongs to this tab.
public struct TranscriptQuery: Sendable, Equatable {
    public var workingDirectory: URL?
    /// When the agent process in this terminal started.
    public var sessionStartedAt: Date?

    public init(workingDirectory: URL?, sessionStartedAt: Date? = nil) {
        self.workingDirectory = workingDirectory
        self.sessionStartedAt = sessionStartedAt
    }
}

/// One session's recent history, newest first.
public struct TranscriptReading: Sendable, Equatable {
    /// Recent human prompts, most recent first. More than one, because the
    /// most recent is often a pronoun-shaped follow-up — "run it", "now the
    /// other one" — that names nothing on its own.
    public var prompts: [String]
    /// Identifies the conversation these came from, so the naming engine can
    /// tell "this session moved on" apart from "a different session won".
    public var sessionID: String

    public init(prompts: [String], sessionID: String) {
        self.prompts = prompts
        self.sessionID = sessionID
    }
}

/// Reads recent human prompts from a coding agent's *local* session metadata.
///
/// This is the privacy boundary. Agents already write their transcripts to
/// disk; naming reads that, and nothing leaves the machine. No provider is
/// permitted to ship terminal contents anywhere to get a title.
public protocol LLMTranscriptSource: Sendable {
    func latestPrompts(for query: TranscriptQuery) async -> TranscriptReading?
}

/// Used by providers whose on-disk format has not been verified yet, so they
/// still detect the process without inventing a task.
public struct UnavailableTranscriptSource: LLMTranscriptSource {
    public init() {}
    public func latestPrompts(for query: TranscriptQuery) async -> TranscriptReading? { nil }
}

/// How many prompts back a source is willing to look for something nameable.
public let transcriptPromptWindow = 8
