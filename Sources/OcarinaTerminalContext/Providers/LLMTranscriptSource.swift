import Foundation

/// Reads the most recent human prompt from a coding agent's *local* session
/// metadata.
///
/// This is the privacy boundary. Agents already write their transcripts to
/// disk; naming reads that, and nothing leaves the machine. No provider is
/// permitted to ship terminal contents anywhere to get a title.
public protocol LLMTranscriptSource: Sendable {
    func latestHumanPrompt(forWorkingDirectory directory: URL?) async -> String?
}

/// Used by providers whose on-disk format has not been verified yet, so they
/// still detect the process without inventing a task.
public struct UnavailableTranscriptSource: LLMTranscriptSource {
    public init() {}
    public func latestHumanPrompt(forWorkingDirectory directory: URL?) async -> String? { nil }
}
