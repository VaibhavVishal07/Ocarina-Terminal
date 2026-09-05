import Foundation

/// Shared behaviour for every terminal-based coding agent.
///
/// The concrete providers below differ only in which binaries they claim and
/// where their session metadata lives — which is the point: adding OpenCode or
/// the next agent is a few lines, not a new code path.
public struct LLMSessionContextProvider: TerminalContextProvider, Sendable {
    public let identifier: String
    /// Shown as secondary information, e.g. `Claude Code · ~/Projects/checkout`.
    public let displayName: String
    public let executableNames: Set<String>
    public let transcripts: any LLMTranscriptSource

    /// A task read from session metadata is the strongest signal available.
    public var transcriptConfidence: Double = 0.85
    /// A title the agent set itself via OSC is weaker but still task-shaped.
    public var escapeSequenceConfidence: Double = 0.55

    public init(
        identifier: String,
        displayName: String,
        executableNames: Set<String>,
        transcripts: any LLMTranscriptSource
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.executableNames = executableNames
        self.transcripts = transcripts
    }

    public func canHandle(_ session: TerminalSessionSnapshot) -> Bool {
        guard let process = session.foregroundProcessName?.lowercased() else { return false }
        return executableNames.contains(process)
    }

    public func observe(_ session: TerminalSessionSnapshot) async -> ContextObservation? {
        if let prompt = await transcripts.latestHumanPrompt(forWorkingDirectory: session.workingDirectory),
           let title = TitleFormatter.title(fromNaturalLanguage: prompt) {
            return ContextObservation(
                title: title,
                activeTask: prompt,
                source: .llmSession,
                confidence: transcriptConfidence,
                processName: displayName,
                projectName: session.projectName,
                workingDirectory: session.workingDirectory
            )
        }

        // Fall back to a title the tool set for itself, if it is not just the
        // tool's own name.
        if let osc = session.escapeSequenceTitle,
           !isGeneric(osc),
           let title = TitleFormatter.title(fromNaturalLanguage: osc) {
            return ContextObservation(
                title: title,
                activeTask: osc,
                source: .llmSession,
                confidence: escapeSequenceConfidence,
                processName: displayName,
                projectName: session.projectName,
                workingDirectory: session.workingDirectory
            )
        }

        // Nothing task-shaped to say. Staying silent leaves the tab on its
        // project name, which beats twenty tabs all reading `Claude`.
        return nil
    }

    public func displayName(forProcess process: String) -> String? {
        executableNames.contains(process.lowercased()) ? displayName : nil
    }

    private func isGeneric(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return true }
        if executableNames.contains(normalized) { return true }
        return normalized == displayName.lowercased()
    }
}

public extension LLMSessionContextProvider {
    /// Claude Code — reads `~/.claude/projects/<slug>/*.jsonl`.
    static func claude(transcripts: (any LLMTranscriptSource)? = nil) -> Self {
        LLMSessionContextProvider(
            identifier: "claude",
            displayName: "Claude Code",
            executableNames: ["claude"],
            transcripts: transcripts ?? ClaudeTranscriptSource()
        )
    }

    /// Codex — reads `~/.codex/sessions/**/rollout-*.jsonl`.
    static func codex(transcripts: (any LLMTranscriptSource)? = nil) -> Self {
        LLMSessionContextProvider(
            identifier: "codex",
            displayName: "Codex",
            executableNames: ["codex"],
            transcripts: transcripts ?? CodexTranscriptSource()
        )
    }

    /// Gemini CLI. Its on-disk session format has not been verified, so this
    /// runs on OSC titles only until someone confirms the layout.
    static func gemini(transcripts: (any LLMTranscriptSource)? = nil) -> Self {
        LLMSessionContextProvider(
            identifier: "gemini",
            displayName: "Gemini CLI",
            executableNames: ["gemini"],
            transcripts: transcripts ?? UnavailableTranscriptSource()
        )
    }

    /// OpenCode. Same caveat as Gemini.
    static func openCode(transcripts: (any LLMTranscriptSource)? = nil) -> Self {
        LLMSessionContextProvider(
            identifier: "opencode",
            displayName: "OpenCode",
            executableNames: ["opencode"],
            transcripts: transcripts ?? UnavailableTranscriptSource()
        )
    }
}
