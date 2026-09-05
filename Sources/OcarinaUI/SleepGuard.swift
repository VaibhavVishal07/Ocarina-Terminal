import Foundation
import IOKit.pwr_mgt
import Observation

/// Takes and gives back the system's "do not let the display sleep" assertion.
///
/// Injected, so tests can drive `SleepGuard` without asking real power
/// management to keep the machine awake for the length of a test run.
@MainActor
public protocol DisplaySleepAssertion {
    /// The new assertion's id, or nil if the system refused it.
    func create(reason: String) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

/// The real thing: the same assertion `caffeinate -d` holds.
public struct IOKitDisplaySleepAssertion: DisplaySleepAssertion {
    public init() {}

    public func create(reason: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    public func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
    }
}

/// Keeps the Mac awake for as long as Ocarina is open.
///
/// A terminal is usually waiting on something long — a build, a test run, an
/// agent working through a task — and a display that sleeps through it is never
/// what was wanted. So this is on by default rather than something to remember
/// to switch on, which is the whole reason people keep a `caffeinate` running
/// in a spare tab.
///
/// The assertion is named, so `pmset -g assertions` reports that it is Ocarina
/// holding the machine awake instead of leaving it a mystery.
@MainActor
@Observable
public final class SleepGuard {
    /// On by default. Turning it off gives the assertion back immediately.
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { take() } else { drop() }
        }
    }

    /// Whether an assertion is actually held. This is not the same as
    /// `isEnabled`: the system can refuse one, and the UI should not claim the
    /// Mac is being kept awake when it is not.
    public private(set) var isHolding = false

    @ObservationIgnored private var assertionID: IOPMAssertionID?
    @ObservationIgnored private let assertion: DisplaySleepAssertion
    @ObservationIgnored private let reason: String

    public init(
        assertion: DisplaySleepAssertion = IOKitDisplaySleepAssertion(),
        reason: String = "Ocarina is open",
        isEnabled: Bool = true
    ) {
        self.assertion = assertion
        self.reason = reason
        // Property observers do not run during init, so nothing is taken until
        // `start()`. The app decides when the assertion begins.
        self.isEnabled = isEnabled
    }

    /// Takes the assertion if enabled. Safe to call more than once.
    public func start() {
        guard isEnabled else { return }
        take()
    }

    /// Gives the assertion back. The kernel drops a process's assertions when it
    /// exits, so this is for turning the feature off, not for shutdown.
    public func stop() {
        drop()
    }

    private func take() {
        // Never stack assertions: a second id would have to be released twice,
        // and the first would outlive every attempt to switch this off.
        guard assertionID == nil else { return }
        assertionID = assertion.create(reason: reason)
        isHolding = assertionID != nil
    }

    private func drop() {
        guard let id = assertionID else { return }
        assertion.release(id)
        assertionID = nil
        isHolding = false
    }
}
