// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Majora",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MajoraTerminalContext", targets: ["MajoraTerminalContext"]),
        .executable(name: "Majora", targets: ["Majora"])
    ],
    dependencies: [
        // Terminal emulation only: the VT parser and screen grid.
        // Majora owns the pty itself, because naming needs the descriptor.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .target(name: "MajoraTerminalContext"),
        .target(
            name: "MajoraUI",
            dependencies: [
                "MajoraTerminalContext",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .executableTarget(name: "Majora", dependencies: ["MajoraUI"]),
        .testTarget(
            name: "MajoraTerminalContextTests",
            dependencies: ["MajoraTerminalContext"]
        ),
        .testTarget(name: "MajoraUITests", dependencies: ["MajoraUI"])
    ]
)
