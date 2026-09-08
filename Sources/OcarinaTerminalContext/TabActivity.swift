import Foundation

/// What a tab is doing right now, as opposed to what it is for.
///
/// Naming answers "what is this terminal about"; activity answers "is it busy,
/// and did the last thing work". They move independently, so activity is
/// carried alongside the title rather than through `TabNamingEngine`.
public enum TabActivity: Sendable, Equatable {
    /// At a prompt, nothing has run yet.
    case idle
    /// A command is in the foreground.
    case running
    /// The last command exited 0.
    case succeeded
    /// The program in this tab rang the bell and you have not looked since.
    ///
    /// The one state here that is not read off the pty's own behaviour. BEL is
    /// a program *asking for you* — it has meant that for fifty years, and the
    /// coding agents ring it when they want a decision — so it is the only
    /// honest way to tell "waiting on you" from "still thinking". A transcript
    /// cannot say it: a permission prompt that has not been answered has not
    /// happened yet, so nothing is written down.
    ///
    /// It outranks running, because an agent that has stopped to ask is not
    /// making progress however busy the screen looks.
    case needsYou
    /// The last command exited non-zero.
    case failed(exitCode: Int)

    public var isRunning: Bool { self == .running }

    public var exitCode: Int? {
        if case let .failed(code) = self { return code }
        if case .succeeded = self { return 0 }
        return nil
    }
}
