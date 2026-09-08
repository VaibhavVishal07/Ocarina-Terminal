import Foundation
import Testing
@testable import OcarinaUI

/// What happens to the selection when a tab goes.
@MainActor
@Suite("Closing a tab")
struct CloseTabTests {

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-close-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The bug: `selectedSession` is `selectedTabID` looked up in `sessions`,
    /// and the session was torn down before the selection moved. For that
    /// moment there were tabs on screen and no session selected — which is
    /// precisely the case the window draws its landing board for. Closing one
    /// of several tabs flashed the empty state on the way to the next one.
    @Test("A session is always selected while tabs remain")
    func neverLandsOnNothing() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = OcarinaModel()
        let first = model.newTab(workingDirectory: dir)
        let second = model.newTab(workingDirectory: dir)
        let third = model.newTab(workingDirectory: dir)
        defer { [first, second].forEach { model.closeTab($0.id) } }

        model.closeTab(third.id)
        #expect(model.selectedTabID != nil)
        #expect(model.selectedSession != nil, "tabs remain, so a session must be selected")
    }

    /// "Go back to the previous tab": the one you came from, not the one next
    /// to it in a column ordered by when each session was made.
    @Test("Closing the tab you are in goes back where you came from")
    func returnsToThePreviousTab() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = OcarinaModel()
        let a = model.newTab(workingDirectory: dir)
        let b = model.newTab(workingDirectory: dir)
        let c = model.newTab(workingDirectory: dir)
        defer { [a, b].forEach { model.closeTab($0.id) } }

        // Work in A, then open C's neighbour and come back — the tab you were
        // last in is A, which is two rows away in the column.
        model.selectTab(a.id)
        model.selectTab(c.id)
        model.closeTab(c.id)

        #expect(model.selectedTabID == a.id, "not b, which is merely adjacent")
    }

    /// A window whose tabs have never been switched between has no history to
    /// go back to, so the neighbour is the honest answer.
    @Test("With nothing visited, it takes the neighbour")
    func fallsBackToTheNeighbour() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = OcarinaModel()
        let a = model.newTab(workingDirectory: dir)
        let b = model.newTab(workingDirectory: dir)
        defer { model.closeTab(a.id) }

        model.closeTab(b.id)
        #expect(model.selectedTabID == a.id)
        #expect(model.selectedSession != nil)
    }

    /// The one case where the board is right: nothing is open.
    @Test("The last tab leaves the landing screen")
    func lastTabLeavesNothing() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = OcarinaModel()
        let only = model.newTab(workingDirectory: dir)
        model.closeTab(only.id)

        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
        #expect(model.selectedSession == nil)
        #expect(model.usage == nil)
    }

    @Test("Closing a tab you are not in leaves the selection alone")
    func closingAnotherTabDoesNotMoveYou() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = OcarinaModel()
        let a = model.newTab(workingDirectory: dir)
        let b = model.newTab(workingDirectory: dir)
        defer { model.closeTab(b.id) }

        model.selectTab(b.id)
        model.closeTab(a.id)
        #expect(model.selectedTabID == b.id)
    }
}
