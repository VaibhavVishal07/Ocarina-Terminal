import Foundation

/// Where the target's own resources actually are, inside a built `.app`.
///
/// SwiftPM generates a `Bundle.module` accessor for this target that looks in
/// exactly two places: `Bundle.main.bundleURL/Ocarina_OcarinaUI.bundle` — the
/// root of the `.app` — and the absolute `.build` path that was baked in when it
/// compiled. Neither is usable for something people download.
///
/// The bundle root cannot hold it, because `codesign` refuses to sign a bundle
/// with anything loose at the top:
///
///     Ocarina.app: unsealed contents present in the bundle root
///
/// A symlink there is refused for the same reason. So the resources are sealed
/// where they belong, in `Contents/Resources`, and this looks for them there
/// first. `Bundle.module` remains the fallback, which is what `swift run` and
/// the test bundle use — and it is only reached if the sealed copy is absent, so
/// its `fatalError` stays out of the way.
///
/// Getting this wrong is invisible on the machine that built the app: the second
/// candidate is a real path on that disk, so it loads and everything works,
/// while every downloaded copy dies on launch. Verify with `.build` deleted.
enum PackagedResources {
    static let bundle: Bundle = {
        if let sealed = Bundle.main.resourceURL?
            .appendingPathComponent("Ocarina_OcarinaUI.bundle"),
           let bundle = Bundle(url: sealed) {
            return bundle
        }
        return Bundle.module
    }()
}
