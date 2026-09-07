import SwiftUI

/// What a tab is running, as a symbol.
///
/// The app's own mark used to sit here, which told you nothing: every tab
/// carried the same picture. The icon follows the foreground process instead,
/// so a tab running Claude Code is distinguishable from a shell at a prompt
/// across a strip of twenty.
///
/// Matching is on the naming layer's `processName`, which is a provider's
/// display name when one recognised the process (`Claude Code`, `Gemini CLI`)
/// and the raw executable otherwise (`zsh`, `vim`) — so both forms are handled.
enum TabIcon {
    struct Look {
        let symbol: String
        /// The agent's own mark, drawn instead of the symbol when there is one.
        ///
        /// So Claude wears the same burst in the tab strip as it does on the
        /// landing screen. It was a stock `sparkles`, which is the symbol every
        /// app in the world reaches for the moment anything is called AI, and
        /// which said nothing about *which* agent was running in that tab.
        let mark: AgentMark?
        let tint: Tint

        /// True when the symbol is the bare terminal — a shell at a prompt, or
        /// a tab with nothing running yet. Every tab in a terminal app is a
        /// terminal, so drawing one says nothing that the window does not
        /// already say.
        var isPlainTerminal: Bool { symbol == "terminal" && mark == nil }
    }

    /// What colour a look is, said in the theme's terms rather than in
    /// hexadecimal.
    ///
    /// The agents used to carry their makers' brand colours — Claude in
    /// Anthropic's orange, Gemini in Google's blue — and a brand colour is by
    /// definition the one colour that does not move when the window changes
    /// around it. Pick Matcha and the sidebar went green with an orange spark
    /// sitting in it. The window is wearing a theme; everything in the window
    /// wears it too.
    enum Tint: Equatable {
        /// An agent. Drawn in the theme's accent, so Matcha has a green Claude
        /// in it and Ember an orange one — and the accent is the right slot
        /// rather than a board colour because this is chrome, beside a tab
        /// name, not a lamp on the departure board.
        ///
        /// All four agents share it. Which agent is running is carried by the
        /// mark, which is a shape and readable at 11pt; what the colour says is
        /// "this tab is an agent, and the others are not", which is the thing
        /// you scan a strip of twenty tabs for.
        case agent
        /// Everything else. A tab running vim is running vim on every theme,
        /// and it is not what you are looking for in the strip.
        case neutral
    }

    /// The look worth drawing, or `nil` when it would only repeat that this is
    /// a terminal. Callers that want the symbol regardless — tests, and
    /// anywhere a slot must be filled — use `look(for:)`.
    static func meaningfulLook(for processName: String?) -> Look? {
        let look = look(for: processName)
        return look.isPlainTerminal ? nil : look
    }

    static func look(for processName: String?) -> Look {
        guard let name = processName?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            // No process yet: the tab is a shell waiting at a prompt.
            return Look(symbol: "terminal", mark: nil, tint: .neutral)
        }

        // Agents are matched on a prefix so the display name and the executable
        // both land: "Claude Code" and "claude".
        if name.hasPrefix("claude") {
            return Look(symbol: "sparkles", mark: .burst, tint: .agent)
        }
        if name.hasPrefix("codex") {
            return Look(symbol: "chevron.left.forwardslash.chevron.right",
                        mark: .hexagon, tint: .agent)
        }
        if name.hasPrefix("gemini") {
            return Look(symbol: "diamond", mark: .spark, tint: .agent)
        }
        // No mark of its own yet, but an agent all the same: it takes the
        // agent tint and keeps its symbol.
        if name.hasPrefix("opencode") {
            return Look(symbol: "curlybraces", mark: nil, tint: .agent)
        }

        switch name {
        case "zsh", "bash", "sh", "fish", "dash", "tcsh", "ksh", "nu":
            return Look(symbol: "terminal", mark: nil, tint: .neutral)
        case "vim", "nvim", "vi", "nano", "emacs", "hx", "helix", "micro":
            return Look(symbol: "square.and.pencil", mark: nil, tint: .neutral)
        case "git", "lazygit", "tig", "gh":
            return Look(symbol: "arrow.triangle.branch", mark: nil, tint: .neutral)
        case "ssh", "mosh", "sftp", "scp":
            return Look(symbol: "network", mark: nil, tint: .neutral)
        case "docker", "podman", "kubectl", "k9s":
            return Look(symbol: "shippingbox", mark: nil, tint: .neutral)
        case "node", "npm", "npx", "pnpm", "yarn", "bun", "deno":
            return Look(symbol: "hexagon", mark: nil, tint: .neutral)
        case "python", "python3", "ipython", "uv", "pip", "pip3", "ruby", "irb":
            return Look(symbol: "chevron.left.forwardslash.chevron.right", mark: nil, tint: .neutral)
        case "make", "cargo", "swift", "go", "gradle", "mvn", "xcodebuild", "cmake":
            return Look(symbol: "hammer", mark: nil, tint: .neutral)
        case "top", "htop", "btop", "btm", "glances":
            return Look(symbol: "chart.bar", mark: nil, tint: .neutral)
        case "man", "less", "more", "bat":
            return Look(symbol: "book", mark: nil, tint: .neutral)
        default:
            // Something is running that we do not recognise — which is still
            // worth distinguishing from an idle prompt.
            return Look(symbol: "gearshape", mark: nil, tint: .neutral)
        }
    }
}
