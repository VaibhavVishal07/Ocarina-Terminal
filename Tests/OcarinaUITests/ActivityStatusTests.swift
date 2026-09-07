import Foundation
import OcarinaTerminalContext
import Testing
@testable import OcarinaUI

@MainActor
@Suite("Menu bar status")
struct ActivityStatusTests {

    private let speech = Theme.Speech(
        working: "Steeping",
        done: "Steeped through",
        stopped: "It went bitter",
        clear: "The cup is empty",
        blurb: "Green, and in no hurry about it."
    )

    @Test("Each state is said in the theme's own words")
    func statesSpeakTheTheme() {
        #expect(ActivityStatusItem.line(for: .running, speech: speech) == "Steeping")
        #expect(ActivityStatusItem.line(for: .succeeded, speech: speech) == "Steeped through")
        #expect(ActivityStatusItem.line(for: .idle, speech: speech) == "The cup is empty")
    }

    @Test("The strip names the app and the state, in every theme")
    func stripNamesTheApp() {
        // The menu bar is read from outside Ocarina, so it says which app is
        // talking. It is also the same four words in all fourteen themes:
        // Steel put "Under load" up there, which is a sentence about a Mac in
        // trouble rather than about a build that is running.
        #expect(ActivityStatusItem.title(for: .running) == "Ocarina Working")
        #expect(ActivityStatusItem.title(for: .succeeded) == "Ocarina Done")
        #expect(ActivityStatusItem.title(for: .idle) == "Ocarina Idle")
        for activity: TabActivity in [.running, .succeeded, .idle, .failed(exitCode: 1)] {
            #expect(ActivityStatusItem.title(for: activity).hasPrefix("Ocarina "))
        }
    }

    @Test("No theme's wording reaches the menu bar strip")
    func themeVoiceStaysOutOfTheStrip() {
        // The register did not go away — it is one click down, in the menu.
        // What this pins is that it stays there: a theme that could write the
        // strip could put anything at all beside the Wi-Fi.
        let title = ActivityStatusItem.title(for: .running)
        #expect(title != ActivityStatusItem.line(for: .running, speech: speech))
        #expect(!title.contains(speech.working))
    }

    @Test("A failure keeps its code in the strip too")
    func stripFailureCarriesItsCode() {
        let title = ActivityStatusItem.title(for: .failed(exitCode: 127))
        #expect(title.contains("127"))
        #expect(title != ActivityStatusItem.title(for: .succeeded))
    }

    @Test("A theme cannot write a failure that loses its exit code")
    func failureAlwaysCarriesItsCode() {
        // The wording is the theme's; the number is not. A theme is allowed to
        // be as arch as it likes about a build stopping, and is not allowed to
        // make one read as anything other than a stop.
        let line = ActivityStatusItem.line(for: .failed(exitCode: 127), speech: speech)
        #expect(line.contains("127"))
        #expect(line.hasPrefix("It went bitter"))
        #expect(line != ActivityStatusItem.line(for: .succeeded, speech: speech))
    }

    @Test("A theme that says nothing still says something")
    func houseWordsStandIn() {
        // Every line has a default under it, so a user's own theme file — which
        // will not have heard of this field — comes up saying the house lines
        // rather than four empty strings in the menu bar.
        let silent = Theme.Speech(
            working: Theme.fallback.speech.working,
            done: Theme.fallback.speech.done,
            stopped: Theme.fallback.speech.stopped,
            clear: Theme.fallback.speech.clear,
            blurb: nil
        )
        #expect(silent.working == "Something is building")
        #expect(silent.done == "A build has completed")
        #expect(silent.clear == "All the items are closed")
    }

    @Test("The tooltip names what the line is about, when there is anything to name")
    func tooltipNamesTheTask() {
        func tooltip(task: String?) -> String {
            ActivityStatusItem.tooltip(
                for: .running,
                reading: .init(activity: .running, task: task, usage: nil, speech: speech)
            )
        }
        #expect(tooltip(task: "fix the parser") == "Ocarina — Steeping: fix the parser")
        // Not "Ocarina — Steeping: ", which is a colon promising a detail that
        // never arrives.
        #expect(tooltip(task: nil) == "Ocarina — Steeping")
        #expect(tooltip(task: "") == "Ocarina — Steeping")
    }

    @Test("The countdown reads in hours until there are none left")
    func countdownDropsTheHours() {
        let now = Date()
        #expect(ActivityStatusItem.countdown(to: now.addingTimeInterval(3 * 3600 + 1500), from: now) == "3h 25m")
        #expect(ActivityStatusItem.countdown(to: now.addingTimeInterval(1500), from: now) == "25m")
        // A window that closed while you were away counts down to nothing
        // rather than to a negative number of minutes.
        #expect(ActivityStatusItem.countdown(to: now.addingTimeInterval(-90), from: now) == "0m")
    }
}
