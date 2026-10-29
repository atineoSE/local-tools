// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "dictate",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "dictate", targets: ["dictate"]),
    ],
    dependencies: [
        // Diarizer trait only: leaves out TTS and the prebuilt NemoTextProcessing binary.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0", traits: ["Diarizer"]),
    ],
    targets: [
        .target(name: "DictateCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "dictate", dependencies: ["DictateCore"]),
        .testTarget(name: "DictateCoreTests", dependencies: ["DictateCore"]),
    ]
)
