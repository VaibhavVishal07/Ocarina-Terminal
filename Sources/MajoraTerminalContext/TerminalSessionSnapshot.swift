import Foundation

/// What providers are allowed to look at.
///
/// Deliberately a value type with no reference back into the PTY: naming reads
/// a snapshot, it never reaches into the renderer or the live process tree.
public struct TerminalSessionSnapshot: Sendable, Equatable {
    public var tabID: UUID
    public var shellName: String?
    /// Basename of the foreground process, e.g. `claude`, `ssh`, `python3`.
    public var foregroundProcessName: String?
    /// Full argv of the foreground process, when shell integration supplies it.
    public var foregroundCommandLine: [String]
    public var workingDirectory: URL?
    /// Title the program set via OSC 0/1/2, if any.
    public var escapeSequenceTitle: String?
    /// Busy or idle, and how the last command ended.
    public var activity: TabActivity

    public init(
        tabID: UUID = UUID(),
        shellName: String? = nil,
        foregroundProcessName: String? = nil,
        foregroundCommandLine: [String] = [],
        workingDirectory: URL? = nil,
        escapeSequenceTitle: String? = nil,
        activity: TabActivity = .idle
    ) {
        self.tabID = tabID
        self.shellName = shellName
        self.foregroundProcessName = foregroundProcessName
        self.foregroundCommandLine = foregroundCommandLine
        self.workingDirectory = workingDirectory
        self.escapeSequenceTitle = escapeSequenceTitle
        self.activity = activity
    }

    /// Basename of the working directory, which is the project fallback title.
    public var projectName: String? {
        guard let workingDirectory else { return nil }
        let name = workingDirectory.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
