// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "textfix",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TextFix", targets: ["TextFix"]),
        .executable(name: "textfix", targets: ["TextFixCLI"]),
    ],
    targets: [
        .target(name: "TextFix"),
        .executableTarget(name: "TextFixCLI", dependencies: ["TextFix"]),
        .testTarget(name: "TextFixTests", dependencies: ["TextFix"]),
    ]
)
