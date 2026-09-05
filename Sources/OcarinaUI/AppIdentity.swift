import Foundation

/// What this build calls itself.
///
/// The name was written out as "Ocarina" at every point it appeared: the
/// window title, the app menu and its About / Hide / Quit items, the
/// keep-awake assertion. That was fine while there was one app. The debug
/// build is a second one — its own bundle identifier, installed beside the
/// release app — and it went on calling itself Ocarina in exactly the places
/// you look to tell two running copies apart.
///
/// The bundle already carries the answer, so read it from there. A bare
/// `swift run Ocarina` has no Info.plist to read and falls back to the name.
public enum AppIdentity {
    /// "Ocarina", or "Ocarina Test Build" for the debug bundle.
    public static let name: String = {
        let info = Bundle.main.infoDictionary
        let stated = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? ""
        return stated.isEmpty ? "Ocarina" : stated
    }()

    /// The product, without any build qualifier. This is the brand, and it is
    /// the same word whichever build you are running.
    public static let product = "Ocarina"

    /// What marks this build out, if anything — "Test Build" for the debug
    /// bundle, nil for the release.
    ///
    /// Kept apart from `product` so the wordmark can lead with the name and
    /// carry the qualifier as a badge. Set as one string it truncated to
    /// "Ocarina Test Bui…" in a 165pt column, which is the worst of both.
    public static var variant: String? {
        guard name != product else { return nil }
        guard name.hasPrefix(product) else { return name }
        let rest = name.dropFirst(product.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// Reads as a sentence in `pmset -g assertions`, which is the point of
    /// naming the assertion at all.
    public static var sleepReason: String { "\(name) is open" }
}
