// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JobScout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "JobScout", targets: ["JobScoutApp"]),
        .executable(name: "jobscout-cli", targets: ["JobScoutCLI"]),
        .library(name: "JobScoutCore", targets: ["JobScoutCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")
    ],
    targets: [
        .target(name: "JobScoutCore", dependencies: ["SwiftSoup"]),
        .executableTarget(name: "JobScoutCLI", dependencies: ["JobScoutCore"]),
        .executableTarget(name: "JobScoutApp", dependencies: ["JobScoutCore"]),
    ]
)
