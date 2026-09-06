import Foundation
import Testing
@testable import OcarinaTerminalContext
@testable import OcarinaUI

/// Pinning, and what comes back the next time the app opens.
@Suite("Pinned tabs")
@MainActor
struct PinnedTabTests {

    private func makeStore() throws -> (PinnedTabStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-pins-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (PinnedTabStore(url: directory.appendingPathComponent("pinned.json")), directory)
    }

    private func makeProjectDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-pin-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("A pinned tab comes back next launch, in the directory it was left in")
    func pinSurvivesRelaunch() throws {
        let (store, storeDirectory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let project = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: project) }

        let first = OcarinaModel(pinStore: store)
        let tab = first.newTab(workingDirectory: project)
        first.setPinned(true, for: tab.id)
        first.closeTab(tab.id)

        // A new model is the next launch: nothing carries over but the file.
        let second = OcarinaModel(pinStore: store)
        second.start()
        defer { second.tabs.forEach { second.closeTab($0.id) } }

        let restored = try #require(second.tabs.first { $0.id == tab.id })
        #expect(restored.isPinned)
        // Listed, but nothing spawned for it until it is asked for.
        #expect(restored.isDormant)
        #expect(second.session(for: restored.id) == nil)
        #expect(second.pinnedTabs.map(\.id) == [tab.id])
    }

    @Test("Tapping a restored tab is what starts it")
    func selectingWakesIt() throws {
        let (store, storeDirectory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let project = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: project) }

        let first = OcarinaModel(pinStore: store)
        let tab = first.newTab(workingDirectory: project)
        first.setPinned(true, for: tab.id)
        first.closeTab(tab.id)

        let second = OcarinaModel(pinStore: store)
        second.start()
        defer { second.tabs.forEach { second.closeTab($0.id) } }

        second.selectTab(tab.id)

        let session = try #require(second.session(for: tab.id))
        #expect(!second.tabs.first { $0.id == tab.id }!.isDormant)
        // Back where it was left, not at home.
        #expect(session.workingDirectory.standardizedFileURL == project.standardizedFileURL)
    }

    @Test("Closing a pinned tab keeps the row and drops the session")
    func closingLeavesTheRow() throws {
        let (store, storeDirectory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let project = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: project) }

        let model = OcarinaModel(pinStore: store)
        defer { model.tabs.forEach { model.closeTab($0.id) } }
        let tab = model.newTab(workingDirectory: project)
        model.setPinned(true, for: tab.id)

        model.closeTab(tab.id)

        #expect(model.tabs.contains { $0.id == tab.id })
        #expect(model.tabs.first { $0.id == tab.id }?.isDormant == true)
        #expect(model.session(for: tab.id) == nil)
    }

    @Test("Unpinning a dormant tab is what removes it")
    func unpinningRemovesADormantTab() throws {
        let (store, storeDirectory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let project = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: project) }

        let first = OcarinaModel(pinStore: store)
        let tab = first.newTab(workingDirectory: project)
        first.setPinned(true, for: tab.id)
        first.closeTab(tab.id)

        let second = OcarinaModel(pinStore: store)
        second.start()
        defer { second.tabs.forEach { second.closeTab($0.id) } }
        #expect(second.tabs.contains { $0.id == tab.id })

        second.setPinned(false, for: tab.id)
        #expect(!second.tabs.contains { $0.id == tab.id })

        // And it does not come back on the launch after that.
        let third = OcarinaModel(pinStore: store)
        third.start()
        defer { third.tabs.forEach { third.closeTab($0.id) } }
        #expect(!third.tabs.contains { $0.id == tab.id })
    }

    @Test("A pin whose directory has since gone still opens")
    func missingDirectoryFallsBackHome() throws {
        let (store, storeDirectory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let project = try makeProjectDirectory()

        let first = OcarinaModel(pinStore: store)
        let tab = first.newTab(workingDirectory: project)
        first.setPinned(true, for: tab.id)
        first.closeTab(tab.id)

        // The folder is deleted between launches.
        try FileManager.default.removeItem(at: project)

        let second = OcarinaModel(pinStore: store)
        second.start()
        defer { second.tabs.forEach { second.closeTab($0.id) } }
        second.selectTab(tab.id)

        let session = try #require(second.session(for: tab.id))
        #expect(session.workingDirectory.standardizedFileURL
                == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
    }
}
