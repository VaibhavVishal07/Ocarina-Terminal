import Testing
@testable import OcarinaUI

@Suite("Tab icons")
@MainActor
struct TabIconTests {

    @Test("A tab with nothing running shows a terminal")
    func idleShell() {
        #expect(TabIcon.look(for: nil).symbol == "terminal")
        #expect(TabIcon.look(for: "zsh").symbol == "terminal")
    }

    @Test("Agents are recognised by display name and by executable")
    func agentsAreRecognised() {
        // The naming layer hands over a provider's display name when one
        // matched, and the bare executable when none did.
        #expect(TabIcon.look(for: "Claude Code").symbol == "sparkles")
        #expect(TabIcon.look(for: "claude").symbol == "sparkles")
        #expect(TabIcon.look(for: "Gemini CLI").symbol == TabIcon.look(for: "gemini").symbol)
        #expect(TabIcon.look(for: "Codex").symbol == TabIcon.look(for: "codex").symbol)
    }

    @Test("Each agent gets its own symbol")
    func agentsAreDistinct() {
        let symbols = ["claude", "codex", "gemini", "opencode"].map {
            TabIcon.look(for: $0).symbol
        }
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("An agent wears the theme, and everything else stays out of the way")
    func agentsTakeTheTheme() {
        // A brand colour is by definition the one colour that does not move
        // when the window changes around it: Claude in Anthropic's orange sat
        // in a green sidebar the moment somebody picked Matcha. `TabIcon` names
        // a slot and the theme says what colour that is.
        for agent in ["claude", "Claude Code", "codex", "gemini", "opencode"] {
            #expect(TabIcon.look(for: agent).tint == .agent, "\(agent) should wear the theme")
        }
        for other in ["zsh", "vim", "git", "some-custom-tool"] {
            #expect(TabIcon.look(for: other).tint == .neutral)
        }
    }

    @Test("Each agent is told apart by its mark, not by its colour")
    func agentMarksAreDistinct() {
        // They all share the accent now, so the shape is the whole of the
        // distinction — two agents wearing the same mark would be two tabs
        // that look identical in the strip.
        let marks = ["claude", "codex", "gemini"].compactMap { TabIcon.look(for: $0).mark }
        #expect(marks.count == 3)
        #expect(Set(marks).count == 3)

        // And it is the same mark the landing screen draws, so a tool does not
        // change shape between the screen you installed it from and the tab it
        // runs in.
        #expect(TabIcon.look(for: "claude").mark == AgentCatalog.all.first { $0.id == "claude-code" }?.mark)
        #expect(TabIcon.look(for: "gemini").mark == AgentCatalog.all.first { $0.id == "gemini-cli" }?.mark)
        #expect(TabIcon.look(for: "codex").mark == AgentCatalog.all.first { $0.id == "codex-cli" }?.mark)
    }

    @Test("A shell's terminal symbol is not worth drawing, a program's is")
    func plainTerminalIsDropped() {
        // Every tab in a terminal app is a terminal, so the sidebar leaves the
        // slot out rather than filling it with a picture of the obvious.
        #expect(TabIcon.look(for: nil).isPlainTerminal)
        #expect(TabIcon.look(for: "zsh").isPlainTerminal)
        #expect(TabIcon.meaningfulLook(for: nil) == nil)
        #expect(TabIcon.meaningfulLook(for: "fish") == nil)

        // Anything that says more than "terminal" survives.
        #expect(TabIcon.meaningfulLook(for: "claude")?.symbol == "sparkles")
        #expect(TabIcon.meaningfulLook(for: "vim")?.symbol == "square.and.pencil")
        #expect(TabIcon.meaningfulLook(for: "some-custom-tool") != nil)
    }

    @Test("A running program is distinguishable from an idle prompt")
    func unknownProcessIsNotAShell() {
        #expect(TabIcon.look(for: "some-custom-tool").symbol != "terminal")
        #expect(TabIcon.look(for: "vim").symbol == "square.and.pencil")
        #expect(TabIcon.look(for: "git").symbol == "arrow.triangle.branch")
    }
}

@Suite("Tab titles")
@MainActor
struct TabTitleTests {

    @Test("A short title is left alone")
    func shortTitleUntouched() {
        #expect("Build the parser".ellipsised(to: 24) == "Build the parser")
        // Exactly at the cap is not over it.
        #expect(String(repeating: "a", count: 24).ellipsised(to: 24).count == 24)
    }

    @Test("A long title is cut with an ellipsis")
    func longTitleIsCut() {
        let long = "Refactoring the terminal naming subsystem"
        let cut = long.ellipsised(to: 24)

        #expect(cut.hasSuffix("…"))
        // The ellipsis counts toward the cap: nothing renders wider than 24.
        #expect(cut.count == 24)
        #expect(long.hasPrefix(String(cut.dropLast())))
    }

    @Test("A cut does not leave a dangling space before the ellipsis")
    func noDanglingSpace() {
        // "Generate the report now" cut at 24 would land mid-space.
        let cut = "Deploying to staging now please".ellipsised(to: 24)
        #expect(!cut.dropLast().hasSuffix(" "))
    }
}
