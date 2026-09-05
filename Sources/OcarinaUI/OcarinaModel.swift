import Foundation
import OcarinaTerminalContext
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
    /// What is running in the tab, for the icon. Nil at a bare prompt.
    public var processName: String?
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
public final class OcarinaModel {
    public private(set) var tabs: [TabItem] = []
    public var selectedTabID: UUID?
    public var isCommandPaletteVisible = false

    /// Keeps the Mac awake while Ocarina is open. On by default.
    public let sleepGuard: SleepGuard

    @ObservationIgnored private var sessions: [UUID: TerminalSession] = [:]
    @ObservationIgnored private let namingService: TabNamingService
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    /// The look, and the list of looks available.
    public let themes: ThemeStore

    /// The commands the drawer offers, read once at launch.
    public let recipes: [RecipeGroup] = RecipeCatalog.load()

    public var isQuickActionsVisible = false
    public var isThemePickerVisible = false

    /// Dismissed per failure, not for good: the next failing command shows it
    /// again, because the next one is a new thing the user does not understand.
    public var isErrorBannerVisible = true

    public var isTaskPanelVisible = false
    /// Set when *you* close the panel, so it stops opening itself.
    ///
    /// The panel appears on its own the first time a tab has tasks, because
    /// somebody who has just prompted an agent has no reason to know the panel
    /// exists. Doing that twice would be a fight rather than a hint.
    @ObservationIgnored private var autoOpenSuppressed = false
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    /// Set when a paste needs a word said about it first.
    public var pendingPaste: PasteInspector.Reading?

    /// ⌘V comes here rather than going straight to the emulator.
    ///
    /// Anything unremarkable is pasted with no ceremony — a terminal that
    /// interrupts every paste is one people learn to click through. Only
    /// multi-command or dangerous text stops for review.
    public func requestPaste(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        let clean = PasteInspector.withoutTrailingNewline(text)
        let reading = PasteInspector.read(clean)
        if reading.needsReview { pendingPaste = reading } else { typeAtPrompt(clean) }
    }

    public func confirmPendingPaste() {
        guard let pending = pendingPaste else { return }
        pendingPaste = nil
        typeAtPrompt(pending.text)
    }
    /// Tasks for the selected tab, refreshed while the panel is open.
    public private(set) var tasks: [AgentTask] = []

    @ObservationIgnored private let taskSource = AgentTaskSource()
    /// Better names for the same tasks, when an agent is around to write them.
    public let taskSummariser = TaskSummariser()
    @ObservationIgnored private var taskRefresh: Task<Void, Never>?

    /// Re-reads the transcript on a timer while the panel is open.
    ///
    /// Polling rather than watching: the file is appended to constantly by a
    /// process we do not own, and a two-second read of one file costs less than
    /// keeping a file descriptor and a coalescing timer correct.
    public func setTaskPanel(visible: Bool) {
        // A deliberate close is the one signal that the panel is unwanted.
        if !visible { autoOpenSuppressed = true }
        isTaskPanelVisible = visible
        taskRefresh?.cancel()
        guard visible else { tasks = []; return }
        refreshTasks()
        taskRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refreshTasks()
            }
        }
    }

    /// Watches for a tab's first tasks while the panel is shut.
    ///
    /// Reading one JSONL file every four seconds is cheaper than the machinery
    /// to be told about it, and it stops the moment the panel opens — from then
    /// on the panel's own poll is doing the same work.
    func startWatchingForTasks() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled else { return }
                guard !isTaskPanelVisible, !autoOpenSuppressed,
                      let directory = selectedSession?.workingDirectory
                else { continue }
                if !taskSource.tasks(for: directory).isEmpty {
                    setTaskPanel(visible: true)
                    // `setTaskPanel` only suppresses on a close; opening here
                    // must not look like the user asked.
                    autoOpenSuppressed = false
                }
            }
        }
    }

    private func refreshTasks() {
        guard let directory = selectedSession?.workingDirectory else { tasks = []; return }
        let read = taskSource.tasks(for: directory)

        // The local title shows immediately; Claude's replaces it once it has
        // been asked. Nothing here waits on a subprocess.
        tasks = read.map { task in
            guard let better = taskSummariser.titles[task.id] else { return task }
            return AgentTask(
                id: task.id,
                title: better,
                prompt: task.prompt,
                askedAt: task.askedAt,
                state: task.state
            )
        }
        taskSummariser.refresh(read)
    }

    /// Types text into the selected tab without running it. Every path that
    /// puts a command in front of the user ends here, and none of them press
    /// Return.
    public func typeAtPrompt(_ text: String) {
        selectedSession?.type(text)
    }

    /// The exit code of the selected tab's last command, when it failed.
    public var selectedFailure: Int? {
        guard let id = selectedTabID,
              let tab = tabs.first(where: { $0.id == id }),
              case let .failed(code) = tab.activity
        else { return nil }
        return code
    }

    /// Hands the failure to whichever agent is installed. With none installed
    /// the drawer opens instead — the answer to "explain this" is then
    /// "install something that can", which is a question this app can also
    /// answer.
    public func explainLastFailure() {
        guard let session = selectedSession else { return }
        guard let command = ErrorHelp.command(explaining: session.recentOutput()) else {
            isQuickActionsVisible = true
            return
        }
        typeAtPrompt(command)
    }

    public init(
        namingService: TabNamingService = TabNamingService(),
        sleepGuard: SleepGuard = SleepGuard(),
        themes: ThemeStore = ThemeStore()
    ) {
        self.namingService = namingService
        self.sleepGuard = sleepGuard
        self.themes = themes
        observeTitleChanges()
    }

    /// Restyles every open terminal. Chrome follows on its own because the
    /// views read the theme from the environment; the emulator does not, so it
    /// is told.
    public func applyThemeToSessions() {
        for session in sessions.values { session.apply(themes.theme) }
    }

    public func session(for id: UUID) -> TerminalSession? { sessions[id] }

    public var selectedSession: TerminalSession? {
        selectedTabID.flatMap { sessions[$0] }
    }

    // MARK: - Tabs

    @discardableResult
    public func newTab(workingDirectory: URL? = nil) -> TabItem {
        let session = TerminalSession(workingDirectory: workingDirectory)
        // Styled before it is ever shown, so a new tab never flashes the
        // default palette on its way to the chosen one.
        session.apply(themes.theme)
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
        sleepGuard.start()
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
        tab.processName = context.processName

        // A fresh failure brings the banner back even if the last one was
        // dismissed: dismissing means "I have read this one", not "stop telling
        // me when things break".
        if case .failed = context.activity, tab.activity != context.activity {
            isErrorBannerVisible = true
        }
        tab.activity = context.activity
        tab.isManuallyNamed = !context.isAutoNamingEnabled
    }

    deinit {
        updateTask?.cancel()
    }
}
