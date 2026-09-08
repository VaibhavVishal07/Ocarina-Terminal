import AppKit
import Foundation
import OcarinaTerminalContext
import Observation

/// What the tab strip draws for one tab.
@MainActor
@Observable
public final class TabItem: Identifiable {
    public let id: UUID
    /// The title the naming layer settled on: a hand-typed one, or the word
    /// filter's reading of the prompt. On screen from the first poll.
    public var generatedTitle: String
    /// The text the title was made from: a prompt when a conversation named the
    /// tab, the command line when a running program did. Nil at a bare prompt.
    public var activeTask: String?
    /// Whether that text is something a person said to an agent.
    ///
    /// Only a prompt is worth rewriting. `npm run dev` is already the clearest
    /// form of itself, and putting a command line through a model that writes
    /// to-do items turns "Dev Server" into "Run the development server" — a
    /// worse name, bought with a subprocess and a slice of the allowance.
    public var isConversation = false
    /// `Claude Code · ~/Projects/checkout` — secondary everywhere.
    public var subtitle: String?
    /// What is running in the tab, for the icon. Nil at a bare prompt.
    public var processName: String?
    public var isManuallyNamed: Bool = false
    /// Busy, done, or failed — drawn as the status dot.
    public var activity: TabActivity = .idle

    /// The summariser, so the strip can show the same quality of name the task
    /// panel does. Weak and ignored: the model owns it, and it is read here,
    /// never observed as a reference.
    @ObservationIgnored weak var summariser: TaskSummariser?

    /// The contextual task — the primary title.
    ///
    /// Computed, so a better name arriving from the summariser redraws the
    /// strip on its own. The word filter's title is what stands here until
    /// then, and it is what stands forever on a machine with no agent
    /// installed — this only ever replaces a title, it never waits for one.
    public var title: String {
        guard !isManuallyNamed, isConversation, let activeTask,
              let better = summariser?.title(for: activeTask)
        else { return generatedTitle }
        return better
    }

