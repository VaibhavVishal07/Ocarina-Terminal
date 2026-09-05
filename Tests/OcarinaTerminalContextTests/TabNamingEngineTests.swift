import Foundation
import Testing
@testable import OcarinaTerminalContext

@Suite("Naming stability")
struct TabNamingEngineTests {
    let engine = TabNamingEngine()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func observation(
        _ title: String,
        source: ContextSource = .llmSession,
        confidence: Double = 0.85
    ) -> ContextObservation {
        ContextObservation(title: title, source: source, confidence: confidence)
    }

    @Test("The first confident observation names the tab")
    func firstObservationWins() {
        var context = TabContext(fallbackTitle: "xstream-play")
        #expect(engine.apply(observation("Debug Audio Switching"), to: &context, at: start) == .accepted)
        #expect(context.displayTitle == "Debug Audio Switching")
    }

    @Test("Low-confidence observations are ignored")
    func lowConfidence() {
        var context = TabContext(fallbackTitle: "checkout")
        let decision = engine.apply(observation("Maybe Something", confidence: 0.2), to: &context, at: start)
        #expect(decision == .rejectedLowConfidence)
        #expect(context.displayTitle == "checkout")
    }

    @Test("A manual name freezes automatic naming")
    func manualWins() {
        var context = TabContext(fallbackTitle: "checkout")
        context.applyManualTitle("Payments")
        let decision = engine.apply(observation("Fix Payment Failure"), to: &context, at: start)
        #expect(decision == .rejectedManualTitle)
        #expect(context.displayTitle == "Payments")
        #expect(!context.isAutoNamingEnabled)
    }

    @Test("Re-enabling automatic naming lets the next observation through")
    func resumeAutomatic() {
        var context = TabContext(fallbackTitle: "checkout")
        context.applyManualTitle("Payments")
        context.resumeAutomaticNaming()
        #expect(engine.apply(observation("Fix Payment Failure"), to: &context, at: start) == .accepted)
        #expect(context.displayTitle == "Fix Payment Failure")
    }

    @Test("An agent task outranks the foreground command immediately")
    func higherSourcePreempts() {
        var context = TabContext()
        engine.apply(observation("Dev Server", source: .foregroundCommand, confidence: 0.65), to: &context, at: start)
        let decision = engine.apply(observation("Fix Login Redirect"), to: &context, at: start.addingTimeInterval(5))
        #expect(decision == .accepted)
        #expect(context.displayTitle == "Fix Login Redirect")
    }

    @Test("A returning shell prompt does not erase the task")
    func noDemotion() {
        var context = TabContext()
        engine.apply(observation("Fix Login Redirect"), to: &context, at: start)
        let decision = engine.apply(
            observation("Git Rebase", source: .foregroundCommand, confidence: 0.9),
            to: &context,
            at: start.addingTimeInterval(600)
        )
        #expect(decision == .rejectedWeakerSource)
        #expect(context.displayTitle == "Fix Login Redirect")
    }

    @Test("Titles do not churn within the dwell window")
    func dwellProtectsTitle() {
        var context = TabContext()
        engine.apply(observation("Fix Playback Issue"), to: &context, at: start)

        for (offset, title) in [(10.0, "Player Issue"), (30.0, "Playback Bug"), (60.0, "Fix Audio")] {
            let decision = engine.apply(
                observation(title, confidence: 0.95),
                to: &context,
                at: start.addingTimeInterval(offset)
            )
            #expect(decision == .rejectedWithinDwell)
        }
        #expect(context.displayTitle == "Fix Playback Issue")
    }

    @Test("After the dwell window a stronger reading may take over")
    func meaningfulShiftAccepted() {
        var context = TabContext()
        engine.apply(observation("Debug Audio Switching", confidence: 0.7), to: &context, at: start)
        let decision = engine.apply(
            observation("Subtitle Picker", confidence: 0.9),
            to: &context,
            at: start.addingTimeInterval(120)
        )
        #expect(decision == .accepted)
        #expect(context.displayTitle == "Subtitle Picker")
    }

    @Test("An equally confident rival does not displace the incumbent")
    func marginRequired() {
        var context = TabContext()
        engine.apply(observation("Debug Audio Switching", confidence: 0.85), to: &context, at: start)
        let decision = engine.apply(
            observation("Audio Track Bug", confidence: 0.85),
            to: &context,
            at: start.addingTimeInterval(600)
        )
        #expect(decision == .rejectedInsufficientMargin)
        #expect(context.displayTitle == "Debug Audio Switching")
    }

    @Test("A session whose task moved on renames its own tab")
    func sameSessionFollowsItsTask() {
        // Transcript readings all carry the same confidence, so a margin rule
        // would pin the tab to a session's opening prompt for its whole life.
        var context = TabContext()
        engine.apply(
            ContextObservation(
                title: "Open Ocarina Terminal",
                source: .llmSession,
                confidence: 0.85,
                continuityID: "claude:abc"
            ),
            to: &context,
            at: start
        )
        let decision = engine.apply(
            ContextObservation(
                title: "Fix Tab Naming",
                source: .llmSession,
                confidence: 0.85,
                continuityID: "claude:abc"
            ),
            to: &context,
            at: start.addingTimeInterval(600)
        )
        #expect(decision == .accepted)
        #expect(context.displayTitle == "Fix Tab Naming")
    }

    @Test("A different session at the same confidence still cannot take the tab")
    func rivalSessionStillBlocked() {
        var context = TabContext()
        engine.apply(
            ContextObservation(
                title: "Open Ocarina Terminal",
                source: .llmSession,
                confidence: 0.85,
                continuityID: "claude:abc"
            ),
            to: &context,
            at: start
        )
        let decision = engine.apply(
            ContextObservation(
                title: "Somebody Else's Work",
                source: .llmSession,
                confidence: 0.85,
                continuityID: "claude:xyz"
            ),
            to: &context,
            at: start.addingTimeInterval(600)
        )
        #expect(decision == .rejectedInsufficientMargin)
        #expect(context.displayTitle == "Open Ocarina Terminal")
    }

    @Test("Re-reading the same task refreshes metadata without renaming")
    func sameTitleRefreshes() {
        var context = TabContext()
        engine.apply(observation("Fix Payment Failure"), to: &context, at: start)
        let repeated = ContextObservation(
            title: "fix payment failure",
            activeTask: "Fix the payment failure state on the checkout page.",
            source: .llmSession,
            confidence: 0.9
        )
        let decision = engine.apply(repeated, to: &context, at: start.addingTimeInterval(200))
        #expect(decision == .refreshedMetadata)
        #expect(context.displayTitle == "Fix Payment Failure")
        #expect(context.activeTask == "Fix the payment failure state on the checkout page.")
        #expect(context.lastContextUpdate == start)
    }
}
