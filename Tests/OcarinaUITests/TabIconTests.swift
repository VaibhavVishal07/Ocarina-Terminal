import AppKit
import Testing
@testable import OcarinaUI

@Suite("Tab icons")
@MainActor
struct TabIconTests {

    @Test("A shell at a prompt is not worth a picture")
    func idleShellIsBlank() {
        // Every tab in a terminal app is a terminal, so the sidebar leaves the
        // slot out rather than filling it with a picture of the obvious.
        #expect(TabIcon.symbol(for: nil) == nil)
        #expect(TabIcon.symbol(for: "") == nil)
        #expect(TabIcon.symbol(for: "zsh") == nil)
        #expect(TabIcon.symbol(for: "fish") == nil)
    }

    @Test("An agent is not worth one either")
    func agentsAreBlank() {
        // They wore their makers' marks here and it was a fourth copy of a
        // fact: the tab is named after what you asked, the dot says whether it
        // is still going, and the menu bar says that again from outside the
        // window. The name gets the width back.
        for agent in ["claude", "Claude Code", "codex", "Codex", "gemini",
                      "Gemini CLI", "opencode"] {
            #expect(TabIcon.symbol(for: agent) == nil, "\(agent) should draw nothing")
        }
    }

    @Test("An agent is still recognised, or it would draw the unknown picture")
    func agentsAreMatchedNotMissed() {
        // The prefix list is what earns an agent its empty slot. Dropped along
        // with the marks, "claude" would fall through to the gearshape every
        // unrecognised process gets — which is a picture, in the slot this went
        // to empty. This is the test that would catch that.
        #expect(TabIcon.symbol(for: "claude") != TabIcon.symbol(for: "some-custom-tool"))
    }

    @Test("A running program is distinguishable from an idle prompt")
    func unknownProcessIsNotAShell() {
        #expect(TabIcon.symbol(for: "some-custom-tool") == "gearshape")
        #expect(TabIcon.symbol(for: "vim") == "square.and.pencil")
        #expect(TabIcon.symbol(for: "git") == "arrow.triangle.branch")
        #expect(TabIcon.symbol(for: "cargo") == "hammer")
    }

    @Test("Nothing in the strip is anybody else's logo")
    func noVendorMarksAreLeft() {
        // A tab strip wearing three vendors' logos reads as a list of products
        // rather than a list of your work. The marks still exist — the landing
        // screen installs from them — they are just not in the tab any more.
        let drawn = ["claude", "codex", "gemini", "opencode", "zsh", "vim",
                     "git", "node", "some-custom-tool"]
            .compactMap { TabIcon.symbol(for: $0) }
        #expect(!drawn.isEmpty)
        // Every one of them is an SF Symbol, which is to say the system's.
        #expect(drawn.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
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
