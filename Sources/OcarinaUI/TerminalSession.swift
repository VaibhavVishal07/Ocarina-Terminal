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
    public let terminalView: DroppableTerminalView
    /// Where this tab's shell started. The task panel needs it to find the
    /// right transcript — agents write per project directory, so reading the
    /// home folder's would show another tab's work.
    public let workingDirectory: URL
    public private(set) var monitor: TerminalSessionMonitor?

    private var pty: PTYProcess?
    private let shellPath: String

    /// Called the first time anything is typed into this tab.
    ///
    /// The summariser runs the `claude` binary, and a subprocess asks for its
    /// permissions in the app's name. There is no longer a panel to open by
    /// hand, so this is the signal that took its place: somebody is using the
    /// terminal, which is a thing that cannot happen at launch.
    public var onInput: (() -> Void)?

    /// A drag is over this terminal, or has left it.
    public var onDragStateChange: ((Bool) -> Void)?

    public init(workingDirectory: URL? = nil) {
        id = UUID()
        self.workingDirectory = workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView = DroppableTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 480))
        super.init()

        terminalView.terminalDelegate = self
        // A dropped file arrives as text at the prompt, so it goes through the
        // same door as everything else typed here rather than round the back.
        terminalView.onDropText = { [weak self] text in
            self?.type(text)
            self?.onInput?()
        }
        terminalView.onDragStateChange = { [weak self] isOver in
            self?.onDragStateChange?(isOver)
        }
        // Let the window's glass show through; the bed behind it in
        // OcarinaWindowView keeps text legible.
        terminalView.nativeBackgroundColor = .clear
        start(workingDirectory: workingDirectory)
    }

    /// Falls back to home rather than to the process's own directory. Launched
    /// from Finder an app inherits `/`, so without this every new tab opened at
    /// the root of the disk and was named for it.
    private func start(workingDirectory: URL?) {
        let directory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let terminal = terminalView.getTerminal()
        do {
            let process = try PTYProcess(
                executable: shellPath,
                arguments: ["-l"],
                environment: ShellIntegration.environment(forShell: shellPath),
                workingDirectory: directory,
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
        onInput?()
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

    // MARK: - Theme and text

    /// Restyles the emulator. Applied to every open session when the theme
    /// changes, so switching is live rather than something you relaunch for.
    ///
    /// The background stays clear whatever the theme says: the window is
    /// non-opaque and the bed behind the text is drawn by `OcarinaWindowView`,
    /// so painting it here would lay an opaque slab over the glass.
    public func apply(_ theme: Theme) {
        let terminal = theme.terminal
        terminalView.font = terminal.resolvedFont
        terminalView.nativeForegroundColor = terminal.foreground.nsColor
        terminalView.nativeBackgroundColor = .clear
        terminalView.caretColor = terminal.cursor.nsColor
        terminalView.selectedTextBackgroundColor = terminal.selection.nsColor
        terminalView.installColors(terminal.ansi.map(\.swiftTermColor))

        // A bar, not a block. SwiftTerm defaults to a filled cell, which is
        // what a terminal has always done — but it sits *over* the character
        // under it, so the thing you are about to edit is the one thing you
        // cannot see. Every text field this user has ever typed into blinks a
        // thin line, and that is the expectation worth matching.
        //
        // A program can still ask for another shape through the usual escape
        // sequence; this only sets what a fresh shell starts with.
        terminalView.getTerminal().setCursorStyle(.blinkBar)
    }

    /// Types text at the prompt without running it.
    ///
    /// Quick Actions and the paste inspector both end here, and neither presses
    /// Return. Seeing the command land and pressing Return yourself is the
    /// difference between a button that teaches you something and a button that
    /// does something you could not describe afterwards.
    public func type(_ text: String) {
        terminalView.send(txt: text)
    }

    /// The visible screen, for handing a failure to an agent that can read it.
    /// Blank lines at either end are dropped so the excerpt starts at the
    /// command and ends at the error.
    public func recentOutput(lines: Int = 40) -> String {
        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        guard rows > 0, terminal.cols > 0 else { return "" }
        let text = terminal.getText(
            start: Position(col: 0, row: max(0, rows - lines)),
            end: Position(col: terminal.cols - 1, row: rows - 1)
        )
        let trimmed = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .drop(while: \.isEmpty)
        return trimmed.reversed().drop(while: \.isEmpty).reversed().joined(separator: "\n")
    }

}
