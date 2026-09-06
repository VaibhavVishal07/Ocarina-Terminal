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

    /// Kept across launches. A pinned tab is listed whether or not it is
    /// running, and closing it ends the session rather than throwing it away.
    public var isPinned: Bool = false

    /// Listed but not started: restored from a previous launch, or closed while
    /// pinned. It becomes live the moment it is selected.
    ///
    /// Nothing is spawned for a pinned tab until it is asked for. Restoring six
    /// of them would otherwise mean six login shells at launch, each running the
    /// user's profile, before anyone had clicked anything.
    public var isDormant: Bool = false

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
        rawTasks.map { task in
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
    /// Better names for the same tasks, when an agent is around to write them.
    public let taskSummariser = TaskSummariser()
    @ObservationIgnored private var taskRefresh: Task<Void, Never>?

    /// Re-reads the transcript on a timer while the panel is open.
    ///
    /// Polling rather than watching: the file is appended to constantly by a
    /// process we do not own, and a two-second read of one file costs less than
    /// keeping a file descriptor and a coalescing timer correct.
    /// The panel is permanent, so this runs for the life of the window.
    public func startWatchingTasks() {
        taskRefresh?.cancel()
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

    // MARK: - Pinned tabs

    @ObservationIgnored private var pins: [PinnedTab] = []
    /// Where each tab actually is, as the naming layer last saw it — which is
    /// not where its shell started once anybody has typed `cd`.
    @ObservationIgnored private var liveDirectories: [UUID: URL] = [:]

    /// Pinned first, then the rest. Two lists rather than one sorted one,
    /// because the sidebar draws a rule between them.
    public var pinnedTabs: [TabItem] { tabs.filter(\.isPinned) }
    public var unpinnedTabs: [TabItem] { tabs.filter { !$0.isPinned } }

    /// Lists a pinned tab without starting it.
    private func restorePinnedTabs() {
        pins = pinStore.load()
        for pin in pins where !tabs.contains(where: { $0.id == pin.id }) {
            let tab = TabItem(id: pin.id, title: pin.title)
            tab.isPinned = true
            tab.isDormant = true
            tab.subtitle = Self.abbreviate(pin.directory)
            tabs.append(tab)
        }
    }

    /// `~/Projects/checkout`, which is what the row has room for.
    static func abbreviate(_ directory: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = directory.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Starts the shell a dormant tab has been standing in for.
    private func wake(_ tab: TabItem) {
        guard sessions[tab.id] == nil else {
            tab.isDormant = false
            return
        }
        // The directory may have been renamed or deleted since it was pinned.
        // Home is a worse answer than the one on file but a much better one
        // than a tab that fails to open at all.
        var directory = pins.first { $0.id == tab.id }?.directory
        if let candidate = directory,
           !FileManager.default.fileExists(atPath: candidate.path) {
            directory = nil
        }

        let session = TerminalSession(id: tab.id, workingDirectory: directory)
        session.onInput = { [weak self] in self?.noteUserInput() }
        session.apply(themes.theme)
        sessions[tab.id] = session
        tab.isDormant = false

        if let monitor = session.monitor {
            Task { await namingService.attach(monitor) }
        }
    }

    public func setPinned(_ pinned: Bool, for id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned = pinned

        if pinned {
            record(tab)
        } else {
            pins.removeAll { $0.id == id }
            pinStore.save(pins)
            // A dormant row was only ever the pin. Without it there is nothing
            // left for it to be.
            if tab.isDormant { tabs.removeAll { $0.id == id } }
            if selectedTabID == id { selectedTabID = tabs.first?.id }
        }
    }

    /// Writes a pinned tab's name and directory down, if either has moved.
    private func record(_ tab: TabItem) {
        guard tab.isPinned else { return }
        let directory = liveDirectories[tab.id]
            ?? sessions[tab.id]?.workingDirectory
            ?? pins.first { $0.id == tab.id }?.directory
            ?? FileManager.default.homeDirectoryForCurrentUser

        let entry = PinnedTab(id: tab.id, title: tab.title, directoryPath: directory.path)
        if let index = pins.firstIndex(where: { $0.id == tab.id }) {
            guard pins[index] != entry else { return }
            pins[index] = entry
        } else {
            pins.append(entry)
        }
        pinStore.save(pins)
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

    @ObservationIgnored private let pinStore: PinnedTabStore

    public init(
        namingService: TabNamingService = TabNamingService(),
        sleepGuard: SleepGuard = SleepGuard(),
        themes: ThemeStore = ThemeStore(),
        pinStore: PinnedTabStore = PinnedTabStore()
    ) {
        self.namingService = namingService
        self.sleepGuard = sleepGuard
        self.themes = themes
        self.pinStore = pinStore
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
        Task { await namingService.detach(tabID: id) }

        if let tab = tabs.first(where: { $0.id == id }), tab.isPinned {
            // Pinned means still there tomorrow, so closing ends the session
            // and leaves the row. Unpinning is what throws the tab away.
            tab.isDormant = true
            tab.activity = .idle
            tab.processName = nil
            tab.subtitle = pins.first { $0.id == id }.map { Self.abbreviate($0.directory) }
        } else {
            tabs.removeAll { $0.id == id }
        }

        if selectedTabID == id {
            // A live tab is a better landing place than a dormant one, which
            // would only show the empty state.
            selectedTabID = tabs.first { !$0.isDormant }?.id ?? tabs.first?.id
        }
    }

    /// Selecting a dormant tab is what starts it. That is the whole gesture the
    /// feature is for: the tab you left is already in the list, and tapping it
    /// puts you back in the directory you were in.
    public func selectTab(_ id: UUID) {
        if let tab = tabs.first(where: { $0.id == id }), tab.isDormant { wake(tab) }
        selectedTabID = id
    }

    // MARK: - Naming

    public func start() {
        Task { await namingService.start() }
        sleepGuard.start()
        // Before the empty check: a window that restored yesterday's pins is
        // not empty, and opening an untitled tab beside them is not what was
        // asked for.
        restorePinnedTabs()
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

        // Where it is now, not where its shell started.
        if let directory = context.workingDirectory { liveDirectories[tab.id] = directory }
        record(tab)
    }

    deinit {
        updateTask?.cancel()
    }
}
