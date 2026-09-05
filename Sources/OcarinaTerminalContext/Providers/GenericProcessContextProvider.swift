import Foundation

/// The fallback: name the tab after whatever command is in the foreground.
///
/// Shells and known agents are skipped. A shell is not an activity, and an
/// agent's binary name is exactly the title this feature exists to avoid — in
/// both cases the tab keeps its project-name fallback instead.
public struct GenericProcessContextProvider: TerminalContextProvider, Sendable {
    public let identifier = "generic-process"

    public static let shellNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "login"
    ]

    /// Commands whose argv we understand well enough to name confidently.
    static let recognizedExecutables: Set<String> = [
        "ssh", "mosh", "npm", "pnpm", "yarn", "bun", "deno", "python", "python3",
        "node", "ruby", "perl", "make", "just", "task", "git", "docker",
        "podman", "cargo", "swift", "go", "kubectl", "k9s", "tsx", "ts-node"
    ]

    public var agentExecutables: Set<String>
    public var recognizedConfidence: Double = 0.65
    public var unrecognizedConfidence: Double = 0.45

    public init(agentExecutables: Set<String> = ["claude", "codex", "gemini", "opencode", "aider"]) {
        self.agentExecutables = agentExecutables
    }

    public func canHandle(_ session: TerminalSessionSnapshot) -> Bool {
        guard let process = session.foregroundProcessName?.lowercased() else { return false }
        return !Self.shellNames.contains(process) && !agentExecutables.contains(process)
    }

    public func observe(_ session: TerminalSessionSnapshot) async -> ContextObservation? {
        let argv = session.foregroundCommandLine.isEmpty
            ? [session.foregroundProcessName].compactMap { $0 }
            : session.foregroundCommandLine
        guard !argv.isEmpty, let title = TitleFormatter.title(fromCommand: argv) else { return nil }

        let executable = TitleFormatter.basename(argv[0]).lowercased()
        let confidence = Self.recognizedExecutables.contains(executable)
            ? recognizedConfidence
            : unrecognizedConfidence

        return ContextObservation(
            title: title,
            activeTask: argv.joined(separator: " "),
            source: .foregroundCommand,
            confidence: confidence,
            processName: session.foregroundProcessName,
            projectName: session.projectName,
            workingDirectory: session.workingDirectory
        )
    }
}
