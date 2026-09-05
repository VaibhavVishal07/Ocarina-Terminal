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
    /// The last command exited non-zero.
    case failed(exitCode: Int)

    public var isRunning: Bool { self == .running }

    public var exitCode: Int? {
        if case let .failed(code) = self { return code }
        if case .succeeded = self { return 0 }
        return nil
    }
}
