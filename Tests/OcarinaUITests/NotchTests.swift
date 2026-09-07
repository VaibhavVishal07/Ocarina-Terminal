import AppKit
import Foundation
import OcarinaTerminalContext
import Testing
@testable import OcarinaUI

@Suite("The drop out of the notch")
@MainActor
struct NotchTests {

    private func task(_ id: String, _ state: AgentTask.State, at seconds: TimeInterval = 0) -> AgentTask {
        AgentTask(
            id: id,
            title: "Task \(id)",
            prompt: "prompt \(id)",
            askedAt: Date(timeIntervalSinceReferenceDate: seconds),
            state: state
        )
    }

    @Test("A task that has just stopped is announced")
    func transitionIsFound() {
        let before = [task("a", .working), task("b", .working)]
        let after = [task("a", .finished), task("b", .working)]
        #expect(OcarinaModel.justFinished(was: before, now: after).map(\.id) == ["a"])
    }

    @Test("The same finished task is not announced twice")
    func announcedOnce() {
        // `finished` stays true forever after, so anything reading the current
        // list rather than the change would drop the notch on every poll for
        // as long as the task stayed in the panel — which is a two-second
        // heartbeat until you clear it.
        let after = [task("a", .finished)]
        #expect(OcarinaModel.justFinished(was: after, now: after).isEmpty)
    }

    @Test("History is not news")
    func openingATabAnnouncesNothing() {
        // The first poll of a tab hands over everything ever asked in that
        // directory, all of it finished. Nothing happened; you just looked.
        let history = [task("a", .finished), task("b", .finished), task("c", .finished)]
        #expect(OcarinaModel.justFinished(was: [], now: history).isEmpty)
    }

    @Test("A task that is still running is not announced")
    func stillWorking() {
        let before = [task("a", .working)]
        #expect(OcarinaModel.justFinished(was: before, now: before).isEmpty)
    }

    @Test("Several finishing at once are all reported, newest last")
    func severalAtOnce() {
        // The caller takes the newest of these. It gets all of them rather
        // than one, because "which is newest" is a decision about presentation
        // and this is the part that knows what changed.
        let before = [task("a", .working, at: 10), task("b", .working, at: 20)]
        let after = [task("a", .finished, at: 10), task("b", .finished, at: 20)]
        let finished = OcarinaModel.justFinished(was: before, now: after)
        #expect(Set(finished.map(\.id)) == ["a", "b"])
        #expect(finished.max(by: { $0.askedAt < $1.askedAt })?.id == "b")
    }

    @Test("The drop hangs from the bar at the top of the screen")
    func geometry() throws {
        let screen = try #require(NotchHUD.screenToUse())
        let frame = NotchHUD.frame(on: screen)

        // Centred on the screen it hangs from, not on whichever screen happens
        // to have the focused window.
        #expect(abs(frame.midX - screen.frame.midX) < 0.5)

        // Its top edge is exactly under the bar — the notch on a machine that
        // has one, the menu bar on a machine that does not — so the drop comes
        // out from behind that rather than floating below it.
        let bar = NotchHUD.barHeight(of: screen)
        #expect(bar > 0, "there is always something at the top of a screen to clear")
        #expect(abs(frame.maxY - (screen.frame.maxY - bar)) < 0.5)

        #expect(frame.height == NotchDrop.height)
        #expect(frame.width == NotchDrop.width)
    }

    @Test("The shape is square across the top and round across the bottom")
    func shapeTucksUnderTheBar() {
        // A fully rounded pill under the notch is a notification. The top edge
        // has to read as continuous with the black bar above it, which means
        // the corners up there are not corners.
        let box = CGRect(x: 0, y: 0, width: 200, height: 40)
        let path = NotchShape(corner: 17).path(in: box)

        #expect(path.contains(CGPoint(x: 1, y: 1)), "the top-left corner should be filled")
        #expect(path.contains(CGPoint(x: 199, y: 1)), "the top-right corner should be filled")
        #expect(!path.contains(CGPoint(x: 1, y: 39)), "the bottom-left corner should be cut")
        #expect(!path.contains(CGPoint(x: 199, y: 39)), "the bottom-right corner should be cut")
    }
}
