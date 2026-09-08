import AppKit
import Foundation
import Observation
import OcarinaTerminalContext
import UserNotifications

/// Somewhere to send a notification. Injected so the tests never touch the real
/// notification centre — `UNUserNotificationCenter.current()` needs a bundle,
/// and a test binary is not one.
@MainActor
public protocol NotificationPoster: AnyObject {
    /// Asks once. Returns whether we may post.
    func authorize() async -> Bool
    func post(title: String, body: String, id: String)
}

/// The real one.
@MainActor
public final class SystemNotificationPoster: NotificationPoster {
    public init() {}

    /// Whether this process can post at all.
    ///
    /// `UNUserNotificationCenter.current()` does not fail politely without a
    /// bundle identifier — it aborts the process. A SwiftPM executable run
    /// straight out of `.build`, and the test binary, are both in exactly that
    /// state, so the check has to come before the call rather than around it.
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    public func authorize() async -> Bool {
        guard isBundled else { return false }
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    public func post(title: String, body: String, id: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // No sound. The thing that prompts most of these already rang the
        // terminal bell, and a notification that beeps a second time for the
        // same event is the noise this feature exists to remove.
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }
}

/// Tells you the few things worth interrupting you for.
///
/// ## What it will not do
///
/// Notify about anything you can see. A notification for a window you are
/// looking at is not information, it is a second copy of the screen — so
/// nothing is posted while Ocarina is the app in front. Everything here is
/// already said in the window: the tab's dot, the rail over the terminal, the
/// card in the menu bar. This is only for when none of those are in view.
///
/// ## What it will
///
/// Three moments, and they are the three the states already distinguish: a tab
/// **asking for you**, a tab that **came back**, and a command that **stopped
/// badly**. Not every command, not output, not a shell reaching a prompt — a
/// terminal reaches a prompt a hundred times an hour and none of them are news.
///
/// ## Asking for permission
///
/// Not at launch. macOS asks on the first post, which is the first moment the
/// answer means anything — a permission sheet in front of a window you have
/// only just opened is a question about a thing you have not seen yet.
@MainActor
@Observable
public final class Notifier {
    /// Whether to post at all. Persisted, and on by default: the feature is
    /// worth nothing to somebody who never finds the switch, and the system's
    /// own permission prompt is the real opt-in.
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
        }
    }

    private static let key = "ocarina.notifications.enabled"

    @ObservationIgnored private let poster: NotificationPoster
    /// Whether the system has been asked yet, and what it said.
    @ObservationIgnored private var allowed: Bool?
    /// Whether Ocarina is the app in front. Injected so a test can say.
    @ObservationIgnored private let isAppActive: @MainActor () -> Bool

    public init(
        poster: NotificationPoster? = nil,
        defaults: UserDefaults = .standard,
        // `NSApp` is nil until an application object exists, and it is an
        // implicitly unwrapped global — reading `.isActive` off it traps. A
        // process with no application has no window in front of anybody, so
        // the honest answer there is "not active".
        isAppActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    ) {
        self.poster = poster ?? SystemNotificationPoster()
        self.isAppActive = isAppActive
        self.isEnabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    /// The three things worth saying, and the words for each.
    ///
    /// The house lines, not the theme's. A notification is read on a lock
    /// screen beside mail and calendar alerts, further outside Ocarina than
    /// even the menu bar is — and the same rule applies harder: a theme being
    /// arch there costs somebody the one reading they came for. See
    /// `ActivityStatusItem.title(for:)`, which settled this once already.
    public enum Moment: Equatable {
        case needsYou
        case backToYou
        case failed(exitCode: Int)

        var line: String {
            switch self {
            case .needsYou: "Needs you"
            case .backToYou: "Back to you"
            case let .failed(code): "Stopped (\(code))"
            }
        }

        /// Whether this is worth waking somebody for, given what they can see.
        ///
        /// All three are, once Ocarina is not in front. The gate is deliberately
        /// not per-state: a rule that posted for failures but not for a finished
        /// run would be the app deciding which of your asks mattered.
        static func worthSaying(_ activity: TabActivity) -> Moment? {
            switch activity {
            case .needsYou: .needsYou
            case .succeeded: .backToYou
            case let .failed(code): .failed(exitCode: code)
            case .idle, .running: nil
            }
        }
    }

    /// Says one thing about one tab, if it is worth saying.
    ///
    /// `tab` is the name, which is the whole of what identifies the session —
    /// it is the ask you made, which is exactly the thing you are waiting on.
    public func say(_ moment: Moment, about tab: String, id: UUID) {
        guard isEnabled, !isAppActive() else { return }
        let title = moment.line
        let body = tab
        Task { [poster] in
            if allowed == nil { allowed = await poster.authorize() }
            guard allowed == true else { return }
            // The tab's id, so a second notification about the same session
            // replaces the first rather than stacking under it. Four asks
            // coming back while you are at lunch should be four lines, not
            // forty.
            poster.post(title: title, body: body, id: id.uuidString)
        }
    }
}
