// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatterKey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChatterKey", targets: ["ChatterKey"]),
        .library(name: "ChatterKeyAndroid", type: .dynamic, targets: ["ChatterKeyAndroidBridge"])
    ],
    targets: [
        .target(
            name: "ChatterKeyCore",
            path: "core/Sources/ChatterKeyCore"
        ),
        .target(
            name: "ChatterKeyAndroidBridge",
            dependencies: ["ChatterKeyCore"],
            path: "apps/android/bridge"
        ),
        .executableTarget(
            name: "ChatterKey",
            dependencies: ["ChatterKeyCore"],
            path: "apps/macos/Sources"
        )
    ]
)
