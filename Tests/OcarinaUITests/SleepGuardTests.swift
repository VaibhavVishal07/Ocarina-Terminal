import Foundation
import IOKit.pwr_mgt
import Testing
@testable import OcarinaUI

/// Records what the guard asked power management to do.
@MainActor
private final class FakeAssertion: DisplaySleepAssertion {
    private(set) var reasons: [String] = []
    private(set) var released: [IOPMAssertionID] = []
    var isRefusing = false
    private var nextID: IOPMAssertionID = 1

    func create(reason: String) -> IOPMAssertionID? {
        guard !isRefusing else { return nil }
        reasons.append(reason)
        defer { nextID += 1 }
        return nextID
    }

    func release(_ id: IOPMAssertionID) {
        released.append(id)
    }
}

@Suite("Keeping the Mac awake")
@MainActor
struct SleepGuardTests {

    @Test("Ocarina holds the Mac awake from the moment it starts")
    func onByDefault() {
        let fake = FakeAssertion()
        let guardian = SleepGuard(assertion: fake, reason: "Ocarina is open")

        #expect(guardian.isEnabled)
        #expect(!guardian.isHolding)   // nothing taken until start()

        guardian.start()

        #expect(guardian.isHolding)
        #expect(fake.reasons == ["Ocarina is open"])
    }

    @Test("Starting twice does not stack a second assertion")
    func startIsIdempotent() {
        let fake = FakeAssertion()
        let guardian = SleepGuard(assertion: fake)

        guardian.start()
        guardian.start()

        // A second id would have to be released twice, and the first would
        // outlive every attempt to switch the feature off.
        #expect(fake.reasons.count == 1)
        #expect(guardian.isHolding)
    }

    @Test("Switching it off gives the assertion straight back")
    func disablingReleases() {
        let fake = FakeAssertion()
        let guardian = SleepGuard(assertion: fake)
        guardian.start()

        guardian.isEnabled = false

        #expect(fake.released.count == 1)
        #expect(!guardian.isHolding)
    }

    @Test("Switching it back on takes a fresh assertion")
    func reEnablingTakesAnother() {
        let fake = FakeAssertion()
        let guardian = SleepGuard(assertion: fake)
        guardian.start()
        guardian.isEnabled = false

        guardian.isEnabled = true

        #expect(fake.reasons.count == 2)
        #expect(guardian.isHolding)
    }

    @Test("Starting while switched off takes nothing")
    func startRespectsDisabled() {
        let fake = FakeAssertion()
        let guardian = SleepGuard(assertion: fake, isEnabled: false)

        guardian.start()

        #expect(fake.reasons.isEmpty)
        #expect(!guardian.isHolding)
    }

    @Test("A refused assertion is never reported as holding")
    func refusedAssertion() {
        let fake = FakeAssertion()
        fake.isRefusing = true
        let guardian = SleepGuard(assertion: fake)

        guardian.start()

        // The cup must not claim the Mac is being kept awake when it is not.
        #expect(guardian.isEnabled)
        #expect(!guardian.isHolding)
    }

    @Test("Releasing twice is harmless")
    func stopIsIdempotent() {
        let fake = FakeAssertion()
        let guardian = SleepGuard(assertion: fake)
        guardian.start()

        guardian.stop()
        guardian.stop()

        #expect(fake.released.count == 1)
    }

    @Test("The real assertion reaches power management, and is named")
    func liveAssertionIsVisibleToPmset() throws {
        let reason = "Ocarina test \(UUID().uuidString)"
        let guardian = SleepGuard(assertion: IOKitDisplaySleepAssertion(), reason: reason)

        guardian.start()
        try #require(guardian.isHolding)
        #expect(try pmsetAssertions().contains(reason))

        guardian.stop()
        #expect(!(try pmsetAssertions().contains(reason)))
    }

    private func pmsetAssertions() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
