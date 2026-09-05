import Foundation
import Testing
@testable import MajoraTerminalContext

@Suite("Shell integration")
struct ShellIntegrationTests {

    @Test("zsh is pointed at generated config that defers to the user's own")
    func zshEnvironment() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("majora-si-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let environment = ShellIntegration.environment(
            forShell: "/bin/zsh",
            base: ["HOME": "/Users/me", "ZDOTDIR": "/Users/me/.config/zsh"],
            supportDirectory: support
        )

        #expect(environment["ZDOTDIR"] == support.path)
        // The user's own config location is preserved for the snippet to source.
        #expect(environment["MAJORA_USER_ZDOTDIR"] == "/Users/me/.config/zsh")

        for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            let contents = try String(contentsOf: support.appendingPathComponent(name), encoding: .utf8)
            #expect(contents.contains("MAJORA_USER_ZDOTDIR/\(name)"))
        }

        let zshrc = try String(contentsOf: support.appendingPathComponent(".zshrc"), encoding: .utf8)
        #expect(zshrc.contains("add-zsh-hook preexec _majora_preexec"))
        #expect(zshrc.contains("add-zsh-hook precmd _majora_precmd"))
        // The user's config must not be left looking at Majora's directory.
        #expect(zshrc.contains(#"ZDOTDIR="$MAJORA_USER_ZDOTDIR""#))
    }

    @Test("Without ZDOTDIR set, the user's home is used")
    func defaultsToHome() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("majora-si-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let environment = ShellIntegration.environment(
            forShell: "/bin/zsh",
            base: ["HOME": "/Users/me"],
            supportDirectory: support
        )
        #expect(environment["MAJORA_USER_ZDOTDIR"] == "/Users/me")
    }

    @Test("Unsupported shells are left completely alone")
    func otherShellsUntouched() {
        let base = ["HOME": "/Users/me", "SHELL": "/bin/bash"]
        #expect(ShellIntegration.environment(forShell: "/bin/bash", base: base) == base)
        #expect(ShellIntegration.environment(forShell: "/bin/fish", base: base) == base)
    }
}
