import Foundation

/// Runs the provider chain for a tab and folds the result into its context.
///
/// Owns naming state only. It never touches the PTY or the renderer; the UI
/// observes `context(for:)` and draws whatever `displayTitle` says.
public actor TabContextCoordinator {
    private let providers: [any TerminalContextProvider]
    private let engine: TabNamingEngine
    private var contexts: [UUID: TabContext] = [:]

    public init(
        providers: [any TerminalContextProvider],
        engine: TabNamingEngine = TabNamingEngine()
    ) {
        self.providers = providers
        self.engine = engine
    }

    public func context(for tabID: UUID) -> TabContext? {
        contexts[tabID]
    }

    public func register(_ context: TabContext) {
        contexts[context.tabID] = context
    }

    /// A tab can be renamed before it has ever been polled, so the context is
    /// created on demand rather than the rename being dropped.
    public func setManualTitle(_ title: String?, for tabID: UUID) {
        var context = contexts[tabID] ?? TabContext(tabID: tabID)
        context.applyManualTitle(title)
        contexts[tabID] = context
    }

    public func resumeAutomaticNaming(for tabID: UUID) {
        var context = contexts[tabID] ?? TabContext(tabID: tabID)
        context.resumeAutomaticNaming()
        contexts[tabID] = context
    }

    /// Poll the providers for one tab. Highest-priority observation wins the
    /// round; `TabNamingEngine` then decides if it beats what is on screen.
    @discardableResult
    public func refresh(
        _ session: TerminalSessionSnapshot,
        at now: Date = Date()
    ) async -> TabContext {
        var context = contexts[session.tabID] ?? TabContext(
            tabID: session.tabID,
            fallbackTitle: session.projectName ?? session.shellName ?? "Terminal",
            workingDirectory: session.workingDirectory,
            projectRoot: session.projectRoot
        )

        var best: ContextObservation?
        for provider in providers where provider.canHandle(session) {
            guard let observation = await provider.observe(session) else { continue }
            if let current = best {
                let outranks = observation.source > current.source
                let tiebreak = observation.source == current.source
                    && observation.confidence > current.confidence
                if outranks || tiebreak { best = observation }
            } else {
                best = observation
            }
        }

        if let best {
            engine.apply(best, to: &context, at: now)
        }

        // Secondary information tracks the live process even when no provider
        // had anything worth renaming the tab for.
        //
        // A provider that can see what the tab is *doing* overrules the
        // monitor, which only sees bytes. For an agent that is the difference
        // between a dot that goes green when the work stops and one that
        // blinks for the life of the session.
        context.activity = await activity(for: session) ?? session.activity
        context.processName = displayName(for: session)
        context.workingDirectory = session.workingDirectory ?? context.workingDirectory
        context.projectName = session.projectName ?? context.projectName
        // Straight from the snapshot and never merged from an observation: a
        // provider names what a tab is *doing*, and moving between projects is
        // a fact about the pty that no provider is a better witness to.
        //
        // Nil is load-bearing here in a way it is not on the lines above: a
        // `cd` out of a checkout and into the home directory must take the
        // project name off the tab rather than leave the last one on it. Which
        // is why it is gated on the directory — a snapshot that could not read
        // the pty at all reports nil for both, and *that* nil means "no
        // reading", not "no project".
        if session.workingDirectory != nil {
            context.projectRoot = session.projectRoot
        }
        if let fallback = session.projectName ?? session.shellName {
            context.fallbackTitle = TitleFormatter.humanize(fallback) ?? fallback
        }

        contexts[session.tabID] = context
        return context
    }

    /// The first provider with an opinion on whether this tab is working.
    private func activity(for session: TerminalSessionSnapshot) async -> TabActivity? {
        for provider in providers where provider.canHandle(session) {
            if let activity = await provider.activity(session) { return activity }
        }
        return nil
    }

    private func displayName(for session: TerminalSessionSnapshot) -> String? {
        guard let process = session.foregroundProcessName else { return nil }
        for provider in providers {
            if let name = provider.displayName(forProcess: process) { return name }
        }
        return process
    }
}
