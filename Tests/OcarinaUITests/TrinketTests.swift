import Foundation
import Testing
@testable import OcarinaUI

@Suite("Trinkets")
@MainActor
struct TrinketTests {
    /// Read from the files rather than through the store, which filters
    /// unusable themes out — silently dropping one we ship is exactly what
    /// these are checking for.
    private var themes: [Theme] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        return urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
    }

    /// What `DotMatrix` can actually draw. A character outside this renders as
    /// a blank cell rather than failing, so nothing but a test catches it.
    private static let drawable = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 +-./:")

    /// The tagline it replaces is 22 characters. The board's font is fixed
    /// width, so a longer line is a wider line, and past about this it is
    /// wider than the row of tools it sits over.
    private static let lineLimit = 24

    @Test("Every bundled theme has been given a trinket, or deliberately not")
    func everyThemeDecided() {
        // Two have none on purpose: Mono is a theme about not doing this, and
        // High Contrast exists for people for whom moving decoration is the
        // problem rather than the charm. Every other theme having one is what
        // stops a new theme quietly shipping without.
        let silent: Set<String> = ["mono", "high-contrast"]
        for theme in themes {
            if silent.contains(theme.id) {
                #expect(theme.trinket == nil, "\(theme.id) should have no trinket")
                #expect(theme.flavour == nil, "\(theme.id) should have no line")
            } else {
                #expect(theme.trinket != nil, "\(theme.id) has no trinket")
                #expect(theme.flavour != nil, "\(theme.id) has no line of its own")
            }
        }
    }

    @Test("Every line can be drawn, and fits")
    func linesAreDrawable() {
        for theme in themes {
            guard let flavour = theme.flavour else { continue }
            let stray = flavour.filter { !Self.drawable.contains($0) }
            #expect(stray.isEmpty, "\(theme.id) cannot draw '\(stray)' on the board")
            #expect(
                flavour.count <= Self.lineLimit,
                "\(theme.id)'s line is \(flavour.count) characters, over \(Self.lineLimit)"
            )
            #expect(flavour == flavour.uppercased(), "\(theme.id)'s line must be uppercase")
        }
    }

    @Test("A trinket in a theme file is one the renderer knows")
    func trinketsDecode() {
        // The field is a string in the file and an enum here. A typo decodes
        // as nil, which is indistinguishable from "this theme has none" — so
        // the check that catches it is that every theme that should have one
        // does, which is the test above. This one guards the other direction:
        // every case the enum offers is spelled the way a file would spell it.
        for trinket in Trinket.allCases {
            #expect(trinket.rawValue == trinket.rawValue.lowercased())
            #expect(trinket.count > 0)
            #expect(trinket.size > 0)
            // Under a third, always. The landing screen has four icons and a
            // button on it that somebody is choosing between, and a petal as
            // strong as the thing it crosses behind has won an argument it
            // should not have been in.
            #expect(trinket.strength < 0.34, "\(trinket.rawValue) is drawn too hard")
            #expect(trinket.path(size: 8).isEmpty == false)
        }
    }

    @Test("A still trinket does not need a crossing time, and a moving one does")
    func motionIsCoherent() {
        for trinket in Trinket.allCases where trinket.motion != .still {
            #expect(trinket.crossing > 1, "\(trinket.rawValue) crosses too fast to be a trinket")
        }
        // Rain is the exception the others are measured against: it is meant to
        // read as weather, and everything else is meant not to.
        for trinket in Trinket.allCases where trinket != .rain && trinket.motion != .still {
            #expect(trinket.crossing >= 9, "\(trinket.rawValue) is closer to weather than to a trinket")
        }
    }
}
