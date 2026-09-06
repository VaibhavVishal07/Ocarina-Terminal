import Foundation
import Testing
@testable import OcarinaUI

/// The theme reaching inside the programs the terminal runs.
@Suite("Palette filter")
struct PaletteFilterTests {

    private func filter(enabled: Bool = true) -> PaletteFilter {
        PaletteFilter(theme: .fallback, isEnabled: enabled)
    }

    private func text(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    @Test("A program's own accent is toned down to plain text")
    func accentIsTonedDown() {
        var subject = filter()
        // Claude's orange is branding, not information: the loudest thing on
        // the screen, saying nothing the words beside it do not. The house
        // theme's foreground is #C9D4E0, whose grey is #D3D3D3.
        let out = text(subject.filter(Array("\u{1B}[38;2;217;119;87mhello".utf8)[...]))
        #expect(out == "\u{1B}[38;2;211;211;211mhello")
    }

    @MainActor
    @Test("Toned down means no hue, not the theme's hue")
    func accentCarriesNoTheme() throws {
        // The theme's own text colour is not neutral in every theme — Matrix
        // sets it to #8CF5A3 — so an accent handed the foreground itself came
        // out bright green, which is not what toning a colour down means.
        let matrix = try #require(ThemeStore().available.first { $0.id == "matrix" })
        var subject = PaletteFilter(theme: matrix, isEnabled: true)
        let out = text(subject.filter(Array("\u{1B}[38;5;220m".utf8)[...]))

        let channels = out
            .dropFirst("\u{1B}[38;2;".count).dropLast()
            .split(separator: ";").compactMap { Int($0) }
        #expect(channels.count == 3)
        #expect(Set(channels).count == 1)
    }

    @MainActor
    @Test("A recolour may not turn decoration into pass or fail")
    func themeMayNotInventMeaning() throws {
        // The pale blue Claude Code paints the *selected* option of a yes/no
        // prompt in. Matrix answers "blue" with #8AF0A5, so "No, exit" came up
        // green — a negative call to action wearing the colour of go.
        let store = ThemeStore()
        let selected = "\u{1B}[38;5;153m"

        let matrix = try #require(store.available.first { $0.id == "matrix" })
        var green = PaletteFilter(theme: matrix, isEnabled: true)
        #expect(text(green.filter(Array(selected.utf8)[...])) == selected)

        // Where the theme's blue really is a blue, it still answers.
        let ocarina = try #require(store.available.first { $0.id == "ocarina" })
        var blue = PaletteFilter(theme: ocarina, isEnabled: true)
        #expect(text(blue.filter(Array(selected.utf8)[...])) == "\u{1B}[38;5;12m")
    }

    @Test("Every theme is checked by the same rule that picked the slot")
    func familyIsShared() {
        #expect(PaletteFilter.wouldReadAsSemantic(ThemeColor(hex: "#8AF0A5")))   // Matrix's "blue"
        #expect(PaletteFilter.wouldReadAsSemantic(ThemeColor(hex: "#F06C6C")))
        #expect(!PaletteFilter.wouldReadAsSemantic(ThemeColor(hex: "#84B1F5")))
        #expect(!PaletteFilter.wouldReadAsSemantic(ThemeColor(hex: "#BDC1F5")))  // Sakura's blue
        #expect(!PaletteFilter.wouldReadAsSemantic(ThemeColor(hex: "#E5CE5A")))  // a yellow is not a verdict
        #expect(!PaletteFilter.wouldReadAsSemantic(ThemeColor(hex: "#949494")))
    }

    @Test("Red and green are the program's to keep")
    func semanticColoursSurvive() {
        var subject = filter()
        // The two colours in a terminal that mean something rather than
        // decorate: removed and added, failed and passed. Sent to the theme's
        // nearest slot, a palette built around one hue answers both with the
        // same colour, and a diff stops being a diff.
        let removed = "\u{1B}[38;2;220;80;80m- old"
        let added = "\u{1B}[38;2;80;200;120m+ new"
        #expect(text(subject.filter(Array(removed.utf8)[...])) == removed)
        #expect(text(subject.filter(Array(added.utf8)[...])) == added)
        // Including as a background, which is how a diff marks a whole line.
        let block = "\u{1B}[48;5;22m added \u{1B}[48;5;52m removed "
        #expect(text(subject.filter(Array(block.utf8)[...])) == block)
    }

    @Test("A warm background is still a marked row, not a white bar")
    func warmBackgroundKeepsAHue() {
        var subject = filter()
        // Toning the accent to the text colour is a rule about text. A warm
        // background is a highlighted row, and it has to stay visible as one.
        #expect(text(subject.filter(Array("\u{1B}[48;2;217;119;87m".utf8)[...])) == "\u{1B}[48;5;11m")
    }

    @Test("The eight ANSI colours are left where they are")
    func ansiPassesThrough() {
        var subject = filter()
        // These were already the theme's to answer. Rewriting them would be
        // taking a question the theme had and answering it twice.
        let input = "\u{1B}[31mred\u{1B}[0m \u{1B}[1;38;5;4mblue\u{1B}[m"
        #expect(text(subject.filter(Array(input.utf8)[...])) == input)
    }

    @Test("The 256-colour cube gets the same three answers")
    func cubeIsMapped() {
        var subject = filter()
        // These three are what Claude Code actually sends: 220 its gold, 246
        // the grey of its secondary lines, 153 the pale blue of its chrome.
        #expect(text(subject.filter(Array("\u{1B}[38;5;220m".utf8)[...])) == "\u{1B}[38;2;211;211;211m")
        #expect(text(subject.filter(Array("\u{1B}[38;5;153m".utf8)[...])) == "\u{1B}[38;5;12m")
        // A grey is already neutral; there is nothing in it to theme.
        #expect(text(subject.filter(Array("\u{1B}[38;5;246m".utf8)[...])) == "\u{1B}[38;5;246m")
        #expect(text(subject.filter(Array("\u{1B}[38;5;240m".utf8)[...])) == "\u{1B}[38;5;240m")
    }

    @Test("A program painting the terminal's own ground gets the ground")
    func groundBecomesDefault() {
        var subject = filter()
        // The house theme's background. Answered with the theme's black, this
        // would lay an opaque slab over the window's glass; answered with
        // "default", the glass shows through as it does everywhere else.
        #expect(text(subject.filter(Array("\u{1B}[48;2;18;23;30m".utf8)[...])) == "\u{1B}[49m")
        // And the same for text already set in the theme's own foreground.
        #expect(text(subject.filter(Array("\u{1B}[38;2;201;212;224m".utf8)[...])) == "\u{1B}[39m")
    }

    @Test("Other attributes in the same sequence survive it")
    func neighbouringParametersSurvive() {
        var subject = filter()
        let out = text(subject.filter(Array("\u{1B}[1;38;2;90;169;240;4m".utf8)[...]))
        #expect(out == "\u{1B}[1;38;5;12;4m")
    }

    @Test("Sub-parameter colour is mapped too")
    func subparameterForm() {
        var subject = filter()
        let out = text(subject.filter(Array("\u{1B}[38:2::143:180:255m".utf8)[...]))
        #expect(out == "\u{1B}[38:5:12m")
    }

    @Test("A sequence split across two reads is put back together")
    func splitSequence() {
        var subject = filter()
        // A pty read stops wherever the buffer filled. Rewriting half a
        // sequence would put the tail of one on screen as text.
        let first = text(subject.filter(Array("ok \u{1B}[38;2;217".utf8)[...]))
        #expect(first == "ok ")
        let second = text(subject.filter(Array(";119;87mhello".utf8)[...]))
        #expect(second == "\u{1B}[38;2;211;211;211mhello")
    }

    @Test("Anything that is not a colour is passed through byte for byte")
    func otherSequencesUntouched() {
        var subject = filter()
        let input = "\u{1B}[2J\u{1B}[H\u{1B}]0;a title\u{07}plain\r\n\u{1B}[?25l"
        #expect(text(subject.filter(Array(input.utf8)[...])) == input)
    }

    @Test("Switched off, it is the identity")
    func disabledChangesNothing() {
        var subject = filter(enabled: false)
        let input = "\u{1B}[38;2;217;119;87mhello"
        #expect(text(subject.filter(Array(input.utf8)[...])) == input)
    }

    @Test("Held bytes are let go when the retint is switched off mid-stream")
    func heldBytesSurviveBeingDisabled() {
        var subject = filter()
        _ = subject.filter(Array("\u{1B}[38;2;217".utf8)[...])
        subject.isEnabled = false
        // The fragment is still owed to the screen, whatever the setting says.
        #expect(text(subject.filter(Array(";119;87mx".utf8)[...])) == "\u{1B}[38;2;217;119;87mx")
    }

    @Test("A run of bytes that only looked like a sequence is not swallowed")
    func longFragmentIsReleased() {
        var subject = filter()
        let noise = "\u{1B}[" + String(repeating: "1;", count: 200)
        #expect(text(subject.filter(Array(noise.utf8)[...])) == noise)
    }

    @Test("What each kind of colour is allowed to become")
    func renderings() {
        func rendering(_ hex: String, foreground: Bool = true) -> PaletteFilter.Rendering {
            PaletteFilter.rendering(for: ThemeColor(hex: hex), isForeground: foreground)
        }
        // Meaning: left alone, dark or bright, text or background.
        #expect(rendering("#8B1A1A") == .unchanged)
        #expect(rendering("#FF6B6B") == .unchanged)
        #expect(rendering("#2E8B57") == .unchanged)
        #expect(rendering("#2E8B57", foreground: false) == .unchanged)
        // Decoration: the theme's, and a saturated hue sits at half lightness
        // however loud it is, so the bright half is chosen on the strongest
        // channel instead.
        #expect(rendering("#1E6FD9") == .slot(4))
        #expect(rendering("#84C4F5") == .slot(12))
        #expect(PaletteFilter.family(of: ThemeColor(hex: "#84C4F5")) == .blue)
        #expect(rendering("#9B59B6") == .slot(5))
        #expect(rendering("#17A2B8") == .slot(6))
        // Branding: no hue at all.
        #expect(rendering("#D97757") == .neutral)
        #expect(rendering("#FFD700") == .neutral)
        // Greys are already neutral, at either end of the ramp.
        #expect(rendering("#0A0A0A") == .unchanged)
        #expect(rendering("#6E6E6E") == .unchanged)
        #expect(rendering("#B4B4B4") == .unchanged)
        #expect(rendering("#FFFFFF") == .unchanged)
    }
}
