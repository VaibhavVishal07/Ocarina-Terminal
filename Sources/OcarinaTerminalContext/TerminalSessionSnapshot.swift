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
    /// When the foreground process started. Providers that read a tool's own
    /// session files use it to pick this terminal's session out of several.
    public var foregroundProcessStartTime: Date?
    public var workingDirectory: URL?
    /// Root of the project the working directory sits inside, as
    /// `ProjectLocator` reads it. Resolved by the monitor rather than computed
    /// here: it costs a walk up the tree, and a snapshot is a value that tests
    /// build by hand and pass around freely.
    public var projectRoot: URL?
    /// Title the program set via OSC 0/1/2, if any.
    public var escapeSequenceTitle: String?
    /// Busy or idle, and how the last command ended.
    public var activity: TabActivity

    public init(
        tabID: UUID = UUID(),
        shellName: String? = nil,
        foregroundProcessName: String? = nil,
        foregroundCommandLine: [String] = [],
        foregroundProcessStartTime: Date? = nil,
        workingDirectory: URL? = nil,
        projectRoot: URL? = nil,
        escapeSequenceTitle: String? = nil,
        activity: TabActivity = .idle
    ) {
        self.tabID = tabID
        self.shellName = shellName
        self.foregroundProcessName = foregroundProcessName
        self.foregroundCommandLine = foregroundCommandLine
        self.foregroundProcessStartTime = foregroundProcessStartTime
        self.workingDirectory = workingDirectory
        self.projectRoot = projectRoot
        self.escapeSequenceTitle = escapeSequenceTitle
        self.activity = activity
    }

    /// The project this terminal is working in, which is what names the tab.
    ///
    /// The project root when one was found, and the working directory itself
    /// when none was — so a folder that is not a checkout still reads the way
    /// it always did, and a shell three directories inside a repository now
    /// says the repository instead of whichever subfolder it is standing in.
    public var projectDirectory: URL? {
        projectRoot ?? workingDirectory
    }

    /// Basename of that directory, which is the project fallback title.
    public var projectName: String? {
        guard let directory = projectDirectory else { return nil }
        let name = directory.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
