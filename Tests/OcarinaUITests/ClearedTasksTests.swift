import Foundation
import Testing
@testable import OcarinaUI

/// The line drawn under a project's task list.
@Suite("Clearing tasks")
struct ClearedTasksTests {

    private func makeStore() throws -> (ClearedTasks, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina-cleared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ClearedTasks(url: directory.appendingPathComponent("cleared.json")), directory)
    }

    @Test("A cleared project remembers its line across launches")
    func survivesRelaunch() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var first = store
        let project = URL(fileURLWithPath: "/tmp/some-project")
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(first.mark(for: project) == nil)
        first.clear(project, at: moment)

        let second = ClearedTasks(url: directory.appendingPathComponent("cleared.json"))
        let mark = try #require(second.mark(for: project))
        #expect(abs(mark.timeIntervalSince(moment)) < 1)
    }

    @Test("Clearing one project leaves the others alone")
    func isPerProject() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var marks = store

        marks.clear(URL(fileURLWithPath: "/tmp/one"))
        #expect(marks.mark(for: URL(fileURLWithPath: "/tmp/one")) != nil)
        #expect(marks.mark(for: URL(fileURLWithPath: "/tmp/two")) == nil)
    }

    @Test("Restoring puts a project's history back")
    func restores() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var marks = store
        let project = URL(fileURLWithPath: "/tmp/three")

        marks.clear(project)
        #expect(marks.mark(for: project) != nil)
        marks.restore(project)
        #expect(marks.mark(for: project) == nil)
    }
}
