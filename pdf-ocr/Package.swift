// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pdf-ocr",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "pdf-ocr", targets: ["pdf-ocr"]),
    ],
    dependencies: [
        // Names file and language-model correction, shared with dictate.
        .package(path: "../textfix"),
    ],
    targets: [
        .executableTarget(name: "pdf-ocr", dependencies: [.product(name: "TextFix", package: "textfix")]),
    ]
)
