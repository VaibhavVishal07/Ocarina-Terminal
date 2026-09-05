import Foundation
import MajoraTerminalContext
import Observation

/// What the tab strip draws for one tab.
@MainActor
@Observable
public final class TabItem: Identifiable {
    public let id: UUID
    /// The contextual task — the primary title.
    public var title: String
    /// `Claude Code · ~/Projects/checkout` — secondary everywhere.
    public var subtitle: String?
    public var isManuallyNamed: Bool = false
    /// Busy, done, or failed — drawn as the status dot.
    public var activity: TabActivity = .idle

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

/// Owns the open tabs and keeps their titles in step with what they are doing.
@MainActor
@Observable
public final class MajoraModel {
    public private(set) var tabs: [TabItem] = []
    public var selectedTabID: UUID?
    public var isCommandPaletteVisible = false

    @ObservationIgnored private var sessions: [UUID: TerminalSession] = [:]
    @ObservationIgnored private let namingService: TabNamingService
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    public init(namingService: TabNamingService = TabNamingService()) {
        self.namingService = namingService
        observeTitleChanges()
    }

    public func session(for id: UUID) -> TerminalSession? { sessions[id] }

    public var selectedSession: TerminalSession? {
        selectedTabID.flatMap { sessions[$0] }
    }

    // MARK: - Tabs

    @discardableResult
    public func newTab(workingDirectory: URL? = nil) -> TabItem {
        let session = TerminalSession(workingDirectory: workingDirectory)
        sessions[session.id] = session

        // Before any activity, a tab is named for where it is.
        let directory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let fallback = TitleFormatter.humanize(directory.lastPathComponent)
            ?? directory.lastPathComponent
        let tab = TabItem(id: session.id, title: fallback)
        tabs.append(tab)
        selectedTabID = tab.id

        if let monitor = session.monitor {
            Task { await namingService.attach(monitor) }
        }
        return tab
    }

    public func closeTab(_ id: UUID) {
        sessions[id]?.close()
        sessions[id] = nil
        tabs.removeAll { $0.id == id }
        Task { await namingService.detach(tabID: id) }

        if selectedTabID == id {
            selectedTabID = tabs.first?.id
        }
    }

    public func selectTab(_ id: UUID) {
        selectedTabID = id
    }

    // MARK: - Naming

    public func start() {
        Task { await namingService.start() }
        if tabs.isEmpty { newTab() }
    }

    /// A hand-typed name wins and stops automatic naming for that tab.
    public func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard !trimmed.isEmpty else { return }
        tab.title = trimmed
        tab.isManuallyNamed = true
        Task { await namingService.setManualTitle(trimmed, for: id) }
    }

    public func resumeAutomaticNaming(for id: UUID) {
        tabs.first(where: { $0.id == id })?.isManuallyNamed = false
        Task { await namingService.resumeAutomaticNaming(for: id) }
    }

    private func observeTitleChanges() {
        updateTask = Task { [namingService] in
            for await context in await namingService.updates() {
                await MainActor.run { self.apply(context) }
            }
        }
    }

    private func apply(_ context: TabContext) {
        guard let tab = tabs.first(where: { $0.id == context.tabID }) else { return }
        tab.title = context.displayTitle
        tab.subtitle = context.subtitle
        tab.activity = context.activity
        tab.isManuallyNamed = !context.isAutoNamingEnabled
    }

    deinit {
        updateTask?.cancel()
    }
}
