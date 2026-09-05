import Foundation
import Testing
@testable import OcarinaUI

@Suite("Explaining a failure")
struct ErrorHelpTests {

    @Test("With no agent installed there is nothing to type")
    func noAgent() {
        #expect(ErrorHelp.command(explaining: "boom", agent: nil) == nil)
    }

    @Test("The command asks about a file, not about pasted output")
    func excerptGoesToAFile() throws {
        // Terminal output is full of quotes, newlines and escapes. Inlining it
        // into a shell command is how a failed build becomes a second problem.
        let nasty = "error: unexpected '\"' near `rm -rf /`\nline 2\n$(whoami)"
        let command = try #require(ErrorHelp.command(explaining: nasty, agent: "claude"))

        #expect(command.hasPrefix("claude "))
        #expect(command.contains("\n") == false, "a newline would submit the command early")
        #expect(command.contains("$(whoami)") == false, "output must not reach the command line")
        #expect(command.contains(ErrorHelp.excerptURL.path))

        let written = try String(contentsOf: ErrorHelp.excerptURL, encoding: .utf8)
        #expect(written == nasty)
    }

    @Test("A quote in the question cannot break out of the quoting")
    func quoting() {
        #expect(ErrorHelp.shellQuoted("it's fine") == "'it'\\''s fine'")
        #expect(ErrorHelp.shellQuoted("plain") == "'plain'")
    }

    @Test("An agent is found on PATH, and absence is reported honestly")
    func findsAgent() {
        #expect(ErrorHelp.installedAgent(path: "", extraDirectories: []) == nil)
        // And it does look where the native Claude installer actually puts
        // things, which is not always on PATH.
        #expect(ErrorHelp.defaultExtraDirectories().contains { $0.hasSuffix("/.local/bin") })
    }
}
