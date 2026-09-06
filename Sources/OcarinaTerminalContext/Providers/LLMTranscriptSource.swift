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

/// How a session names itself: its opening prompts, oldest first.
public struct TranscriptReading: Sendable, Equatable {
    /// The human prompts that open this conversation, oldest first — the
    /// candidates for its name, best first. More than one, because an opening
    /// line is often throat-clearing — "hey", "look at this" — that names
    /// nothing on its own.
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

    /// Whether the agent is mid-turn, or waiting for the next thing you say.
    ///
    /// Read from the *end* of the transcript, unlike the name, which is read
    /// from the beginning: what a conversation is about was settled by its
    /// first prompt, and what it is doing is settled by its last record.
    ///
    /// Nil when it cannot be told — no transcript, or nothing in it yet.
    func isAwaitingUser(for query: TranscriptQuery) async -> Bool?
}

public extension LLMTranscriptSource {
    func isAwaitingUser(for query: TranscriptQuery) async -> Bool? { nil }
}

/// Used by providers whose on-disk format has not been verified yet, so they
/// still detect the process without inventing a task.
public struct UnavailableTranscriptSource: LLMTranscriptSource {
    public init() {}
    public func latestPrompts(for query: TranscriptQuery) async -> TranscriptReading? { nil }
}

/// How many prompts back a source is willing to look for something nameable.
public let transcriptPromptWindow = 8
