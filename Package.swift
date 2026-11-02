// swift-tools-version: 6.0
import Foundation
import PackageDescription

// With Command Line Tools only (no Xcode), `swift test` sometimes fails to
// find the swift-testing macro plugin ("plugin for module 'TestingMacros' not
// found"). Passing the plugin directory explicitly makes it load every time.
// The flag is added only when Command Line Tools are the active developer
// directory, so Xcode builds use their own toolchain's plugin.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let activeDeveloperDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
    ?? ""
// xcode-select falls back to Command Line Tools when its link points at a
// removed Xcode, so a missing target directory also means CLT.
let usingCommandLineTools = activeDeveloperDir.hasPrefix("/Library/Developer/CommandLineTools")
    || !FileManager.default.fileExists(atPath: activeDeveloperDir)
let testSwiftSettings: [SwiftSetting] =
    usingCommandLineTools && FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])]
    : []

let package = Package(
    name: "EdgeGlide",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EdgeGlide", targets: ["EdgeGlide"]),
        .library(name: "EdgeGlideCore", targets: ["EdgeGlideCore"]),
    ],
    targets: [
        // Pure logic. No private frameworks, no AppKit.
        .target(name: "EdgeGlideCore"),
        // The menu bar app: touch monitor, system controls, UI.
        .executableTarget(
            name: "EdgeGlide",
            dependencies: ["EdgeGlideCore"]
        ),
        .testTarget(
            name: "EdgeGlideCoreTests",
            dependencies: ["EdgeGlideCore"],
            swiftSettings: testSwiftSettings
        ),
    ]
)
