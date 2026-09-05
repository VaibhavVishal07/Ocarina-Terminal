import Foundation
import Testing
@testable import OcarinaUI

@Suite("Quick Actions")
struct RecipeTests {
    private var groups: [RecipeGroup] { RecipeCatalog.bundled() }

    @Test("The bundled catalogue is there and parses")
    func catalogueLoads() {
        #expect(groups.isEmpty == false, "no recipe files found in the bundle")
        #expect(groups.flatMap(\.items).isEmpty == false)
    }

    @Test("Every recipe says where it came from and when it was checked")
    func provenance() {
        // A wrong install command behind a friendly button is worse than no
        // button, because the person pressing it cannot tell. Provenance is
        // what makes a stale recipe a bug with an owner instead of a mystery.
        for recipe in groups.flatMap(\.items) {
            #expect(recipe.docs.hasPrefix("https://"), "\(recipe.id) has no docs URL")
            #expect(
                recipe.lastVerified.count == 10 && recipe.lastVerified.contains("-"),
                "\(recipe.id) lastVerified should be an ISO date, got '\(recipe.lastVerified)'"
            )
        }
    }

    @Test("Every recipe explains itself before it is offered")
    func explanations() {
        for recipe in groups.flatMap(\.items) {
            #expect(recipe.explain.count > 20, "\(recipe.id) needs a real explanation")
            #expect(recipe.command.isEmpty == false)
        }
    }

    @Test("Recipe ids are unique, so one cannot shadow another")
    func uniqueIDs() {
        let ids = groups.flatMap(\.items).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Nothing in the catalogue runs itself")
    func nothingAutoRuns() {
        // The command is typed, never executed, so a trailing newline in a
        // recipe would quietly turn a suggestion into an action.
        for recipe in groups.flatMap(\.items) {
            #expect(recipe.command.contains("\n") == false, "\(recipe.id) has a newline in it")
        }
    }
}
