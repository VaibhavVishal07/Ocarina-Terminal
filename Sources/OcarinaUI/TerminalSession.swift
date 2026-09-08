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
    /// Rewrites colours a program names in full into the theme's own. See
    /// `PaletteFilter`.
    private var palette = PaletteFilter(theme: .fallback, isEnabled: false)

    /// Called the first time anything is typed into this tab.
    ///
    /// The summariser runs the `claude` binary, and a subprocess asks for its
    /// permissions in the app's name. There is no longer a panel to open by
    /// hand, so this is the signal that took its place: somebody is using the
    /// terminal, which is a thing that cannot happen at launch.
    public var onInput: (() -> Void)?

    /// A drag is over this terminal, or has left it.
    public var onDragStateChange: ((Bool) -> Void)?
    /// The program rang. See `TabActivity.needsYou`.
    public var onBell: (() -> Void)?

    /// A command waiting for the shell to be ready for it. See `runWhenReady`.
    private var pendingCommand: String?
    private var settleTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?

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
        terminalView.feed(byteArray: palette.filter(bytes[...])[...])
        noteDrawn()
        // The monitor gets the bytes as they arrived. It reads titles out of
        // them, and it should be reading what the program actually said.
        if let monitor {
            Task { await monitor.ingest(bytes) }
        }
    }

    /// Send input to the shell as if the user typed it.
    public func send(text: String) {
        pty?.write(Array(text.utf8))
    }

    /// Where the shell says it is now, as opposed to where this session was
    /// started.
    ///
    /// Read from the emulator rather than pushed to us. SwiftTerm parses OSC 7
    /// into `hostCurrentDirectory` but its AppKit view never forwards the
    /// delegate call that goes with it, so there is nothing to subscribe to —
    /// and a poll is the right shape anyway: the task poll is already running
    /// every two seconds and this is one property read on the end of it.
    ///
    /// Nil until the shell has drawn a prompt, and for anything that is not a
    /// file URL.
    public var reportedDirectory: URL? {
        guard let reported = terminalView.getTerminal().hostCurrentDirectory,
              let url = URL(string: reported),
              url.isFileURL
        else { return nil }
        return url.standardizedFileURL
    }

    /// Wipes the screen and the scrollback, and asks the shell to redraw.
    ///
    /// Three steps because a terminal's "clear" is three different things. The
    /// escape wipes the grid you can see; `clearScrollback` drops what has
    /// gone off the top, which is the half people actually mean when they say
    /// the window is full of noise; and Ctrl-L asks whatever is in front —
    /// readline at a prompt, or an agent's own drawing — to put itself back on
    /// the empty screen. Without the third the window is left blank until the
    /// next keystroke, which reads as a terminal that has died rather than one
    /// that has been cleared.
    ///
    /// Ctrl-L is the right nudge for both cases: readline redraws the prompt
    /// and keeps a half-typed line, and a full-screen program treats it as the
    /// repaint request it has always been.
    public func clearScreen() {
        terminalView.feed(text: "\u{1b}[H\u{1b}[2J")
        terminalView.getTerminal().clearScrollback()
        send(text: "\u{0C}")
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
        // And it is written down, not only heard. A beep is gone the moment it
        // happens: ring it while the window is behind a browser and nothing on
        // the screen remembers that this tab asked for something. See
        // `TabActivity.needsYou`.
        onBell?()
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
    public func apply(_ theme: Theme, tintingOutput: Bool = false) {
        palette.use(theme)
        palette.isEnabled = tintingOutput
        let terminal = theme.terminal
        terminalView.font = terminal.resolvedFont
        // `text` and `palette`, not `foreground` and `ansi`: body text is
        // white with a tinge of the theme rather than the theme's colour set
        // as words. See `Theme.Terminal.textChroma`.
        terminalView.nativeForegroundColor = terminal.text.nsColor
        terminalView.nativeBackgroundColor = .clear
        terminalView.caretColor = terminal.cursor.nsColor
        terminalView.selectedTextBackgroundColor = terminal.selection.nsColor
        terminalView.installColors(terminal.palette.map(\.swiftTermColor))

        // The theme's caret, defaulting to a bar. SwiftTerm defaults to a
        // filled cell, which is what a terminal has always done — but it sits
        // *over* the character under it, so the thing you are about to edit is
        // the one thing you cannot see. Every text field this user has ever
        // typed into blinks a thin line, and that is the expectation worth
        // matching, so it is the shape a theme gets by saying nothing.
        //
        // A theme that is about terminals rather than about a colour may want
        // the block back, and Matrix does. See `Theme.Shape.Caret`.
        terminalView.getTerminal().setCursorStyle(theme.shape.caret.swiftTermStyle)
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

    /// Types a command and presses Return.
    ///
    /// The counterpart to `type`, which deliberately does not, and the two are
    /// separate methods rather than a flag so that every caller has to say
    /// which one it meant. Quick Actions and the paste inspector put a command
    /// in front of you to read; the first-run board starts the one thing you
    /// just pressed by name, because somebody on their first day has no way to
    /// know that a command sitting at a prompt is waiting for them.
    ///
    /// The command is sent as keystrokes rather than run behind the screen, so
    /// it is echoed at the prompt and its output follows underneath. Whatever
    /// ran is on screen afterwards, which is the part that matters.
    public func run(_ command: String) {
        // Carriage return, not newline: this is what the Return key sends, and
        // the line discipline is what turns it into a newline.
        terminalView.send(txt: command + "\r")
    }

    /// Runs a command once the shell has finished starting.
    ///
    /// A tab created a moment ago has a login shell still coming up: `zsh -l`
    /// sources the user's profile before it prints anything, and a command
    /// sent into that gap is echoed above the prompt, or read by whatever the
    /// profile is doing with stdin, or lost. There is no readiness signal from
    /// a pty, so the shell going quiet after it has drawn something is the
    /// closest thing to one.
    public func runWhenReady(_ command: String) {
        pendingCommand = command
        settleTask?.cancel()
        deadlineTask?.cancel()
        // A shell configured to print no prompt at all would never go quiet
        // *after* drawing, because it never draws. It still gets the command.
        deadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.flushPendingCommand()
        }
    }

    /// The shell has put something on screen. Waits for it to stop.
    private func noteDrawn() {
        guard pendingCommand != nil else { return }
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            // Long enough for a prompt to finish arriving, short enough that
            // the command still reads as having come from the click.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.flushPendingCommand()
        }
    }

    private func flushPendingCommand() {
        guard let command = pendingCommand else { return }
        pendingCommand = nil
        settleTask?.cancel()
        settleTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        run(command)
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
