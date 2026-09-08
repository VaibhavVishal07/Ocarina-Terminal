import Foundation
import Testing
@testable import OcarinaTerminalContext
@testable import OcarinaUI

/// The naming that the tab strip and the task panel now share.
@Suite("Summarised names")
@MainActor
struct TaskSummariserTests {

    /// A cache of its own, so what the app has asked about cannot decide
    /// whether a test passes.
    private func summariser() -> TaskSummariser {
        TaskSummariser(cache: FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-titles-\(UUID().uuidString)")
            .appendingPathComponent("prompt-titles.json"))
    }

    @Test("The same question asked twice is one entry in the cache")
    func keyIgnoresLayout() {
        // Keyed by the words, so a prompt read from the tab's transcript and
        // the same prompt read for the panel are not asked about twice — and
        // so a title survives the transcript uuid it was first found under.
        let key = TaskSummariser.key(for: "Fix the payment flow")
        #expect(TaskSummariser.key(for: "  Fix the\n payment   flow  ") == key)
        #expect(TaskSummariser.key(for: "Fix the checkout flow") != key)
    }
}
