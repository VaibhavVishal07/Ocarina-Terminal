import Darwin
import Foundation

/// Turns one live pty into `TerminalSessionSnapshot` values.
///
/// This is the only type in the module that touches a file descriptor, and it
/// still does not read terminal contents for naming: `ingest` exists so the
/// renderer can hand over bytes it is already processing, and the parser keeps
/// nothing but the last OSC title.
public actor TerminalSessionMonitor {
    public let tabID: UUID
    private let descriptor: Int32
    private let shellName: String?
    private var parser = OSCParser()
    private var escapeSequenceTitle: String?
    private var isCommandRunning = false
    private var lastExitCode: Int?
    private var lastOutputAt: Date?
    private var hasProducedOutput = false

    /// How long after the last byte a program still counts as working.
    ///
    /// Longer than the naming poll interval on purpose: a shorter window and
    /// a busy tab would read as finished on whichever poll happened to land
    /// between two frames of a spinner.
    public static let outputQuietPeriod: TimeInterval = 2.5

    /// Programs that sit in the foreground waiting for you.
    ///
    /// For anything else, being in the foreground *is* the work: `sleep 30`
    /// and a silent `make` are both busy for as long as they are there. These
    /// are not. An agent, an editor, a pager or a REPL holds the foreground
    /// from launch until it is quit, so presence says nothing about whether
    /// anything is happening — and a tab running Claude reported busy for its
    /// entire life, which is the same as reporting nothing.
    static let interactiveProcesses: Set<String> = [
        "vim", "nvim", "vi", "nano", "emacs", "hx", "helix", "micro",
        "less", "more", "man", "bat", "top", "htop", "btop", "btm", "glances",
        "tmux", "screen", "zellij", "ssh", "mosh", "lazygit", "tig", "k9s",
        "ranger", "nnn", "yazi", "fzf", "python", "python3", "ipython",
        "node", "irb", "ghci", "psql", "mysql", "sqlite3", "redis-cli"
    ]

    /// Agents are matched on a prefix so both the executable and a provider's
    /// display name land: `claude` and `Claude Code`.
    static let interactivePrefixes = ["claude", "codex", "gemini", "opencode", "aider"]

    static func isInteractive(_ processName: String) -> Bool {
        let name = processName.lowercased()
        if interactiveProcesses.contains(name) { return true }
        return interactivePrefixes.contains { name.hasPrefix($0) }
    }

    public init(tabID: UUID = UUID(), ptyDescriptor: Int32, shellName: String? = nil) {
        self.tabID = tabID
        self.descriptor = ptyDescriptor
        self.shellName = shellName
    }

    /// Hand over pty output the renderer has already read.
    public func ingest(_ output: some Sequence<UInt8>) {
        // The renderer calls this with bytes it has just read, so arrival is
        // itself the signal: something in there is drawing.
        lastOutputAt = Date()
        hasProducedOutput = true

        for sequence in parser.consume(output) {
            if let title = sequence.title {
                escapeSequenceTitle = title
            }
            switch sequence.commandBoundary {
            case .started:
                isCommandRunning = true
            case let .finished(exitCode):
                isCommandRunning = false
                lastExitCode = exitCode
            case nil:
                break
            }
        }
    }

    /// Busy, done, or waiting.
    ///
    /// Shell integration is exact where it exists, and a command the shell
    /// spawned is working for as long as it is in the foreground, silent or
    /// not. An interactive program is the exception: it never leaves the
    /// foreground, so presence cannot mean work. What it can mean is output —
    /// these draw while they think and go quiet the moment they are waiting on
    /// you, which is exactly the line the tab's dot needs to draw.
    private func activity(foregroundProcessName: String?, now: Date = Date()) -> TabActivity {
        if isCommandRunning { return .running }

        if let process = foregroundProcessName,
           !GenericProcessContextProvider.shellNames.contains(process.lowercased()) {
            guard Self.isInteractive(process) else { return .running }

            if let lastOutputAt, now.timeIntervalSince(lastOutputAt) < Self.outputQuietPeriod {
                return .running
            }
            // Nothing drawn yet: it is still starting, not finished.
            return hasProducedOutput ? .succeeded : .idle
        }

        guard let lastExitCode else { return .idle }
        return lastExitCode == 0 ? .succeeded : .failed(exitCode: lastExitCode)
    }

    /// Current reading of the terminal.
    public func snapshot() -> TerminalSessionSnapshot {
        guard let group = ProcessInspector.foregroundProcessGroup(ofPTY: descriptor),
              let pid = ProcessInspector.leader(ofGroup: group)
        else {
            return TerminalSessionSnapshot(
                tabID: tabID,
                shellName: shellName,
                escapeSequenceTitle: escapeSequenceTitle,
                activity: activity(foregroundProcessName: nil)
            )
        }

        let arguments = ProcessInspector.arguments(of: pid)
        let executable = ProcessInspector.executablePath(of: pid)
        let name = ProcessInspector.logicalName(
            executablePath: executable,
            arguments: arguments
        )

        return TerminalSessionSnapshot(
            tabID: tabID,
            shellName: shellName,
            foregroundProcessName: name,
            foregroundCommandLine: arguments,
            foregroundProcessStartTime: ProcessInspector.startTime(of: pid),
            workingDirectory: ProcessInspector.workingDirectory(of: pid),
            escapeSequenceTitle: escapeSequenceTitle,
            activity: activity(foregroundProcessName: name)
        )
    }
}
