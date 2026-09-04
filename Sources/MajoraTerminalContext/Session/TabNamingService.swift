import Foundation

/// Drives naming for every open tab.
///
/// Owns the poll loop, the monitors and the coordinator, and publishes a tab
/// whenever its visible title actually changes — so the UI redraws on renames,
/// not on every poll.
public actor TabNamingService {
    /// Snapshotting is a `tcgetpgrp` plus a couple of sysctls per tab, so this
    /// is cheap; the stability rules, not the poll rate, decide how often a
    /// title may move.
    public static let defaultInterval: Duration = .seconds(2)

    private let coordinator: TabContextCoordinator
    private let interval: Duration
    private var monitors: [UUID: TerminalSessionMonitor] = [:]
    private var publishedTitles: [UUID: String] = [:]
    private var subscribers: [UUID: AsyncStream<TabContext>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?

    public init(
        coordinator: TabContextCoordinator = .standard(),
        interval: Duration = TabNamingService.defaultInterval
    ) {
        self.coordinator = coordinator
        self.interval = interval
    }

    deinit {
        pollTask?.cancel()
        for subscriber in subscribers.values { subscriber.finish() }
    }

    // MARK: - Tabs

    public func attach(_ monitor: TerminalSessionMonitor) {
        monitors[monitor.tabID] = monitor
    }

    public func detach(tabID: UUID) {
        monitors[tabID] = nil
        publishedTitles[tabID] = nil
    }

    public func context(for tabID: UUID) async -> TabContext? {
        await coordinator.context(for: tabID)
    }

    /// The user renamed a tab by hand: naming stops for it until resumed.
    public func setManualTitle(_ title: String?, for tabID: UUID) async {
        await coordinator.setManualTitle(title, for: tabID)
        if let context = await coordinator.context(for: tabID) { publish(context) }
    }

    public func resumeAutomaticNaming(for tabID: UUID) async {
        await coordinator.resumeAutomaticNaming(for: tabID)
    }

    // MARK: - Updates

    /// Tabs whose displayed title has changed.
    public func updates() -> AsyncStream<TabContext> {
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func publish(_ context: TabContext) {
        guard publishedTitles[context.tabID] != context.displayTitle else { return }
        publishedTitles[context.tabID] = context.displayTitle
        for subscriber in subscribers.values { subscriber.yield(context) }
    }

    // MARK: - Poll loop

    public func start() {
        guard pollTask == nil else { return }
        // Detached so the loop is genuinely off the actor between polls
        // rather than inheriting isolation and holding it.
        pollTask = Task.detached(priority: .utility) { [weak self, interval] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One round over every attached tab. Exposed so tests and the app can step
    /// naming deterministically instead of waiting on the timer.
    public func pollOnce() async {
        for monitor in monitors.values {
            let snapshot = await monitor.snapshot()
            let context = await coordinator.refresh(snapshot)
            publish(context)
        }
    }
}
