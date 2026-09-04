import Foundation
import Testing
@testable import MajoraTerminalContext

@Suite("OSC title parsing")
struct OSCTitleParserTests {

    private func titles(from text: String) -> [String] {
        var parser = OSCTitleParser()
        return parser.consume(Array(text.utf8))
    }

    @Test("Title sequences are recognised for codes 0, 1 and 2")
    func titleCodes() {
        #expect(titles(from: "\u{1B}]0;Fix Payment Flow\u{07}") == ["Fix Payment Flow"])
        #expect(titles(from: "\u{1B}]1;Icon\u{07}") == ["Icon"])
        #expect(titles(from: "\u{1B}]2;Window\u{07}") == ["Window"])
    }

    @Test("String terminator ends a title as well as BEL")
    func stringTerminator() {
        #expect(titles(from: "\u{1B}]2;Build\u{1B}\\") == ["Build"])
    }

    @Test("A sequence split across pty reads still resolves")
    func splitAcrossChunks() {
        var parser = OSCTitleParser()
        #expect(parser.consume(Array("output\u{1B}]0;Debug Sea".utf8)).isEmpty)
        #expect(parser.consume(Array("rch API\u{07}more output".utf8)) == ["Debug Search API"])
    }

    @Test("Non-title OSC codes are ignored")
    func otherOSCCodes() {
        // OSC 7 carries the working directory, not a title.
        #expect(titles(from: "\u{1B}]7;file://host/Users/me\u{07}").isEmpty)
        #expect(titles(from: "\u{1B}]133;A\u{07}").isEmpty)
    }

    @Test("Ordinary output and CSI sequences produce nothing")
    func ordinaryOutput() {
        #expect(titles(from: "hello world\n").isEmpty)
        #expect(titles(from: "\u{1B}[1;31mred\u{1B}[0m").isEmpty)
    }

    @Test("Every title in a chunk is reported, in order")
    func multipleTitles() {
        #expect(titles(from: "\u{1B}]0;First\u{07}text\u{1B}]2;Second\u{07}") == ["First", "Second"])
    }

    @Test("An unterminated payload is bounded rather than buffered forever")
    func runawayPayload() {
        let flood = String(repeating: "x", count: OSCTitleParser.maximumTitleLength + 50)
        var parser = OSCTitleParser()
        #expect(parser.consume(Array("\u{1B}]0;\(flood)".utf8)).isEmpty)
        // The parser recovered and still reads the next real title.
        #expect(parser.consume(Array("\u{07}\u{1B}]0;Recovered\u{07}".utf8)) == ["Recovered"])
    }

    @Test("Empty titles are dropped")
    func emptyTitle() {
        #expect(titles(from: "\u{1B}]0;\u{07}").isEmpty)
    }
}
