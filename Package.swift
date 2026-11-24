// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = []

let package = Package(
    name: "Chitter",
    platforms: [.macOS("14.4")],
    products: [.executable(name: "Chitter", targets: ["EchoApp"])],
    targets: [
        .target(name: "EchoNet"),
        .target(name: "EchoCore", dependencies: ["EchoNet"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "EchoAudio", dependencies: ["EchoCore"]),
        .target(name: "EchoASR", dependencies: ["EchoCore", "EchoAudio"]),
        .target(name: "EchoLang", dependencies: ["EchoCore", "EchoNet"]),
        .target(name: "EchoNotes", dependencies: ["EchoCore", "EchoNet"]),
        .target(name: "EchoVoice", dependencies: ["EchoCore", "EchoAudio", "EchoNet"]),
        .target(name: "EchoUI", dependencies: ["EchoCore", "EchoNotes", "EchoLang"]),
        .executableTarget(name: "EchoApp",
            dependencies: ["EchoCore", "EchoAudio", "EchoASR", "EchoLang", "EchoNotes", "EchoVoice", "EchoNet", "EchoUI"]),
        .testTarget(name: "EchoCoreTests", dependencies: ["EchoCore"]),
        .testTarget(name: "EchoNotesTests", dependencies: ["EchoNotes", "EchoCore"]),
        .testTarget(name: "EchoNetTests", dependencies: ["EchoNet"]),
        .testTarget(name: "EchoUITests", dependencies: ["EchoUI"]),
    ],
    swiftLanguageModes: [.v5]
)
