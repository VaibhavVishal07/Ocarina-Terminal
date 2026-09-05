import Foundation
import Testing
@testable import OcarinaTerminalContext

@Suite("Title formatting")
struct TitleFormatterTests {

    @Test("Agent prompts become short action titles", arguments: [
        ("Fix the payment failure state on the checkout page.", "Fix Payment Failure State"),
        ("Refactor the authentication service to support refresh tokens.", "Refactor Authentication Service"),
        ("Create the homepage animation for the portfolio.", "Create Homepage Animation"),
        ("Investigate why search API latency increased.", "Investigate Search API Latency"),
        ("Now update the subtitle picker UI.", "Update Subtitle Picker UI"),
        ("can you add SSH support", "Add SSH Support"),
        ("please help me debug the search api", "Debug Search API")
    ])
    func naturalLanguage(prompt: String, expected: String) {
        #expect(TitleFormatter.title(fromNaturalLanguage: prompt) == expected)
    }

    @Test("Titles stay within the scannable word budget")
    func wordBudget() throws {
        let long = "Investigate why the video playback pipeline freezes after switching audio tracks mid stream"
        let title = try #require(TitleFormatter.title(fromNaturalLanguage: long))
        #expect(title.split(separator: " ").count <= TitleFormatter.defaultWordLimit)
    }

    @Test("Commands become titles", arguments: [
        (["npm", "run", "dev"], "Dev Server"),
        (["yarn", "build"], "Build"),
        (["python", "generate_report.py"], "Generate Report"),
        (["ssh", "production-api"], "Production API"),
        (["ssh", "deploy@staging-web"], "Staging Web"),
        (["git", "rebase"], "Git Rebase"),
        (["docker", "compose", "up"], "Docker Compose"),
        (["vim", "server_config.yaml"], "Edit Server Config"),
        (["htop"], "Htop")
    ])
    func commands(argv: [String], expected: String) {
        #expect(TitleFormatter.title(fromCommand: argv) == expected)
    }

    @Test("Acronyms stay uppercase and identifiers split on case and separators")
    func humanizing() {
        #expect(TitleFormatter.humanize("api_gateway") == "API Gateway")
        #expect(TitleFormatter.humanize("generateMonthlyReport") == "Generate Monthly Report")
        #expect(TitleFormatter.humanize("/Users/me/xstream-play") == "Xstream Play")
        #expect(TitleFormatter.title(fromNaturalLanguage: "push to github main") == "Push GitHub Main")
        #expect(TitleFormatter.title(fromNaturalLanguage: "fix the ios build") == "Fix iOS Build")
    }

    @Test("Empty and filler-only input yields no title")
    func nothingToSay() {
        #expect(TitleFormatter.title(fromNaturalLanguage: "   ") == nil)
        #expect(TitleFormatter.title(fromCommand: []) == nil)
    }

    @Test("Titles differing only in case are the same title")
    func equivalence() {
        #expect(TitleFormatter.isEquivalent("Fix Payment Flow", "fix  payment flow"))
        #expect(!TitleFormatter.isEquivalent("Fix Payment Flow", "Fix Payment Bug"))
    }
}
