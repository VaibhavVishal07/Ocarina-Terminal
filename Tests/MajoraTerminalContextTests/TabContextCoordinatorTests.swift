import Foundation
import Testing
@testable import MajoraTerminalContext

private struct StubTranscriptSource: LLMTranscriptSource {
    let prompt: String?
    func latestHumanPrompt(forWorkingDirectory directory: URL?) async -> String? { prompt }
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
