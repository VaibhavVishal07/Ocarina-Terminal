import Foundation

/// What a tab is running, as a symbol.
///
/// The app's own mark used to sit here, which told you nothing: every tab
/// carried the same picture. The icon follows the foreground process instead,
/// so a tab holding a file open in vim is distinguishable from one part-way
/// through a build across a strip of twenty.
///
/// ## Agents draw nothing
///
/// They wore their makers' marks in this slot for a release — Claude's burst,
/// Codex's hexagon, Gemini's spark, each in the theme's accent so the strip
/// could be scanned for which of these is an agent. Every part of that was
/// true and none of it was needed. An agent tab is *named after what you asked
/// it*, which is the only thing in the strip that says anything you did not
/// already know; the dot beside the name says whether it is still going; and
/// the menu bar says that again from outside the window. The mark was a fourth
/// copy of a fact, sitting in the one part of the row that costs the name its
/// width — and the name is the part you are reading.
///
/// It was also the only picture in the app that belonged to somebody else. A
/// tab strip wearing three vendors' logos reads as a list of products rather
/// than a list of your work.
///
/// What is left is the case an icon was always for: a tab doing something you
/// did not start on purpose in this window and would not guess from the name.
///
/// Matching is on the naming layer's `processName`, which is a provider's
/// display name when one recognised the process (`Claude Code`, `Gemini CLI`)
/// and the raw executable otherwise (`zsh`, `vim`) — so both forms are handled.
enum TabIcon {

    /// The symbol worth drawing, or nil when there is nothing worth saying.
    ///
    /// Nil covers three cases that look unrelated and are the same one: a tab
    /// with nothing running yet, a shell at a prompt — every tab in a terminal
    /// app is a terminal, so a picture of one says nothing the window does not
    /// already — and an agent, for the reasons above. In all three the slot is
    /// left out rather than filled, and the width goes to the name.
    static func symbol(for processName: String?) -> String? {
        guard let name = processName?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            // No process yet: the tab is a shell waiting at a prompt.
            return nil
        }

        if agents.contains(where: name.hasPrefix) { return nil }

        switch name {
        case "zsh", "bash", "sh", "fish", "dash", "tcsh", "ksh", "nu":
            return nil
        case "vim", "nvim", "vi", "nano", "emacs", "hx", "helix", "micro":
            return "square.and.pencil"
        case "git", "lazygit", "tig", "gh":
            return "arrow.triangle.branch"
        case "ssh", "mosh", "sftp", "scp":
            return "network"
        case "docker", "podman", "kubectl", "k9s":
            return "shippingbox"
        case "node", "npm", "npx", "pnpm", "yarn", "bun", "deno":
            return "hexagon"
        case "python", "python3", "ipython", "uv", "pip", "pip3", "ruby", "irb":
            return "chevron.left.forwardslash.chevron.right"
        case "make", "cargo", "swift", "go", "gradle", "mvn", "xcodebuild", "cmake":
            return "hammer"
        case "top", "htop", "btop", "btm", "glances":
            return "chart.bar"
        case "man", "less", "more", "bat":
            return "book"
        default:
            // Something is running that we do not recognise — which is still
            // worth distinguishing from an idle prompt.
            return "gearshape"
        }
    }

    /// Prefixes that mean an agent is in front of this tab.
    ///
    /// Kept, rather than deleted along with the marks they used to pick. What
    /// these names earn now is *no* icon, and an agent has to be recognised to
    /// earn that: without this list `claude` falls through to the
    /// unrecognised-process `gearshape`, which is a picture — in the slot this
    /// change went to empty.
    ///
    /// Prefixes so the display name and the executable both land: `Claude
    /// Code` and `claude`.
    private static let agents = ["claude", "codex", "gemini", "opencode"]
}
