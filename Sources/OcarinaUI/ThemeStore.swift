import AppKit
import Foundation
import Observation
import SwiftUI

/// The themes available, and which one is on.
///
/// Bundled themes ship as JSON beside the app's other resources. A user's own
/// themes live in `~/.ocarina/themes` and are read at launch, so authoring one
/// needs a text editor and nothing else — no build, no restart of anything but
/// Ocarina.
@MainActor
@Observable
public final class ThemeStore {
    public private(set) var available: [Theme]
    public private(set) var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.key) }
    }

    /// Themes that loaded but are not fit to use, with the reason. Surfaced in
    /// the picker rather than silently dropped: a theme you wrote and cannot
    /// find is worse than one listed as broken.
    public private(set) var rejected: [ThemeReport]

    private static let key = "ocarina.theme"
    private static let houseThemeID = "ocarina"

    public var theme: Theme {
        available.first { $0.id == selectedID } ?? available[0]
    }

    public init(extra: [Theme] = []) {
        var loaded = Self.bundled() + Self.userAuthored() + extra

        // A theme nobody can read is not offered. The report is kept so the
        // picker can say why.
        var bad: [ThemeReport] = []
        loaded = loaded.filter { candidate in
            let report = ThemeReport(theme: candidate)
            if report.isUsable { return true }
            bad.append(report)
            return false
        }

        // There is always a theme. If resources are missing or every file was
        // rejected, the compiled-in one stands in — the app opening wrong is
        // recoverable, the app not opening is not.
        //
        // Resolved into locals first: every stored property has to be set
        // before any of them can be read back.
        let usable = loaded.isEmpty ? [Theme.fallback] : loaded
        let saved = UserDefaults.standard.string(forKey: Self.key)

        available = usable
        rejected = bad
        // Saved choice, else the house theme, else whatever loaded. Falling
        // straight to `usable[0]` meant the alphabetically first file won, so a
        // fresh install opened in High Contrast — a theme for people who need
        // it, and a strange first impression for everyone else.
        selectedID = usable.first { $0.id == saved }?.id
            ?? usable.first { $0.id == Self.houseThemeID }?.id
            ?? usable[0].id
    }

    public func select(_ id: String) {
        guard available.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Where a user drops their own themes.
    public static var userDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ocarina/themes", isDirectory: true)
    }

    // MARK: - Loading

    private static func bundled() -> [Theme] {
        guard let urls = Bundle.module.urls(
            forResourcesWithExtension: "json",
            subdirectory: "Themes"
        ) else { return [] }
        return decode(urls).sorted { $0.name < $1.name }
    }

    private static func userAuthored() -> [Theme] {
        let directory = userDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        let urls = names
            .filter { $0.hasSuffix(".json") }
            .map { directory.appendingPathComponent($0) }
        return decode(urls).sorted { $0.name < $1.name }
    }

    private static func decode(_ urls: [URL]) -> [Theme] {
        let decoder = JSONDecoder()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Theme.self, from: data)
        }
    }
}

// MARK: - The one that cannot be missing

public extension Theme {
    /// Today's look, compiled in.
    ///
    /// Duplicating a bundled file is the point: this is the theme that applies
    /// when resource loading has already failed, so it cannot itself depend on
    /// a resource loading.
    static let fallback = Theme(
        id: "ocarina",
        name: "Ocarina",
        isDark: true,
        terminal: Terminal(
            background: ThemeColor(hex: "#12171E"),
            foreground: ThemeColor(hex: "#C9D4E0"),
            cursor: ThemeColor(hex: "#4FC0EC"),
            selection: ThemeColor(hex: "#2A3A4A"),
            ansi: [
                "#5A6675", "#F06C6C", "#5FC98D", "#E5B25A",
                "#5AA9F0", "#C08CE8", "#4FC0EC", "#C9D4E0",
                "#7A8798", "#FF9090", "#84E0AC", "#F5CD84",
                "#84C4F5", "#D6AFF2", "#84D8F5", "#EDF2F7",
            ].map(ThemeColor.init(hex:)),
            fontName: "Geist Mono",
            fontSize: 13
        ),
        chrome: Chrome(
            panelTop: ThemeColor(hex: "#202224"),
            panelBottom: ThemeColor(hex: "#141517"),
            bed: ThemeColor(hex: "#000000"),
            bedOpacity: 0.72,
            rowHover: ThemeColor(hex: "#FFFFFF"),
            rowSelected: ThemeColor(hex: "#FFFFFF"),
            border: ThemeColor(hex: "#FFFFFF"),
            textPrimary: ThemeColor(hex: "#F2F5F8"),
            textSecondary: ThemeColor(hex: "#A8B2BE"),
            textTertiary: ThemeColor(hex: "#77818D"),
            accent: ThemeColor(hex: "#216B95")
        ),
        status: Status(
            idle: ThemeColor(hex: "#87C7FF"),
            running: ThemeColor(hex: "#5CA8FF"),
            succeeded: ThemeColor(hex: "#4CC773"),
            failed: ThemeColor(hex: "#F25959")
        ),
        board: Board(
            lit: ThemeColor(hex: "#38C2FF"),
            litDim: ThemeColor(hex: "#216B95"),
            unlit: ThemeColor(hex: "#191C22"),
            backdrop: ThemeColor(hex: "#060709"),
            highlight: ThemeColor(hex: "#FFB838")
        ),
        typography: nil,
        pattern: Motif(shape: .notes, opacity: 0.05, scale: 13, color: ThemeColor(hex: "#38C2FF"))
    )
}

// MARK: - Reaching the views

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.fallback
}

public extension EnvironmentValues {
    /// Read by every view that draws anything. Set once, at the window's root.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