    init(id: UUID, title: String) {
        self.id = id
        self.generatedTitle = title
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

    /// Whether this app has ever been launched on this machine.
    ///
    /// One bit, and the only thing Ocarina remembers about you between
    /// launches that is not a theme or a tab. It decides whether launch opens
    /// a tab or leaves the landing screen up; see `opensTabAtLaunch`.
    private let defaults = UserDefaults.standard
    private static let hasLaunchedKey = "ocarina.hasLaunched"

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
            guard let better = taskSummariser.title(for: task.prompt) else { return task }
            return AgentTask(
                id: task.id,
                title: better,
                prompt: task.prompt,
                askedAt: task.askedAt,
                state: task.state
            )
        }
    }

    // MARK: - Dropping

    /// A drag is over the terminal right now, so the panel can draw the target.
    ///
    /// This is all that is left of it. A chip under the prompt was built —
    /// thumbnail, name, and an × that took the path back off the line — and it
    /// was one thing too many: the path is already at the prompt, in the place
    /// you are about to press Return on, which makes a second widget saying the
    /// same thing furniture. The overlay stays because it is the part that
    /// teaches; the receipt was never needed.
    public private(set) var isDropTarget = false

    // MARK: - Usage

    /// What has gone through the limit window the selected agent is inside, or
    /// nil when the tab in front is not an agent at all.
    ///
    /// Nil is the common case and it is the one that matters: the card is
    /// about a conversation, and a shell at a prompt is not having one.
    public private(set) var usage: UsageWindow?

    @ObservationIgnored private let usageMeter = TokenUsageMeter()
    @ObservationIgnored private var usageRefresh: Task<Void, Never>?
    /// What the tab in front is doing, in the menu bar — for when Ocarina is
    /// not the window in front, which is the only time it is worth anything.
    /// The token figure it used to carry is back on its card; see
    /// `ActivityStatusItem`.
    @ObservationIgnored private let activityStatusItem = ActivityStatusItem()

    /// Whether the tab in front is running a coding agent.
    ///
    /// Matched the way the tab icon matches: on the naming layer's
    /// `processName`, which is a provider's display name when one recognised
    /// the process and the raw executable otherwise, so "Claude Code" and
    /// "claude" both land.
    public var isAgentSelected: Bool {
        guard let name = selectedTab?.processName?.lowercased() else { return false }
        return Self.agentPrefixes.contains { name.hasPrefix($0) }
    }

    private static let agentPrefixes = ["claude", "codex", "gemini", "opencode"]

    public var selectedTab: TabItem? {
        selectedTabID.flatMap { id in tabs.first { $0.id == id } }
    }

    /// Re-reads usage on a slow timer.
    ///
    /// Slower than the task panel's two seconds by a lot: a window is five
    /// hours long, the number moves once per agent turn, and the read touches
    /// every project rather than one. Fifteen seconds is finer than anything
    /// the card can show.
    public func startWatchingUsage() {
        usageRefresh?.cancel()
        usageRefresh = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshUsage()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func refreshUsage() async {
        // A shell at a prompt is not having a conversation, so there is no
        // window to report. The menu bar still has something to say about it —
        // a build in a plain shell is exactly the case the item is for — so
        // this no longer takes the item down with it.
        usage = isAgentSelected ? await usageMeter.read() : nil
        refreshStatusItem()
    }

    /// The menu bar reading, rebuilt from whatever is true now.
    ///
    /// Called from four places because four different things move it: the
    /// activity arrives on the naming service's stream, the token figure on a
    /// fifteen-second timer, the selection when you change tabs, and the
    /// wording when somebody picks a theme. Cheap enough to call on any of
    /// them — it sets a title and rebuilds a menu nobody has open.
    ///
    /// No tabs is nil, which takes the item out of the menu bar rather than
    /// leaving it there saying the all-clear about an app with nothing in it.
    private func refreshStatusItem() {
        activityStatusItem.update(ActivityStatusItem.Reading(
            activity: tabs.isEmpty ? nil : selectedActivity,
            task: selectedTaskTitle,
            usage: usage,
            speech: themes.theme.speech
        ))
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
        refreshTasks()
        taskRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.pollTasksIfWatched()
            }
        }
    }

    /// The poll runs for whoever is listening.
    ///
    /// The status card reads it as well as the task panel, and the card is
    /// shown whenever an agent is selected — so this cannot stop dead on a
    /// hidden panel the way it once did.
    ///
    /// The saving it was making is kept: with no agent tab in front of you,
    /// nothing is consuming this and it does not run.
    private func pollTasksIfWatched() {
        guard isTaskPanelVisible || !NSApp.isActive else { return }
        refreshTasks()
    }

    /// Somebody typed. Names may now cost a subprocess.
    private func noteUserInput() {
        guard !summarisingAllowed else { return }
        summarisingAllowed = true
        // The transcript is usually already read and unchanged, and
        // `refreshTasks` skips an unchanged one — so without this the better
        // names would wait on the next agent turn rather than the next poll.
        lastTaskSignature = nil
        // Every tab already has a prompt by now; none of them were allowed to
        // be asked about until this moment.
        summariseTabTitles()
    }

    /// Puts the prompts naming the open tabs in front of the summariser.
    ///
    /// The task panel only ever reads the selected tab's conversation, so
    /// without this a background tab's name would sit on the word filter's
    /// reading of it until you clicked into the tab. The summariser holds one
    /// queue and one cache for both, so a prompt that is also in the panel
    /// costs nothing to ask about twice.
    private func summariseTabTitles() {
        guard summarisingAllowed else { return }
        let prompts = tabs.compactMap { tab in
            tab.isManuallyNamed || !tab.isConversation ? nil : tab.activeTask
        }
        guard !prompts.isEmpty else { return }
        taskSummariser.refresh(prompts: prompts)
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
        guard let session = selectedSession else { rawTasks = []; return }

        let directory = session.workingDirectory
        let monitor = session.monitor
        let source = taskSource
        // Which tab asked. Every step below can suspend, and a tab switch in
        // the middle of one is exactly the case this is here for: a read that
        // comes back for a tab you have already left must not be applied.
        let asking = selectedTabID

        Task { [weak self] in
            // When the agent in *this* tab started, which is what picks its
            // conversation out of the several a project can have open — and
            // whether there is an agent in front of this tab at all. A shell
            // opened while another tab works has no conversation of its own,
            // and used to be handed that tab's.
            let snapshot = await monitor?.snapshot()
            let startedAt = snapshot?.foregroundProcessStartTime
            let agentInForeground = AgentTaskSource.isAgent(snapshot?.foregroundProcessName)
            let signature = await Task.detached {
                source.signature(
                    for: directory, startedAt: startedAt, agentInForeground: agentInForeground
                )
            }.value

            guard let self, self.selectedTabID == asking else { return }
            guard signature != self.lastTaskSignature || self.rawTasks.isEmpty else { return }
            self.lastTaskSignature = signature

            let read = await Task.detached {
                source.tasks(
                    for: directory, startedAt: startedAt, agentInForeground: agentInForeground
                )
            }.value
            guard self.selectedTabID == asking else { return }
            self.apply(read)
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

    /// The bundled recipe with this id, which is where an install command lives.
    public func recipe(_ id: String) -> Recipe? {
        recipes.flatMap(\.items).first { $0.id == id }
    }

    /// Starts an agent from the first-run board.
    ///
    /// Installed, it opens. Missing, it installs. One press either way, because
    /// the difference between those two is a distinction the person on this
    /// screen has no way to make yet — they pressed "Claude Code" and what they
    /// meant was "give me Claude Code".
    ///
    /// Always a fresh tab. The board only appears with nothing open, but a
    /// command sent into a tab that is already running something is a command
    /// typed into that program rather than at a prompt, and that is a bad way
    /// to find out this method exists.
    public func start(_ tool: AgentTool) {
        let command: String
        if AgentCatalog.isInstalled(tool) {
            command = tool.executable
        } else if let recipe = recipe(tool.id) {
            command = recipe.command
        } else {
            // No recipe to install from. The drawer is the only honest answer:
            // a plate that does nothing is worse than one that hands over.
            isQuickActionsVisible = true
            return
        }
        let tab = newTab()
        sessions[tab.id]?.runWhenReady(command)
    }

    /// What the tab in front of you is doing, for the rail across the top of
    /// the terminal. Nil with nothing selected.
    /// What the status card names under its headline.
    ///
    /// The task being worked on, or the last one the agent stopped on — so
    /// the card still says what the tick refers to once the work is over,
    /// rather than going blank at the moment it becomes worth reading.
    public var selectedTaskTitle: String? {
        tasks.last(where: { $0.state == .working })?.title ?? tasks.last?.title
    }

    public var selectedActivity: TabActivity? {
        selectedTabID.flatMap { id in tabs.first { $0.id == id }?.activity }
    }

    /// Whether anything is running anywhere in the window.
    ///
    /// Any tab, not the selected one, and that is the point of it. The mark
    /// sits above a column listing every tab, so it answers the question you
    /// have while you are looking at some *other* tab: is the thing I started
    /// still going. Bound to the selected tab it would say nothing you could
    /// not already see in the tab you were in.
    public var isAnythingRunning: Bool {
        tabs.contains { $0.activity.isRunning }
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
        for session in sessions.values {
            session.apply(themes.theme, tintingOutput: themes.tintsProgramColours)
        }
        // The menu bar is outside the environment the theme reaches through,
        // and the words up there are the theme's. Told, like the emulator is.
        refreshStatusItem()
    }

    /// Turns the retint on or off, and tells every open terminal.
    ///
    /// What is already on screen keeps the colours it was drawn in: the
    /// emulator holds a grid of resolved cells, not the bytes that made them.
    /// Everything printed after this follows the theme.
    public func setTinting(_ isOn: Bool) {
        guard isOn != themes.tintsProgramColours else { return }
        themes.tintsProgramColours = isOn
        applyThemeToSessions()
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
        session.onDragStateChange = { [weak self] isOver in self?.isDropTarget = isOver }
        // Styled before it is ever shown, so a new tab never flashes the
        // default palette on its way to the chosen one.
        session.apply(themes.theme, tintingOutput: themes.tintsProgramColours)
        sessions[session.id] = session

        // Before any activity, a tab is named for where it is.
        let directory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let fallback = TitleFormatter.humanize(directory.lastPathComponent)
            ?? directory.lastPathComponent
        let tab = TabItem(id: session.id, title: fallback)
        tab.summariser = taskSummariser
        tabs.append(tab)
        selectedTabID = tab.id

        if let monitor = session.monitor {
            Task { await namingService.attach(monitor) }
        }
        return tab
    }

    public func closeTab(_ id: UUID) {
        // Where it sat, so the selection can land on what took its place.
        // Read before the removal, and nil for an id that is no longer in the
        // list — closing the same tab twice must not move the selection off
        // the tab that inherited it.
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        sessions[id]?.close()
        sessions[id] = nil
        tabs.removeAll { $0.id == id }
        Task { await namingService.detach(tabID: id) }

        // The neighbour, not the top of the list. Closing the tab you are in
        // should leave you beside where you were — `tabs.first` sent you to
        // the first tab in the column instead, so closing the fourth of five
        // jumped the selection three rows away from the work you were doing.
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        // The last tab going takes the right-hand column with it, and the
        // column is drawn from this — left set, it would have been a usage
        // card for a conversation that is no longer on screen.
        if tabs.isEmpty {
            usage = nil
            rawTasks = []
            lastTaskSignature = nil
        }
        refreshStatusItem()
    }

    public func selectTab(_ id: UUID) {
        guard id != selectedTabID else { return }
        selectedTabID = id

        // The list belongs to the tab, so it goes with the tab — at once, not
        // on the next poll. Leaving it up meant switching tabs showed the tab
        // you had just left: its tasks stood there for a beat, blanked, and
        // were replaced by the new tab's. A panel that shows the wrong list
        // and then corrects itself is worse than one that shows nothing for a
        // moment, because you cannot tell which of the two you are reading.
        rawTasks = []
        lastTaskSignature = nil
        refreshTasks()
        // Without this the usage card outlives the tab it belonged to for up
        // to a poll: switch from an agent to a shell and it sat there for
        // fifteen seconds, reporting a conversation that is no longer on
        // screen.
        Task { await refreshUsage() }
    }

    // MARK: - Naming

    /// Whether launch opens a tab, or leaves the landing screen up.
    ///
    /// Only on the very first launch, and only with nothing installed. That
    /// screen is the whole answer to "I just installed this, now what", and a
    /// tab opened on top of it hides the answer behind a blinking prompt —
    /// which is the screen this app exists in order not to be.
    ///
    /// Once, though, and not once per launch. Somebody who has decided to use
    /// Ocarina as a plain terminal and never install an agent has made a
    /// choice, and meeting them with the same pitch every morning is not
    /// helping them, it is nagging. The landing screen is still one \u{2318}W away
    /// whenever they want it.
    nonisolated static func opensTabAtLaunch(isFirstLaunch: Bool, installed: Set<String>) -> Bool {
        !(isFirstLaunch && installed.isEmpty)
    }

    public func start() {
        Task { await namingService.start() }
        sleepGuard.start()
        let firstLaunch = !defaults.bool(forKey: Self.hasLaunchedKey)
        defaults.set(true, forKey: Self.hasLaunchedKey)
        if tabs.isEmpty,
           Self.opensTabAtLaunch(isFirstLaunch: firstLaunch, installed: AgentCatalog.installedIDs()) {
            newTab()
        }
        startWatchingTasks()
        startWatchingUsage()
    }

    /// A hand-typed name wins and stops automatic naming for that tab.
    public func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard !trimmed.isEmpty else { return }
        tab.generatedTitle = trimmed
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
        tab.generatedTitle = context.displayTitle
        tab.activeTask = context.activeTask
        tab.isConversation = context.contextSource == .llmSession
        tab.subtitle = context.subtitle
        tab.processName = context.processName
        summariseTabTitles()

        // A fresh failure brings the banner back even if the last one was
        // dismissed: dismissing means "I have read this one", not "stop telling
        // me when things break".
        if case .failed = context.activity, tab.activity != context.activity {
            isErrorBannerVisible = true
        }
        tab.activity = context.activity
        tab.isManuallyNamed = !context.isAutoNamingEnabled
        // The menu bar's whole subject. This is the only place the activity
        // changes, so it is the only place that has to say so.
        refreshStatusItem()
    }

    deinit {
        updateTask?.cancel()
    }
}
