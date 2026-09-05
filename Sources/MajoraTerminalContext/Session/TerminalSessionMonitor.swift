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

    public init(tabID: UUID = UUID(), ptyDescriptor: Int32, shellName: String? = nil) {
        self.tabID = tabID
        self.descriptor = ptyDescriptor
        self.shellName = shellName
    }

    /// Hand over pty output the renderer has already read.
    public func ingest(_ output: some Sequence<UInt8>) {
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

    /// Busy from either signal: shell integration is exact but optional, and
    /// a non-shell foreground process is a reliable fallback without it.
    private func activity(foregroundProcessName: String?) -> TabActivity {
        let isForeignProcess = foregroundProcessName.map {
            !GenericProcessContextProvider.shellNames.contains($0.lowercased())
        } ?? false

        if isCommandRunning || isForeignProcess { return .running }
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
            workingDirectory: ProcessInspector.workingDirectory(of: pid),
            escapeSequenceTitle: escapeSequenceTitle,
            activity: activity(foregroundProcessName: name)
        )
    }
}
