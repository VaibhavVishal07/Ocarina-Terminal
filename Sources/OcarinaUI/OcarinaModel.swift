import AppKit
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
    public var isFeedbackVisible = false
    public var isThemePickerVisible = false

    /// Dismissed per failure, not for good: the next failing command shows it
    /// again, because the next one is a new thing the user does not understand.
    public var isErrorBannerVisible = true

    /// Whether the task panel is showing.
    ///
    /// A toggle again, but a plain one. What had to go was the notch and its
    /// slide: as a drawer it animated the terminal's width, and every frame of
    /// that was an `ioctl(TIOCSWINSZ)` and a SIGWINCH. Showing and hiding a
    /// column resizes the terminal exactly once, which is what any window does.
    public var isTaskPanelVisible = true

    /// Whether the summariser may shell out yet.
    ///
    /// `TaskSummariser` runs the `claude` binary, and a subprocess inherits the
    /// app's TCC identity: every protected thing it reads is asked about in
    /// Ocarina's name. Run at startup it put "Ocarina would like to access your
    /// Photo Library" — and a network volume prompt on the next run — in front
    /// of someone who had done nothing but open a terminal, about a feature they
    /// had not asked for and could not see.
    ///
    /// The panel is always open now, so "you opened it" is no longer a signal
    /// anything can wait for. The first keystroke is: it cannot happen at
    /// launch, and it means the session is genuinely in use. The heuristic
    /// titles are on screen the whole time; only the better names wait.
    @ObservationIgnored private(set) var summarisingAllowed = false

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
    /// What the transcript says, before Claude has renamed any of it.
    public private(set) var rawTasks: [AgentTask] = []

    /// Tasks as the panel shows them.
    ///
    /// Computed rather than stored, so a title arriving from the summariser
    /// reaches the panel on its own. Stored, it only updated on the next
    /// transcript change — which never comes once you stop typing, so the
    /// better titles appeared minutes later or not at all.
    public var tasks: [AgentTask] {
        _ = clearedRevision
        let visible: [AgentTask]
        if let directory = selectedSession?.workingDirectory,
           let mark = cleared.mark(for: directory) {
            visible = rawTasks.filter { $0.askedAt > mark }
        } else {
            visible = rawTasks
        }
        return visible.map { task in
            guard let better = taskSummariser.titles[task.id] else { return task }
            return AgentTask(
                id: task.id,
                title: better,
                prompt: task.prompt,
                askedAt: task.askedAt,
                state: task.state
            )
        }
    }

    @ObservationIgnored private let taskSource = AgentTaskSource()
    /// Per-project line under the list. Observed, so clearing redraws the panel
    /// without waiting for the next poll.
    @ObservationIgnored private var cleared = ClearedTasks()
    /// Bumped when the line moves, purely so the computed `tasks` is re-read.
    private var clearedRevision = 0
    /// Better names for the same tasks, when an agent is around to write them.
    public let taskSummariser = TaskSummariser()
    @ObservationIgnored private var taskRefresh: Task<Void, Never>?

    /// Re-reads the transcript on a timer while the panel is open.
    ///
    /// Polling rather than watching: the file is appended to constantly by a
    /// process we do not own, and a two-second read of one file costs less than
    /// keeping a file descriptor and a coalescing timer correct.
    public func setTaskPanel(visible: Bool) {
        guard visible != isTaskPanelVisible else { return }
        isTaskPanelVisible = visible
        startWatchingTasks()
    }

    /// Polls while the panel is up, and not at all while it is not: the list is
    /// read for the panel and nothing else looks at it.
    public func startWatchingTasks() {
        taskRefresh?.cancel()
        taskRefresh = nil
        guard isTaskPanelVisible else { return }
        refreshTasks()
        taskRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refreshTasks()
            }
        }
    }

    /// Somebody typed. Names may now cost a subprocess.
    private func noteUserInput() {
        guard !summarisingAllowed else { return }
        summarisingAllowed = true
        // The transcript is usually already read and unchanged, and
        // `refreshTasks` skips an unchanged one — so without this the better
        // names would wait on the next agent turn rather than the next poll.
        lastTaskSignature = nil
    }

    /// Reads the transcript off the main thread.
    ///
    /// This is what made opening the panel jerky. A transcript is a JSONL file
    /// that grows all session — 32MB on the machine this was found on — and
    /// parsing it took the better part of half a second, on the main actor, at
    /// the exact moment the panel was animating in. The window simply stopped.
    /// It then repeated every two seconds for as long as the panel was open.
    ///
    /// Now: a `stat` on the main thread, the parse on a background one, and
    /// nothing at all when the file has not changed since the last look.
    private func refreshTasks() {
        guard let directory = selectedSession?.workingDirectory else { rawTasks = []; return }

        let signature = taskSource.signature(for: directory)
        guard signature != lastTaskSignature || rawTasks.isEmpty else { return }
        lastTaskSignature = signature

        let source = taskSource
        Task { [weak self] in
            let read = await Task.detached { source.tasks(for: directory) }.value
            guard let self else { return }
            apply(read)
        }
    }

    private func apply(_ read: [AgentTask]) {
        // The heuristic title is on screen the moment this lands; Claude's
        // replaces it through `tasks` when the summariser answers.
        rawTasks = read
        guard summarisingAllowed else { return }
        taskSummariser.refresh(read)
    }

    @ObservationIgnored private var lastTaskSignature: String?

    /// Draws a line under everything asked so far in this tab.
    ///
    /// The transcript is not touched: it belongs to the agent, and deleting
    /// somebody's prompts out of Claude's history to tidy a panel would be the
    /// worst kind of helpful.
    public func clearTasks() {
        guard let directory = selectedSession?.workingDirectory else { return }
        // The newest task's own timestamp, not `now`: a prompt sent while the
        // panel was open but not yet polled would otherwise survive the clear
        // and reappear two seconds later.
        let newest = rawTasks.map(\.askedAt).max() ?? Date()
        cleared.clear(directory, at: max(newest, Date()))
        clearedRevision += 1
    }

    /// Whether there is anything to clear, so the control can say so.
    public var canClearTasks: Bool { !tasks.isEmpty }

    /// Opens a prefilled issue in the browser. No mail app, no address, no key
    /// in the binary — the repository is public and the report is a URL.
    public func openFeedbackIssue(_ message: String) {
        isFeedbackVisible = false
        guard !message.isEmpty, let url = FeedbackReport.issueURL(for: message) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The same report on the clipboard, for whoever would rather not open an
    /// account to say a button is broken.
    public func copyFeedback(_ message: String) {
        guard !message.isEmpty else { return }
        let report = FeedbackReport.body(
            message,
            version: FeedbackReport.version,
            system: FeedbackReport.system
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
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
        session.onInput = { [weak self] in self?.noteUserInput() }
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
        startWatchingTasks()
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
