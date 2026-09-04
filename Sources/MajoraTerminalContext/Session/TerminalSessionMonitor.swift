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
    private var parser = OSCTitleParser()
    private var escapeSequenceTitle: String?

    public init(tabID: UUID = UUID(), ptyDescriptor: Int32, shellName: String? = nil) {
        self.tabID = tabID
        self.descriptor = ptyDescriptor
        self.shellName = shellName
    }

    /// Hand over pty output the renderer has already read.
    public func ingest(_ output: some Sequence<UInt8>) {
        if let latest = parser.consume(output).last {
            escapeSequenceTitle = latest
        }
    }

    /// Current reading of the terminal.
    public func snapshot() -> TerminalSessionSnapshot {
        guard let group = ProcessInspector.foregroundProcessGroup(ofPTY: descriptor),
              let pid = ProcessInspector.leader(ofGroup: group)
        else {
            return TerminalSessionSnapshot(
                tabID: tabID,
                shellName: shellName,
                escapeSequenceTitle: escapeSequenceTitle
            )
        }

        let arguments = ProcessInspector.arguments(of: pid)
        let executable = ProcessInspector.executablePath(of: pid)

        return TerminalSessionSnapshot(
            tabID: tabID,
            shellName: shellName,
            foregroundProcessName: ProcessInspector.logicalName(
                executablePath: executable,
                arguments: arguments
            ),
            foregroundCommandLine: arguments,
            workingDirectory: ProcessInspector.workingDirectory(of: pid),
            escapeSequenceTitle: escapeSequenceTitle
        )
    }
}
