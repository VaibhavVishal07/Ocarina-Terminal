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

    @Test("The strip names the app and answers the question, in every theme")
    func stripNamesTheApp() {
        // The menu bar is read from outside Ocarina, so it says which app is
        // talking. It is also the same words in all fourteen themes: Steel put
        // "Under load" up there, which is a sentence about a Mac in trouble
        // rather than about a build that is running.
        #expect(ActivityStatusItem.title(for: .running) == "Ocarina · still going")
        #expect(ActivityStatusItem.title(for: .succeeded) == "Ocarina · back to you")
        #expect(ActivityStatusItem.title(for: .idle) == "Ocarina · ready")
        for activity: TabActivity in [.running, .succeeded, .idle, .failed(exitCode: 1)] {
            #expect(ActivityStatusItem.title(for: activity).hasPrefix("Ocarina · "))
        }
    }

    @Test("An agent is working when it owes you an answer, not when it repaints")
    func agentWorkIsAnOpenAsk() {
        // The one the menu bar got wrong. `.running` off the terminal means
        // "this program drew something in the last two and a half seconds",
        // and Claude sitting at its prompt with a cursor blinking in it
        // repaints forever — so a terminal left open on an agent that had been
        // waiting since lunch reported itself as working.
        func ask(_ state: AgentTask.State) -> AgentTask {
            AgentTask(id: "a", title: "t", prompt: "p", askedAt: Date(), state: state)
        }

        // Busy screen, nothing outstanding: it is your move.
        #expect(OcarinaModel.reported(.running, isConversation: true, tasks: [ask(.finished)])
                == .succeeded)
        // Busy screen, nothing ever asked: ready, not working.
        #expect(OcarinaModel.reported(.running, isConversation: true, tasks: []) == .idle)
        // An ask still open is work, however quiet the screen has gone.
        #expect(OcarinaModel.reported(.succeeded, isConversation: true, tasks: [ask(.working)])
                == .running)
    }

    @Test("A terminal that is not a conversation is taken at its word")
    func plainTerminalsKeepTheirOwnActivity() {
        // `make` in the foreground is working, and has no transcript to check
        // it against. Only a tab with a conversation in it gets second-guessed.
        for activity: TabActivity in [.running, .succeeded, .idle, .failed(exitCode: 2)] {
            #expect(OcarinaModel.reported(activity, isConversation: false, tasks: []) == activity)
        }
    }

    @Test("An agent that exited badly still says so")
    func failureOutranksTheTranscript() {
        // The transcript ends on a finished ask either way; the exit code is
        // the part it cannot tell you.
        #expect(OcarinaModel.reported(.failed(exitCode: 130), isConversation: true, tasks: [])
                == .failed(exitCode: 130))
    }

    @Test("The strip never claims the work succeeded")
    func nothingUpThereSaysItWorked() {
        // An agent stopping means it stopped talking. It does not mean it did
        // what was asked, and "Done" beside the Wi-Fi said it did — so the
        // word for that state hands the turn back rather than grading it.
        for activity: TabActivity in [.running, .succeeded, .idle, .failed(exitCode: 1)] {
            let title = ActivityStatusItem.title(for: activity).lowercased()
            for claim in ["done", "success", "complete", "finished", "worked"] {
                #expect(!title.contains(claim), "\(activity) says \(claim)")
            }
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
