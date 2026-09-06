import Foundation
import Testing
@testable import OcarinaTerminalContext

@Suite("Token usage")
struct TokenUsageTests {

    private func sample(_ minutesAgo: Int, _ tokens: Int, from base: Date) -> TokenUsageSource.Sample {
        TokenUsageSource.Sample(at: base.addingTimeInterval(-Double(minutesAgo) * 60), tokens: tokens)
    }

    @Test("A response costs what was sent and what came back, counted once")
    func tokensAreCountedOnce() {
        // Cache reads are the same tokens being read back again. Counting them
        // charges a long conversation for its whole context on every turn.
        let usage: [String: Any] = [
            "input_tokens": 2,
            "cache_creation_input_tokens": 509,
            "cache_read_input_tokens": 198_783,
            "output_tokens": 185
        ]
        #expect(TokenUsageSource.tokens(in: usage) == 696)
    }

    @Test("Missing fields are zero, not a crash")
    func partialUsage() {
        #expect(TokenUsageSource.tokens(in: ["output_tokens": 10]) == 10)
        #expect(TokenUsageSource.tokens(in: [:]) == 0)
    }

    @Test("The window is the five hours from the request that opened it")
    func windowFromFirstRequest() throws {
        let now = Date()
        let samples = [
            sample(200, 1_000, from: now),   // 3h20m ago — opens the window
            sample(100, 2_000, from: now),
            sample(5, 3_000, from: now)
        ]
        let window = try #require(TokenUsageSource.window(from: samples, now: now))
        #expect(window.tokens == 6_000)
        #expect(window.startedAt == samples[0].at)
        #expect(window.resetsAt == samples[0].at.addingTimeInterval(5 * 3600))
    }

    @Test("A request after the window lapsed opens the next one")
    func lapsedWindowStartsAgain() throws {
        let now = Date()
        let samples = [
            sample(560, 9_000, from: now),   // 9h20m ago, in a window long gone
            sample(500, 9_000, from: now),
            sample(30, 1_500, from: now)     // this one opened the current block
        ]
        let window = try #require(TokenUsageSource.window(from: samples, now: now))
        // Only the request inside the live block counts against it.
        #expect(window.tokens == 1_500)
        #expect(window.startedAt == samples[2].at)
    }

    @Test("Nothing spent in a live window is nothing to report")
    func nothingRecent() {
        let now = Date()
        // Both of these are inside one block, and that block ended hours ago.
        let samples = [sample(700, 5_000, from: now), sample(660, 5_000, from: now)]
        #expect(TokenUsageSource.window(from: samples, now: now) == nil)
        #expect(TokenUsageSource.window(from: [], now: now) == nil)
    }

    @Test("The bar fills with the clock, from nothing to full")
    func elapsedFraction() {
        let start = Date()
        let window = UsageWindow(
            tokens: 1,
            startedAt: start,
            resetsAt: start.addingTimeInterval(5 * 3600)
        )
        #expect(window.elapsedFraction(at: start) == 0)
        #expect(abs(window.elapsedFraction(at: start.addingTimeInterval(2.5 * 3600)) - 0.5) < 0.001)
        // Past the end it stops at full rather than running off the card.
        #expect(window.elapsedFraction(at: start.addingTimeInterval(9 * 3600)) == 1)
    }

    @Test("Samples are read from a transcript's assistant turns")
    func readsATranscript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stamp = ISO8601DateFormatter.transcript().string(from: Date())
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"go"}}"#,
            #"{"type":"assistant","timestamp":"\#(stamp)","message":{"usage":{"input_tokens":5,"cache_creation_input_tokens":10,"cache_read_input_tokens":900,"output_tokens":20}}}"#
        ]
        let transcript = directory.appendingPathComponent("session.jsonl")
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let samples = TokenUsageSource.samples(
            in: transcript,
            since: Date().addingTimeInterval(-3600)
        )
        #expect(samples.count == 1)
        #expect(samples.first?.tokens == 35)
    }

    @Test("A transcript that has grown is read from where the last read stopped")
    func incrementalRead() async throws {
        // The transcript you are talking to is rewritten every few seconds, so
        // re-reading its whole window on every poll re-reads the same
        // megabytes to find the two lines that are new. The incremental path
        // has to agree with a full rescan exactly, or the meter is quietly
        // wrong in a way nobody would notice until the number looked odd.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-usage-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("-Users-me-project", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clock = ISO8601DateFormatter.transcript()
        func record(_ minutesAgo: Int, _ output: Int) -> String {
            let stamp = clock.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
            return #"{"type":"assistant","timestamp":"\#(stamp)","message":{"usage":{"input_tokens":1,"output_tokens":\#(output)}}}"#
        }

        let transcript = directory.appendingPathComponent("session.jsonl")
        try (record(30, 100) + "\n" + record(20, 200) + "\n")
            .write(to: transcript, atomically: true, encoding: .utf8)

        let meter = TokenUsageMeter(source: TokenUsageSource(root: root))
        let first = try #require(await meter.read())
        #expect(first.tokens == 302)

        // Append, the way an agent does.
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((record(5, 500) + "\n").utf8))
        try handle.close()

        let second = try #require(await meter.read())
        #expect(second.tokens == 803)

        // And a meter that has never seen the file must reach the same number.
        let fresh = TokenUsageMeter(source: TokenUsageSource(root: root))
        #expect(await fresh.read()?.tokens == second.tokens)
    }

    @Test("A transcript that shrank is read again from scratch")
    func truncatedTranscript() async throws {
        // Shorter than last time means it is not the same file any more —
        // rotated, truncated, replaced — and reading forward from an offset
        // into the middle of it would return nonsense.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-usage-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("-Users-me-project", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clock = ISO8601DateFormatter.transcript()
        func record(_ minutesAgo: Int, _ output: Int) -> String {
            let stamp = clock.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
            return #"{"type":"assistant","timestamp":"\#(stamp)","message":{"usage":{"output_tokens":\#(output)}}}"#
        }

        let transcript = directory.appendingPathComponent("session.jsonl")
        try (record(30, 100) + "\n" + record(20, 200) + "\n")
            .write(to: transcript, atomically: true, encoding: .utf8)

        let meter = TokenUsageMeter(source: TokenUsageSource(root: root))
        #expect(await meter.read()?.tokens == 300)

        try (record(10, 700) + "\n").write(to: transcript, atomically: true, encoding: .utf8)
        #expect(await meter.read()?.tokens == 700)
    }

}
