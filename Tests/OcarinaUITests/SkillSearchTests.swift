import Foundation
import Testing
@testable import OcarinaUI

/// The searches that broke the substring filter this replaced.
///
/// Every case here is a phrase somebody would actually type into a field that
/// asks "what are you looking for?", which is the only kind of query the new
/// modal can receive. The old filter answered the first one with nothing.
@Suite("Skill search")
struct SkillSearchTests {

    private let catalogue = SkillCatalog.load()

    @Test("The bundled catalogue is there to search")
    func catalogueLoads() {
        #expect(catalogue.count > 100)
    }

    /// The reason any of this exists: `"UI design"` is in no name and no
    /// description, so `description.contains("ui design")` was false 216 times.
    @Test("A two-word phrase that appears verbatim nowhere")
    func uiDesign() throws {
        let found = SkillCatalog.search(catalogue, for: "UI design")
        #expect(found.count > 20)
        #expect(found.first?.skill.name == "frontend-design")
    }

    /// Near-words must stay under real words, or a skill whose *name* contains
    /// "interface" and "design" ties the one people meant.
    @Test("A literal beats a near-word")
    func literalWins() throws {
        let found = SkillCatalog.search(catalogue, for: "UI design")
        let names = found.prefix(4).map(\.skill.name)
        let frontend = try #require(names.firstIndex(of: "frontend-design"))
        if let api = names.firstIndex(of: "api-and-interface-design") {
            #expect(frontend < api)
        }
    }

    /// The naive repair — split on spaces and keep using `contains` — put an
    /// Azure resource browser first here, because "look" is inside "lookup".
    @Test("Whole words only: lookup is not look")
    func wholeWords() {
        let found = SkillCatalog.search(catalogue, for: "make my app look good")
        #expect(found.first?.skill.name.contains("azure") == false)
        #expect(found.first?.skill.category == .web || found.first?.skill.category == .design)
    }

    /// The case the old filter got right, which the new one must not lose.
    @Test("Typing a name puts that name first")
    func exactName() {
        for name in ["pdf", "docx", "code-review"] {
            let found = SkillCatalog.search(catalogue, for: name)
            #expect(found.first?.skill.name == name, "searching \(name)")
        }
    }

    /// What makes the list settle while you are still typing.
    @Test("Three letters prefix-match")
    func prefix() {
        let found = SkillCatalog.search(catalogue, for: "desig")
        #expect(found.contains { $0.skill.name.contains("design") })
    }

    /// Two letters do not, or `ui` would answer to *unit*, *use* and *update*.
    @Test("Two letters do not prefix-match")
    func shortStemsAreExact() {
        let two = SkillCatalog.search(catalogue, for: "de")
        let three = SkillCatalog.search(catalogue, for: "des")
        #expect(two.count < three.count)
        #expect(three.contains { $0.skill.name.contains("design") })
    }

    /// Grammar is dropped, so a sentence scores like the words that carry it.
    @Test("Filler words do not rank anything")
    func stopWords() {
        let bare = SkillCatalog.search(catalogue, for: "commit messages")
        // Only filler added. "write" is not filler — it is a real query here,
        // and adding it is meant to change the ranking.
        let wrapped = SkillCatalog.search(catalogue, for: "I want the commit messages")
        #expect(bare.first?.skill.id == wrapped.first?.skill.id)
    }

    /// Nothing typed is the house order, not an empty list. See
    /// `Skill.Category.ordered`.
    @Test("An empty query is the whole catalogue, design first")
    func emptyQuery() {
        let found = SkillCatalog.search(catalogue, for: "   ")
        #expect(found.count == catalogue.count)
        #expect(found.first?.skill.category == .design)
    }

    /// The hits are what the row underlines, so they have to be words that are
    /// really in the text — an underline on a word the description does not
    /// contain would be the search inventing its own evidence.
    @Test("Every hit is a word the row actually contains")
    func hitsAreReal() {
        for match in SkillCatalog.search(catalogue, for: "UI design").prefix(20) {
            let text = "\(match.skill.name) \(match.skill.description) "
                + "\(match.skill.category.rawValue) \(match.skill.author)"
            for hit in match.hits {
                #expect(text.lowercased().contains(hit), "\(hit) in \(match.skill.name)")
            }
        }
    }

    /// Every example sentence under the field has to return something. They
    /// are the whole merchandising surface of the modal, and one that comes
    /// back empty is worse than no example at all.
    @Test("The four example sentences all find something")
    func examplesWork() {
        let examples = [
            "make my UI look less generic",
            "review a pull request properly",
            "work with spreadsheets and CSVs",
            "write commit messages I'd actually read",
        ]
        for line in examples {
            let found = SkillCatalog.search(catalogue, for: line)
            #expect(found.count >= 3, "\(line) found \(found.count)")
        }
    }
}
