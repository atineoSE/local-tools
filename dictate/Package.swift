// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "dictate",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "dictate", targets: ["dictate"]),
    ],
    targets: [
        .target(name: "DictateCore"),
        .executableTarget(name: "dictate", dependencies: ["DictateCore"]),
        .testTarget(name: "DictateCoreTests", dependencies: ["DictateCore"]),
    ]
)
