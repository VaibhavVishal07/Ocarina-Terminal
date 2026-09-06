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

    /// Whether the thing this provider watches is working right now.
    ///
    /// Separate from `observe` on purpose. Naming is about what a tab *is*;
    /// this is about what it is *doing*, and the two have different best
    /// answers. For a shell, output is the signal and the monitor already has
    /// it. For an agent, output is worthless — a coding agent at an idle
    /// prompt redraws its own input box, its status line and its cursor
    /// forever, so "bytes arrived recently" is true for the entire life of the
    /// tab and the dot never stopped saying *working*. The transcript says it
    /// exactly instead.
    ///
    /// Nil means "no opinion", and the monitor's own reading stands.
    func activity(_ session: TerminalSessionSnapshot) async -> TabActivity?
}

public extension TerminalContextProvider {
    func displayName(forProcess process: String) -> String? { nil }
    func activity(_ session: TerminalSessionSnapshot) async -> TabActivity? { nil }
}
