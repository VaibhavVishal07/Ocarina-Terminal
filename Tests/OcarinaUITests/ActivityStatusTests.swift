import Foundation
import OcarinaTerminalContext
import AppKit
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

    @Test("The words answer the question, in every theme")
    func houseWordsAnswerTheQuestion() {
        // The house line is the same in all fourteen themes: Steel put "Under
        // load" up there, which is a sentence about a Mac in trouble rather
        // than about a build that is running.
        #expect(ActivityStatusItem.title(for: .running) == "Still going")
        #expect(ActivityStatusItem.title(for: .succeeded) == "Back to you")
        #expect(ActivityStatusItem.title(for: .idle) == "Ready")

        // Sentence case. It was uppercase for as long as it was painted on a
        // 5x7 grid with no descenders; now it is read by VoiceOver and shown
        // in a tooltip, and neither of those wants shouting.
        for activity: TabActivity in [.running, .succeeded, .idle, .failed(exitCode: 127)] {
            let line = ActivityStatusItem.title(for: activity)
            #expect(line != line.uppercased(), "\(activity) is still set in the board's case")
        }
    }

    @Test("The app is named once, by the tooltip, and not again by the line")
    func theNameIsSaidOnce() {
        // The face has nothing to say whose it is, so the tooltip says it —
        // once, in front. A line that named the app as well would put the name
        // in every reading twice.
        for activity: TabActivity in [.running, .succeeded, .idle, .failed(exitCode: 1)] {
            #expect(!ActivityStatusItem.title(for: activity).localizedCaseInsensitiveContains("ocarina"))
            let tip = ActivityStatusItem.tooltip(
                for: activity,
                reading: .init(activity: activity, task: nil, usage: nil, speech: speech)
            )
            #expect(tip.hasPrefix("Ocarina — "))
        }
    }

    @MainActor
    @Test("The card is small enough to belong in a menu bar")
    func theCardFitsTheBar() {
        // The point of the whole change. The board this replaced set the line
        // in the 5x7 alphabet at six columns a character, which put `STILL
        // GOING` up there 136 points wide — the widest item in the menu bar by
        // a factor of five, for a word that was too small to read.
        for card in ActivityCard.allCases {
            let image = ActivityStatusItem.glyph(card)
            #expect(image.size.width < 20, "\(card) came out \(image.size)")
            #expect(image.size.height > 10 && image.size.height < 18, "too tall for a menu bar")
            #expect(image.isTemplate, "it will not invert with the menu bar")
            // Square, because every other item in a menu bar is. A tall narrow
            // one reads as something squeezed rather than drawn to fit.
            #expect(image.size.width == image.size.height, "\(card) is not square")
        }
    }

    @MainActor
    @Test("Every state is a different card")
    func everyStateLooksDifferent() {
        func pixels(_ image: NSImage) -> Data? {
            guard let tiff = image.tiffRepresentation else { return nil }
            return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        }

        // Four states, four pictures. A set where two of them draw the same is
        // a menu bar that cannot tell you the one thing it is for.
        var drawn = Set<Data>()
        for card in ActivityCard.allCases {
            let data: Data? = pixels(ActivityStatusItem.glyph(card))
            #expect(data != nil, "\(card) did not draw")
            if let data { drawn.insert(data) }
        }
        let states: Int = ActivityCard.allCases.count
        #expect(drawn.count == states, "two states draw the same card")
    }

    @MainActor
    @Test("The turn moves, and never rests on the resting card")
    func theTurnMoves() {
        func pixels(_ image: NSImage) -> Data? {
            guard let tiff = image.tiffRepresentation else { return nil }
            return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        }

        // Every frame of the turn is a different picture, and the frame index
        // wraps — the item counts frames forever and must not walk off the end
        // of the list.
        var frames = Set<Data>()
        for index in 0..<(ActivityCard.turn.count * 3) {
            if let data: Data = pixels(ActivityStatusItem.glyph(.working, turn: index)) {
                frames.insert(data)
            }
        }
        #expect(frames.count == ActivityCard.turn.count, "the turn does not cycle cleanly")

        // And none of them is the resting card. A working item that flickers
        // through "nothing asked" five times a second is worse than one that
        // simply loops — which is why the turn is five frames and not the six
        // it takes to come back round to the seam.
        let resting: Data? = pixels(ActivityStatusItem.glyph(.ready))
        #expect(resting != nil)
        if let resting { #expect(!frames.contains(resting), "the turn passes through Ready") }
    }

    @Test("The seam is in every state, and nothing else is ever drawn on it")
    func theSeamHolds() {
        // The whole idea. A split-flap card is cut across its middle, and that
        // line has to be there in every state or this is a box that fills up:
        // a lit line when the cell is empty, a dark gap when it is full.
        let seam = ActivityCard.seam
        let dark = String(repeating: ".", count: ActivityCard.columns)
        let full = String(repeating: "#", count: ActivityCard.columns)
        for card in ActivityCard.allCases where card != .ready {
            #expect(card.plate[seam] == dark, "\(card) draws on the seam")
        }
        #expect(ActivityCard.ready.plate[seam] == full, "the empty cell has no seam")
        for (index, frame) in ActivityCard.turn.enumerated() {
            #expect(frame[seam] == dark, "turn frame \(index) draws on the seam")
        }
    }

    @Test("Every card is the same five by five")
    func everyCardIsTheSameShape() {
        // Hand-authored string art. A row a character short is a silent
        // off-by-one in the drawing loop rather than a compile error.
        var plates = ActivityCard.allCases.map(\.plate)
        plates.append(contentsOf: ActivityCard.turn)
        for plate in plates {
            #expect(plate.count == ActivityCard.rows)
            for line in plate {
                #expect(line.count == ActivityCard.columns, "\(line) is not \(ActivityCard.columns) wide")
                #expect(line.allSatisfy { $0 == "#" || $0 == "." }, "\(line) has a stray character")
            }
        }
    }

    @Test("Nothing up there grades the work")
    func theCardMakesNoClaim() {
        // A tick was the most readable of the seven things tried in this slot
        // and the only one that says the work succeeded. An agent stopping
        // means it stopped talking — which is why the words say "back to you"
        // and never "done", and why the card lands on a ring.
        //
        // A ring is symmetric about both axes; a tick is symmetric about
        // neither. This is what catches a tick being put back.
        let plate = ActivityCard.backToYou.plate
        #expect(plate == plate.reversed(), "the landed card is not symmetric top to bottom")
        for line in plate {
            #expect(line == String(line.reversed()), "\(line) is not symmetric left to right")
        }
    }

    @Test("A failure keeps its code in the words")
    func stripFailureCarriesItsCode() {
        // The face cannot draw a number — this is the surface that carries it.
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
