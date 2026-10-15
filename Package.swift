// swift-tools-version: 6.2
import Foundation
import PackageDescription

let sweetCookieKitPath = "../SweetCookieKit"
let useLocalSweetCookieKit =
    ProcessInfo.processInfo.environment["CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT"] == "1"
let sweetCookieKitDependency: Package.Dependency =
    useLocalSweetCookieKit && FileManager.default.fileExists(atPath: sweetCookieKitPath)
    ? .package(path: sweetCookieKitPath)
    : .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.5.7")

let package = Package(
    name: "CodexBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: {
        var products: [Product] = [
            .library(name: "CodexBarCore", targets: ["CodexBarCore"]),
            .executable(name: "CodexBarCLI", targets: ["CodexBarCLI"]),
        ]

        #if os(macOS)
        products.append(contentsOf: [
            .executable(name: "CodexBar", targets: ["CodexBar"]),
            .executable(name: "CodexBarClaudeWatchdog", targets: ["CodexBarClaudeWatchdog"]),
            .executable(name: "CodexBarWidget", targets: ["CodexBarWidget"]),
        ])
        #endif

        return products
    }(),
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
        .package(url: "https://github.com/steipete/Commander", from: "0.2.4"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.15.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        .package(url: "https://github.com/zats/Vortex", revision: "ef5392088d4aeb255c4eee83157dbdafcd31bf07"),
        sweetCookieKitDependency,
    ],
    targets: {
        var targets: [Target] = [
            .target(
                name: "CodexBarCore",
                dependencies: [
                    .product(name: "Crypto", package: "swift-crypto"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "CodexBarCLI",
                dependencies: [
                    "CodexBarCore",
                    .product(name: "Commander", package: "Commander"),
                    .product(name: "Crypto", package: "swift-crypto"),
                ],
                path: "Sources/CodexBarCLI",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            // Crash-test subprocess: tests SIGKILL it mid-save to prove the cost store's
            // save cycle is atomic. Not shipped; built only as a test dependency.
            .executableTarget(
                name: "CodexBarCostStoreCrashProbe",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarCostStoreCrashProbe",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            // Sole owner of the adaptive refresh decision table. Package-internal; not published as a library product.
            .target(
                name: "AdaptiveRefreshCore",
                dependencies: [],
                path: "Sources/AdaptiveRefreshCore",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
        ]

        #if os(macOS)
        targets.append(contentsOf: [
            .executableTarget(
                name: "CodexBarClaudeWatchdog",
                dependencies: [],
                path: "Sources/CodexBarClaudeWatchdog",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "CodexBar",
                dependencies: [
                    .product(name: "Sparkle", package: "Sparkle"),
                    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                    .product(name: "Vortex", package: "Vortex"),
                    "AdaptiveRefreshCore",
                    "CodexBarCore",
                ],
                path: "Sources/CodexBar",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    // Opt into Swift 6 strict concurrency (approachable migration path).
                    .enableUpcomingFeature("StrictConcurrency"),
                    .define("ENABLE_SPARKLE"),
                ]),
            .executableTarget(
                name: "CodexBarWidget",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarWidget",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
        ])

        let testSwiftSettings: [SwiftSetting] = [
            .enableUpcomingFeature("StrictConcurrency"),
            .enableExperimentalFeature("SwiftTesting"),
        ]
        // Test code is split by what it imports so an edit recompiles one test module instead of all of them.
        // Only test targets may depend on the app executables, so shared helpers stay CodexBarCore-only:
        // anything that needs `@testable import CodexBar` lives in CodexBarTests.
        targets.append(contentsOf: [
            // Helpers and fixtures shared by several test targets. Its sources are `#if DEBUG`-guarded because
            // `swift build -c release` also compiles test targets that other test targets depend on.
            .testTarget(
                name: "CodexBarTestSupport",
                dependencies: ["CodexBarCore"],
                path: "Tests/CodexBarTestSupport",
                swiftSettings: testSwiftSettings),
            .testTarget(
                name: "CodexBarCoreTests",
                dependencies: [
                    "CodexBarCore", "CodexBarTestSupport",
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                path: "Tests/CodexBarCoreTests",
                resources: [.copy("Fixtures")],
                swiftSettings: testSwiftSettings),
            .testTarget(
                name: "CodexBarCostUsageTests",
                dependencies: ["CodexBarCore", "CodexBarCostStoreCrashProbe", "CodexBarTestSupport"],
                path: "Tests/CodexBarCostUsageTests",
                resources: [.copy("Fixtures")],
                swiftSettings: testSwiftSettings),
            .testTarget(
                name: "CodexBarClaudeTests",
                dependencies: [
                    "CodexBarCore", "CodexBarTestSupport",
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                path: "Tests/CodexBarClaudeTests",
                resources: [.copy("Fixtures")],
                swiftSettings: testSwiftSettings),
            .testTarget(
                name: "CodexBarCodexTests",
                // CodexBarCLI is launched as a built product, not imported.
                dependencies: ["CodexBarCore", "CodexBarCLI", "CodexBarTestSupport"],
                path: "Tests/CodexBarCodexTests",
                swiftSettings: testSwiftSettings),
            .testTarget(
                name: "CodexBarCLITests",
                dependencies: [
                    "CodexBarCLI", "CodexBarCore", "CodexBarTestSupport",
                    .product(name: "Commander", package: "Commander"),
                ],
                path: "Tests/CodexBarCLITests",
                resources: [.copy("Fixtures")],
                swiftSettings: testSwiftSettings),
            // App, menu, widget and store tests: everything that needs `@testable import CodexBar`.
            .testTarget(
                name: "CodexBarTests",
                dependencies: [
                    "CodexBar", "CodexBarCore", "CodexBarCLI", "CodexBarCostStoreCrashProbe", "CodexBarWidget",
                    "CodexBarTestSupport",
                    .product(name: "Sparkle", package: "Sparkle"),
                ],
                path: "Tests/CodexBarTests",
                resources: [.copy("Fixtures")],
                swiftSettings: testSwiftSettings,
                linkerSettings: [
                    // XCTest's executable is three directories below its sibling framework products.
                    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."]),
                ]),
        ])
        #endif

        return targets
    }())
