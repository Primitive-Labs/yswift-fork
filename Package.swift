// swift-tools-version:5.6

import PackageDescription
import Foundation

var globalSwiftSettings: [PackageDescription.SwiftSetting] = []

// Only enable if Swift 5.7+ is available and the environment variable `LOCALDEV` is
// set to a value (such as 'true')
#if swift(>=5.7)
    if ProcessInfo.processInfo.environment["YSWIFT_LOCAL"] != nil {
        /*
        Summation from https://www.donnywals.com/enabling-concurrency-warnings-in-xcode-14/
        Set `strict-concurrency` to `targeted` to enforce Sendable and actor-isolation
        checks in your code. This explicitly verifies that `Sendable` constraints are
        met when you mark one of your types as `Sendable`.

        This mode is essentially a bit of a hybrid between the behavior that's intended
        in Swift 6, and the default in Swift 5.7. Use this mode to have a bit of
        checking on your code that uses Swift concurrency without too many warnings
        and / or errors in your current codebase.

        Set `strict-concurrency` to `complete` to get the full suite of concurrency
        constraints, essentially as they will work in Swift 6.
        */
        globalSwiftSettings.append(.unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"]))
    }
#endif

// Always use the local xcframework. The remote release (0.5.3) is out of date
// with the scaffold code — we've patched map.get() and added observeUpdateV1.
// To rebuild: cd lib && cargo build --target aarch64-apple-darwin --release
// Then copy lib/target/aarch64-apple-darwin/release/libuniffi_yniffi.a into
// lib/yniffiFFI.xcframework/macos-arm64_x86_64/
let FFIbinaryTarget: PackageDescription.Target = .binaryTarget(
    name: "yniffiFFI",
    path: "./lib/yniffiFFI.xcframework"
)

let package = Package(
    name: "YSwift",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "YSwift", targets: ["YSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
        .package(url: "https://github.com/mattmassicotte/Queue", from: "0.2.1"),
    ],
    targets: [
        FFIbinaryTarget,
        .target(
            name: "Yniffi",
            dependencies: ["yniffiFFI"],
            path: "lib/swift/scaffold"
        ),
        .target(
            name: "YSwift",
            dependencies: [
                "Yniffi",
                .product(name: "Queue", package: "Queue"),
            ],
            swiftSettings: globalSwiftSettings
        ),
        .testTarget(
            name: "YSwiftTests",
            dependencies: ["YSwift"]
        ),
    ]
)
