import Foundation
import Testing
@testable import OcarinaUI

/// The draft handed to the mail client.
@Suite("Share feedback")
struct FeedbackTests {

    @Test("The draft is addressed, titled, and carries the build it came from")
    func composesTheDraft() throws {
        let url = try #require(FeedbackMail.url(for: "The tabs stop renaming.",
                                                version: "0.1.0",
                                                system: "14.5.0"))
        #expect(url.scheme == "mailto")
        #expect(url.path == "vaibhavvishalece@gmail.com")

        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let subject = items.first { $0.name == "subject" }?.value
        let body = try #require(items.first { $0.name == "body" }?.value)

        #expect(subject == "Ocarina feedback")
        #expect(body.contains("The tabs stop renaming."))
        // The two facts every report needs and nobody remembers to include.
        #expect(body.contains("0.1.0"))
        #expect(body.contains("macOS 14.5.0"))
    }

    @Test("A plus in the message survives the trip")
    func keepsPlusSigns() throws {
        // `+` in a query string is a space to most mail clients, so it has to be
        // encoded or "C++" arrives as "C  ".
        let url = try #require(FeedbackMail.url(for: "Crashes when I type C++",
                                                version: "0.1.0",
                                                system: "14.5.0"))
        let raw = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedQuery)
        #expect(!raw.contains("C++"))
        #expect(raw.contains("%2B%2B"))

        let decoded = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value)
        #expect(decoded.contains("C++"))
    }

    @Test("An empty message is not worth a draft")
    @MainActor
    func emptyMessageOpensNothing() {
        let model = OcarinaModel()
        model.isFeedbackVisible = true
        model.composeFeedback("")
        // The sheet closes either way; the point is that nothing was launched.
        #expect(!model.isFeedbackVisible)
    }
}
