// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatterKey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChatterKey", targets: ["ChatterKey"])
    ],
    targets: [
        .target(
            name: "ChatterKeyCore",
            path: "core/Sources/ChatterKeyCore"
        ),
        .executableTarget(
            name: "ChatterKey",
            dependencies: ["ChatterKeyCore"],
            path: "apps/macos/Sources"
        )
    ]
)
