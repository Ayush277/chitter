// swift-tools-version:6.0
import PackageDescription
import Foundation

// Command Line Tools' swift-build intermittently fails to find the swift-testing macro plugin for some test
// targets. When that plugin directory exists, pass it explicitly so test builds are deterministic.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])] : []

let package = Package(
    name: "Chitter",
    platforms: [.macOS("14.4")],
    products: [.executable(name: "Chitter", targets: ["EchoApp"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "EchoNet"),
        .target(name: "EchoCore", dependencies: ["EchoNet"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "EchoAudio", dependencies: ["EchoCore"]),
        .target(name: "EchoASR", dependencies: ["EchoCore", "EchoAudio", .product(name: "WhisperKit", package: "WhisperKit")]),
        .target(name: "EchoLang", dependencies: ["EchoCore", "EchoNet"]),
        .target(name: "EchoNotes", dependencies: ["EchoCore", "EchoNet"]),
        .target(name: "EchoVoice", dependencies: ["EchoCore", "EchoAudio", "EchoNet"]),
        .target(name: "EchoUI", dependencies: ["EchoCore", "EchoNotes", "EchoLang", "EchoNet"]),
        .executableTarget(name: "EchoApp",
            dependencies: ["EchoCore", "EchoAudio", "EchoASR", "EchoLang", "EchoNotes", "EchoVoice", "EchoNet", "EchoUI"]),
        .testTarget(name: "EchoCoreTests", dependencies: ["EchoCore"], swiftSettings: testSettings),
        .testTarget(name: "EchoAudioTests", dependencies: ["EchoAudio"], swiftSettings: testSettings),
        .testTarget(name: "EchoLangTests", dependencies: ["EchoLang"], swiftSettings: testSettings),
        .testTarget(name: "EchoVoiceTests", dependencies: ["EchoVoice"], swiftSettings: testSettings),
        .testTarget(name: "EchoNotesTests", dependencies: ["EchoNotes", "EchoCore"], swiftSettings: testSettings),
        .testTarget(name: "EchoNetTests", dependencies: ["EchoNet", "EchoCore"], swiftSettings: testSettings),
        .testTarget(name: "EchoUITests", dependencies: ["EchoUI"], swiftSettings: testSettings),
    ],
    swiftLanguageModes: [.v5]
)
