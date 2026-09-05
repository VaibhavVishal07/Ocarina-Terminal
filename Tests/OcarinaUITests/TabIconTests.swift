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
