import Foundation
import Testing
@testable import OcarinaUI

/// The report handed to GitHub or the clipboard.
@Suite("Share feedback")
struct FeedbackTests {

    @Test("The issue is titled from the first line and carries the build")
    func buildsTheIssue() throws {
        let url = try #require(FeedbackReport.issueURL(
            for: "The tabs stop renaming.\nIt happens after a build.",
            version: "0.1.0",
            system: "14.5.0"
        ))
        #expect(url.host == "github.com")
        #expect(url.path.hasSuffix("/issues/new"))

        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let title = try #require(items.first { $0.name == "title" }?.value)
        let body = try #require(items.first { $0.name == "body" }?.value)

        // The title is the first line only; the whole thing is in the body.
        #expect(title == "The tabs stop renaming.")
        #expect(body.contains("It happens after a build."))
        #expect(body.contains("0.1.0"))
        #expect(body.contains("macOS 14.5.0"))
    }

    @Test("Nobody has to read a forty-word issue title")
    func capsTheTitle() {
        let long = String(repeating: "a very long complaint ", count: 10)
        let title = FeedbackReport.title(from: long)
        #expect(title.count <= 72)
        #expect(title.hasSuffix("\u{2026}"))
    }

    @Test("A plus in the report survives the trip")
    func keepsPlusSigns() throws {
        let url = try #require(FeedbackReport.issueURL(for: "Crashes when I type C++",
                                                       version: "0.1.0",
                                                       system: "14.5.0"))
        let raw = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedQuery)
        #expect(!raw.contains("C++"))

        let decoded = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value)
        #expect(decoded.contains("C++"))
    }

    @Test("Nothing in the report asks who sent it")
    func staysAnonymous() {
        let report = FeedbackReport.body("Something broke", version: "0.1.0", system: "14.5.0")
        #expect(!report.lowercased().contains("@"))
        #expect(!report.lowercased().contains("mailto"))
    }

    @Test("An empty message opens nothing")
    @MainActor
    func emptyOpensNothing() {
        let model = OcarinaModel()
        model.isFeedbackVisible = true
        model.openFeedbackIssue("")
        #expect(!model.isFeedbackVisible)
    }
}
