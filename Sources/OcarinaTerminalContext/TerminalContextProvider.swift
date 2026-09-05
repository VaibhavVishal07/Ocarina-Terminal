import Foundation

/// A source of context about what a terminal is doing.
///
/// Providers are deliberately interchangeable. Nothing above this protocol
/// knows that Claude Code exists.
public protocol TerminalContextProvider: Sendable {
    /// Stable identifier, used for logging and for user-facing toggles.
    var identifier: String { get }

    /// Cheap synchronous check, so the coordinator can skip the async work.
    func canHandle(_ session: TerminalSessionSnapshot) -> Bool

    /// Read whatever this provider can see. Returns nil when it has nothing
    /// meaningful to say — silence is always preferable to a vague title.
    func observe(_ session: TerminalSessionSnapshot) async -> ContextObservation?

    /// Human-readable name for a binary this provider owns, e.g. `claude` ->
    /// `Claude Code`, used for the secondary line. Nil when unknown.
    func displayName(forProcess process: String) -> String?
}

public extension TerminalContextProvider {
    func displayName(forProcess process: String) -> String? { nil }
}
