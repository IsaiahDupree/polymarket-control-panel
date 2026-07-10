// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PolyPanel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PolyPanel",
            path: "Sources/PolyPanel"
        ),
        .testTarget(
            name: "PolyPanelTests",
            dependencies: ["PolyPanel"],
            path: "Tests/PolyPanelTests"
        )
    ]
)
