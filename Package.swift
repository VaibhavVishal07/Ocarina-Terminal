// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Majora",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MajoraTerminalContext", targets: ["MajoraTerminalContext"])
    ],
    targets: [
        .target(name: "MajoraTerminalContext"),
        .testTarget(
            name: "MajoraTerminalContextTests",
            dependencies: ["MajoraTerminalContext"]
        )
    ]
)
