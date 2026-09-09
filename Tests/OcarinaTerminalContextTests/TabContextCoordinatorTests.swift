import Foundation
import Testing
@testable import OcarinaTerminalContext

private struct StubTranscriptSource: LLMTranscriptSource {
    let prompts: [String]
    var sessionID = "stub-session"

    init(prompt: String?) {
        self.prompts = prompt.map { [$0] } ?? []
    }

    init(prompts: [String], sessionID: String = "stub-session") {
        self.prompts = prompts
        self.sessionID = sessionID
    }

    func latestPrompts(for query: TranscriptQuery) async -> TranscriptReading? {
        prompts.isEmpty ? nil : TranscriptReading(prompts: prompts, sessionID: sessionID)
    }
}

@Suite("Coordinator")
struct TabContextCoordinatorTests {

    private func coordinator(prompt: String?) -> TabContextCoordinator {
        TabContextCoordinator(
            providers: [
                LLMSessionContextProvider.claude(transcripts: StubTranscriptSource(prompt: prompt)),
                GenericProcessContextProvider()
            ]
        )
    }

    @Test("An agent session is named after its task, not its binary")
    func agentSession() async {
        let session = TerminalSessionSnapshot(
            shellName: "zsh",
            foregroundProcessName: "claude",
            foregroundCommandLine: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/Users/me/checkout")
        )
        let context = await coordinator(prompt: "Fix the payment failure state on the checkout page.")
            .refresh(session)

        #expect(context.displayTitle == "Fix Payment Failure State")
        #expect(context.subtitle == "Claude Code · /Users/me/checkout")
    }

    @Test("An agent with no readable task falls back to the project, never to its binary name")
    func agentWithoutTask() async {
        let session = TerminalSessionSnapshot(
            shellName: "zsh",
            foregroundProcessName: "claude",
            workingDirectory: URL(fileURLWithPath: "/Users/me/xstream-play")
        )
        let context = await coordinator(prompt: nil).refresh(session)
        #expect(context.displayTitle == "Xstream Play")
        #expect(context.processName == "Claude Code")
    }

    @Test("A plain command names the tab")
    func foregroundCommand() async {
        let session = TerminalSessionSnapshot(
            shellName: "zsh",
            foregroundProcessName: "npm",
            foregroundCommandLine: ["npm", "run", "dev"],
            workingDirectory: URL(fileURLWithPath: "/Users/me/xstream-play")
        )
        let context = await coordinator(prompt: nil).refresh(session)
        #expect(context.displayTitle == "Dev Server")
    }

    @Test("An idle shell keeps the project name")
    func idleShell() async {
        let session = TerminalSessionSnapshot(
            shellName: "zsh",
            foregroundProcessName: "zsh",
            workingDirectory: URL(fileURLWithPath: "/Users/me/xstream-play")
        )
        let context = await coordinator(prompt: nil).refresh(session)
        #expect(context.displayTitle == "Xstream Play")
    }

    @Test("A follow-up that names nothing leaves the tab on the work it names")
    func followUpPromptsWalkBack() async {
        let coordinator = TabContextCoordinator(
            providers: [
                LLMSessionContextProvider.claude(
                    transcripts: StubTranscriptSource(prompts: [
                        "Build and run it.",
                        "run it again",
                        "Fix the payment failure state on the checkout page."
                    ])
                )
            ]
        )
        let session = TerminalSessionSnapshot(
            foregroundProcessName: "claude",
            workingDirectory: URL(fileURLWithPath: "/Users/me/checkout")
        )
        let context = await coordinator.refresh(session)
        #expect(context.displayTitle == "Fix Payment Failure State")
    }

    @Test("A manual rename survives later refreshes")
    func manualRenameSticks() async {
        let coordinator = coordinator(prompt: "Fix the payment failure state on the checkout page.")
        let session = TerminalSessionSnapshot(
            foregroundProcessName: "claude",
            workingDirectory: URL(fileURLWithPath: "/Users/me/checkout")
        )
        await coordinator.register(TabContext(tabID: session.tabID, fallbackTitle: "checkout"))
        await coordinator.setManualTitle("Payments", for: session.tabID)

        let context = await coordinator.refresh(session)
        #expect(context.displayTitle == "Payments")
    }
}

/// What the tab is called: the project it is in.
///
/// The project travels on the snapshot rather than on an observation, because
/// which codebase a terminal is in is a fact about the pty and no provider is a
/// better witness to it than the kernel.
@Suite("Project in the context")
struct ProjectContextTests {

    private let tabID = UUID()

    private func snapshot(directory: String?, project: String?) -> TerminalSessionSnapshot {
        TerminalSessionSnapshot(
            tabID: tabID,
            shellName: "zsh",
            foregroundProcessName: "zsh",
            workingDirectory: directory.map { URL(fileURLWithPath: $0, isDirectory: true) },
            projectRoot: project.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }

    @Test("A tab inside a repository is named for the repository")
    func projectReachesTheContext() async {
        let coordinator = TabContextCoordinator(providers: [GenericProcessContextProvider()])
        let context = await coordinator.refresh(
            snapshot(directory: "/w/ocarina-terminal/Sources", project: "/w/ocarina-terminal")
        )
        #expect(context.projectTitle == "Ocarina Terminal")
        #expect(context.projectRoot?.lastPathComponent == "ocarina-terminal")
    }

    /// A `cd` out of a checkout must take the name off the tab. Every other
    /// field on the context holds its last known value, which is right for
    /// them and would be wrong here: a tab still wearing the name of the
    /// repository it left is a tab lying about where it is.
    @Test("Leaving a project clears the name rather than keeping the old one")
    func leavingClearsIt() async {
        let coordinator = TabContextCoordinator(providers: [GenericProcessContextProvider()])
        _ = await coordinator.refresh(
            snapshot(directory: "/w/checkout", project: "/w/checkout")
        )
        let home = await coordinator.refresh(snapshot(directory: "/Users/x", project: nil))
        #expect(home.projectTitle == nil)
    }

    /// A pty that cannot be read at all reports nil for everything, and that
    /// nil means "no reading" rather than "no project" — a tab must not be
    /// renamed because one poll came back empty.
    @Test("A blank reading leaves the project alone")
    func blankReadingKeepsIt() async {
        let coordinator = TabContextCoordinator(providers: [GenericProcessContextProvider()])
        _ = await coordinator.refresh(
            snapshot(directory: "/w/checkout", project: "/w/checkout")
        )
        let blank = await coordinator.refresh(
            TerminalSessionSnapshot(tabID: tabID, shellName: "zsh")
        )
        #expect(blank.projectTitle == "Checkout")
    }

    /// A working directory is not a project. Home has one and is not one, and
    /// `projectRoot` is the only field that knows the difference.
    @Test("A directory that is not a project names nothing")
    func directoryAloneIsNotAProject() async {
        let coordinator = TabContextCoordinator(providers: [GenericProcessContextProvider()])
        let context = await coordinator.refresh(snapshot(directory: "/Users/x", project: nil))
        #expect(context.workingDirectory != nil)
        #expect(context.projectTitle == nil)
    }
}
