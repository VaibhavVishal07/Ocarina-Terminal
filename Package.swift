// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ocarina",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OcarinaTerminalContext", targets: ["OcarinaTerminalContext"]),
        .executable(name: "Ocarina", targets: ["Ocarina"])
    ],
    dependencies: [
        // Terminal emulation only: the VT parser and screen grid.
        // Ocarina owns the pty itself, because naming needs the descriptor.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .target(name: "OcarinaTerminalContext"),
        .target(
            name: "OcarinaUI",
            dependencies: [
                "OcarinaTerminalContext",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            // `.process` flattens a directory tree into the bundle root, which
            // loses the `Themes/` subdirectory the loader looks in. The icon is
            // still processed; the themes are copied verbatim so their folder
            // survives.
            resources: [
                .process("Resources/AppIcon.png"),
                .copy("Resources/Themes"),
                .copy("Resources/Recipes"),
                .copy("Resources/Fonts"),
            ]
        ),
        .executableTarget(name: "Ocarina", dependencies: ["OcarinaUI"]),
        .testTarget(
            name: "OcarinaTerminalContextTests",
            dependencies: ["OcarinaTerminalContext"]
        ),
        .testTarget(name: "OcarinaUITests", dependencies: ["OcarinaUI"])
    ]
)
