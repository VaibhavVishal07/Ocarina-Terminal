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
        let tint: Color

        /// True when the symbol is the bare terminal — a shell at a prompt, or
        /// a tab with nothing running yet. Every tab in a terminal app is a
        /// terminal, so drawing one says nothing that the window does not
        /// already say.
        var isPlainTerminal: Bool { symbol == "terminal" }
    }

    /// The look worth drawing, or `nil` when it would only repeat that this is
    /// a terminal. Callers that want the symbol regardless — tests, and
    /// anywhere a slot must be filled — use `look(for:)`.
    static func meaningfulLook(for processName: String?) -> Look? {
        let look = look(for: processName)
        return look.isPlainTerminal ? nil : look
    }

    private static let neutral = Color.secondary

    static func look(for processName: String?) -> Look {
        guard let name = processName?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            // No process yet: the tab is a shell waiting at a prompt.
            return Look(symbol: "terminal", tint: neutral)
        }

        // Agents are matched on a prefix so the display name and the executable
        // both land: "Claude Code" and "claude".
        if name.hasPrefix("claude") {
            return Look(symbol: "sparkles", tint: Color(red: 0.85, green: 0.47, blue: 0.34))
        }
        if name.hasPrefix("codex") {
            return Look(symbol: "chevron.left.forwardslash.chevron.right",
                        tint: Color(red: 0.36, green: 0.75, blue: 0.52))
        }
        if name.hasPrefix("gemini") {
            return Look(symbol: "diamond", tint: Color(red: 0.45, green: 0.60, blue: 0.95))
        }
        if name.hasPrefix("opencode") {
            return Look(symbol: "curlybraces", tint: Color(red: 0.35, green: 0.76, blue: 0.78))
        }

        switch name {
        case "zsh", "bash", "sh", "fish", "dash", "tcsh", "ksh", "nu":
            return Look(symbol: "terminal", tint: neutral)
        case "vim", "nvim", "vi", "nano", "emacs", "hx", "helix", "micro":
            return Look(symbol: "square.and.pencil", tint: neutral)
        case "git", "lazygit", "tig", "gh":
            return Look(symbol: "arrow.triangle.branch", tint: neutral)
        case "ssh", "mosh", "sftp", "scp":
            return Look(symbol: "network", tint: neutral)
        case "docker", "podman", "kubectl", "k9s":
            return Look(symbol: "shippingbox", tint: neutral)
        case "node", "npm", "npx", "pnpm", "yarn", "bun", "deno":
            return Look(symbol: "hexagon", tint: neutral)
        case "python", "python3", "ipython", "uv", "pip", "pip3", "ruby", "irb":
            return Look(symbol: "chevron.left.forwardslash.chevron.right", tint: neutral)
        case "make", "cargo", "swift", "go", "gradle", "mvn", "xcodebuild", "cmake":
            return Look(symbol: "hammer", tint: neutral)
        case "top", "htop", "btop", "btm", "glances":
            return Look(symbol: "chart.bar", tint: neutral)
        case "man", "less", "more", "bat":
            return Look(symbol: "book", tint: neutral)
        default:
            // Something is running that we do not recognise — which is still
            // worth distinguishing from an idle prompt.
            return Look(symbol: "gearshape", tint: neutral)
        }
    }
}
