import AppKit
import Foundation
import OcarinaTerminalContext
import SwiftTerm

/// One tab's terminal: the pty, the emulator view, and the naming monitor.
///
/// Ocarina spawns the pty itself rather than letting SwiftTerm do it, so the
/// descriptor stays available to `ProcessInspector`. SwiftTerm is used purely
/// as the VT parser and screen grid.
@MainActor
// SwiftTerm's delegate is not actor-isolated, but it only ever calls back on
// the main thread, which is where this session lives.
public final class TerminalSession: NSObject, @preconcurrency TerminalViewDelegate {
    public let id: UUID
    public let terminalView: TerminalView
    public private(set) var monitor: TerminalSessionMonitor?

    private var pty: PTYProcess?
    private let shellPath: String

    public init(workingDirectory: URL? = nil) {
        id = UUID()
        shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 480))
        super.init()

        terminalView.terminalDelegate = self
        // Let the window's glass show through; the bed behind it in
        // OcarinaWindowView keeps text legible.
        terminalView.nativeBackgroundColor = .clear
        start(workingDirectory: workingDirectory)
    }

    private func start(workingDirectory: URL?) {
        let terminal = terminalView.getTerminal()
        do {
            let process = try PTYProcess(
                executable: shellPath,
                arguments: ["-l"],
                environment: ShellIntegration.environment(forShell: shellPath),
                workingDirectory: workingDirectory,
                columns: terminal.cols,
                rows: terminal.rows
            ) { [weak self] bytes in
                Task { @MainActor [weak self] in
                    self?.receive(bytes)
                }
            }
            pty = process
            monitor = TerminalSessionMonitor(
                tabID: id,
                ptyDescriptor: process.primaryDescriptor,
                shellName: URL(fileURLWithPath: shellPath).lastPathComponent
            )
        } catch {
            terminalView.feed(text: "ocarina: could not start \(shellPath): \(error)\r\n")
        }
    }

    /// Output goes to the screen, and to the monitor so a program that sets its
    /// own title is noticed. The monitor keeps only the title, never the bytes.
    private func receive(_ bytes: [UInt8]) {
        terminalView.feed(byteArray: bytes[...])
        if let monitor {
            Task { await monitor.ingest(bytes) }
        }
    }

    /// Send input to the shell as if the user typed it.
    public func send(text: String) {
        pty?.write(Array(text.utf8))
    }

    public func close() {
        pty?.terminate()
        pty = nil
    }

    // MARK: - TerminalViewDelegate

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        pty?.write(Array(data))
    }

    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        pty?.resize(columns: newCols, rows: newRows)
    }

    public func setTerminalTitle(source: TerminalView, title: String) {
        // Handled by the naming layer via the byte stream, so the same signal
        // works no matter which renderer is in front of the pty.
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    public func scrolled(source: TerminalView, position: Double) {}

    public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    public func bell(source: TerminalView) {
        NSSound.beep()
    }

    public func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    public func clipboardRead(source: TerminalView) -> Data? {
        NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
    }
}
