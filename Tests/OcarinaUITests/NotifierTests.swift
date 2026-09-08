import Foundation
import OcarinaTerminalContext
import Testing
@testable import OcarinaUI

@Suite("Notifications")
@MainActor
struct NotifierTests {

    /// Stands in for the system's notification centre, which needs a bundle
    /// that a test binary is not.
    final class Spy: NotificationPoster {
        var asked = 0
        var answer = true
        var posted: [(title: String, body: String, id: String)] = []

        func authorize() async -> Bool {
            asked += 1
            return answer
        }

        func post(title: String, body: String, id: String) {
            posted.append((title, body, id))
        }
    }

    private func notifier(
        active: Bool = false,
        enabled: Bool = true,
        spy: Spy = Spy()
    ) -> (Notifier, Spy) {
        let defaults = UserDefaults(suiteName: "ocarina-notify-\(UUID().uuidString)")!
        defaults.set(enabled, forKey: "ocarina.notifications.enabled")
        let n = Notifier(poster: spy, defaults: defaults, isAppActive: { active })
        return (n, spy)
    }

    /// The post is made inside a Task, so let the loop turn once.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    @Test("Only three things are worth saying")
    func onlyMomentsThatMatter() {
        // A terminal reaches a prompt a hundred times an hour and none of them
        // are news; neither is a command still running.
        #expect(Notifier.Moment.worthSaying(.idle) == nil)
        #expect(Notifier.Moment.worthSaying(.running) == nil)

        #expect(Notifier.Moment.worthSaying(.needsYou) == .needsYou)
        #expect(Notifier.Moment.worthSaying(.succeeded) == .backToYou)
        #expect(Notifier.Moment.worthSaying(.failed(exitCode: 127)) == .failed(exitCode: 127))
    }

    @Test("Nothing is said about a window you are looking at")
    func silentWhileYouAreThere() async {
        let (n, spy) = notifier(active: true)
        n.say(.needsYou, about: "Fix the checkout page", id: UUID())
        await settle()
        // Everything here is already on screen: the tab's dot, the rail, the
        // card in the menu bar. A notification would be a second copy of it.
        #expect(spy.posted.isEmpty)
        #expect(spy.asked == 0, "and it must not ask for permission to say nothing")
    }

    @Test("Turned off means off, and unasked")
    func offMeansOff() async {
        let (n, spy) = notifier(enabled: false)
        n.say(.failed(exitCode: 1), about: "npm run build", id: UUID())
        await settle()
        #expect(spy.posted.isEmpty)
        #expect(spy.asked == 0)
    }

    @Test("Away from the window, it says the state and names the ask")
    func itSaysTheState() async {
        let (n, spy) = notifier()
        let id = UUID()
        n.say(.needsYou, about: "Fix the checkout page", id: id)
        await settle()

        #expect(spy.posted.count == 1)
        // The state leads, because that is the actionable half; the name is the
        // ask you made, which is what says *which* session.
        #expect(spy.posted.first?.title == "Needs you")
        #expect(spy.posted.first?.body == "Fix the checkout page")
        #expect(spy.posted.first?.id == id.uuidString)
    }

    @Test("A failure carries its number, here as everywhere else")
    func failuresKeepTheirCode() async {
        let (n, spy) = notifier()
        n.say(.failed(exitCode: 127), about: "npm run build", id: UUID())
        await settle()
        #expect(spy.posted.first?.title == "Stopped (127)")
    }

    @Test("Nothing here says done")
    func nothingClaimsSuccess() {
        // An agent stopping means it stopped talking. The same word the menu
        // bar refuses is refused on a lock screen, where there is even less
        // context to correct it.
        for moment: Notifier.Moment in [.needsYou, .backToYou, .failed(exitCode: 1)] {
            #expect(!moment.line.localizedCaseInsensitiveContains("done"))
            #expect(!moment.line.localizedCaseInsensitiveContains("finish"))
        }
    }

    @Test("Permission is asked once, and a no is taken for an answer")
    func permissionIsAskedOnce() async {
        let spy = Spy()
        spy.answer = false
        let (n, _) = notifier(spy: spy)

        n.say(.backToYou, about: "one", id: UUID())
        await settle()
        n.say(.backToYou, about: "two", id: UUID())
        await settle()

        #expect(spy.asked == 1, "asking twice is asking somebody to say no twice")
        #expect(spy.posted.isEmpty)
    }

    @Test("Two notifications about one session replace each other")
    func oneLinePerSession() async {
        let (n, spy) = notifier()
        let id = UUID()
        n.say(.backToYou, about: "Fix the checkout page", id: id)
        await settle()
        n.say(.needsYou, about: "Fix the checkout page", id: id)
        await settle()
        // Same identifier both times: four asks coming back while you are at
        // lunch should be four lines, not forty.
        #expect(Set(spy.posted.map(\.id)).count == 1)
    }

    @Test("The switch is remembered")
    func theSwitchPersists() {
        let name = "ocarina-notify-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let first = Notifier(poster: Spy(), defaults: defaults, isAppActive: { false })
        #expect(first.isEnabled, "on by default: a feature nobody finds is worth nothing")
        first.isEnabled = false

        // The real one writes to .standard, which is what the app reads back.
        #expect(UserDefaults.standard.bool(forKey: "ocarina.notifications.enabled") == false)
        UserDefaults.standard.removeObject(forKey: "ocarina.notifications.enabled")
    }
}
