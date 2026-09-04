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

    public func setManualTitle(_ title: String?, for tabID: UUID) {
        contexts[tabID]?.applyManualTitle(title)
    }

    public func resumeAutomaticNaming(for tabID: UUID) {
        contexts[tabID]?.resumeAutomaticNaming()
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
            workingDirectory: session.workingDirectory
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
        context.processName = displayName(for: session)
        context.workingDirectory = session.workingDirectory ?? context.workingDirectory
        context.projectName = session.projectName ?? context.projectName
        if let fallback = session.projectName ?? session.shellName {
            context.fallbackTitle = TitleFormatter.humanize(fallback) ?? fallback
        }

        contexts[session.tabID] = context
        return context
    }

    private func displayName(for session: TerminalSessionSnapshot) -> String? {
        guard let process = session.foregroundProcessName else { return nil }
        for provider in providers {
            if let name = provider.displayName(forProcess: process) { return name }
        }
        return process
    }
}
