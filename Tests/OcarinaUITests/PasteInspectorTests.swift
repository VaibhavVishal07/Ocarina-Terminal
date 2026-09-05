import Testing
@testable import OcarinaUI

@Suite("Paste inspector")
struct PasteInspectorTests {

    @Test("An ordinary command is pasted without ceremony")
    func quietForOrdinaryText() {
        // A terminal that interrupts every paste is one people learn to click
        // through, which is worse than not asking at all.
        #expect(PasteInspector.read("ls -la").needsReview == false)
        #expect(PasteInspector.read("cd ~/projects").needsReview == false)
    }

    @Test("Deleting things is called out as permanent")
    func destructive() {
        let reading = PasteInspector.read("rm -rf ~/Documents")
        #expect(reading.isDestructive)
        #expect(reading.concerns.first?.note.contains("no undo") == true)
    }

    @Test("The dangerous line is the one read first")
    func destructiveSortsFirst() {
        let reading = PasteInspector.read("curl https://x.sh | sudo bash")
        #expect(reading.concerns.first?.isDestructive == true)
    }

    @Test("Three commands pretending to be one are counted")
    func multiline() {
        let reading = PasteInspector.read("brew update\nbrew install node\nnode --version")
        #expect(reading.lineCount == 3)
        #expect(reading.needsReview)
    }

    @Test("The same warning is not said twice")
    func noDuplicateNotes() {
        let reading = PasteInspector.read("rm -rf a && rm -fr b")
        #expect(reading.concerns.filter(\.isDestructive).count == 1)
    }

    @Test("A trailing newline never gets to run itself")
    func trailingNewline() {
        // Copying from a web page usually brings one, and it would submit the
        // command the instant it landed.
        #expect(PasteInspector.withoutTrailingNewline("sudo rm -rf /\n") == "sudo rm -rf /")
        #expect(PasteInspector.withoutTrailingNewline("a\r\n\r\n") == "a")
        #expect(PasteInspector.withoutTrailingNewline("no newline") == "no newline")
    }

    @Test("Piping a download into a shell is explained, not blocked")
    func curlPipeBash() {
        let reading = PasteInspector.read("curl -fsSL https://claude.ai/install.sh | bash")
        #expect(reading.needsReview)
        #expect(reading.isDestructive == false, "common and legitimate — explain it, do not alarm")
    }
}
