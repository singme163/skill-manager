// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("BareSlashRegexLiterals"),
]

let package = Package(
    name: "SkillManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SkillManagerCore",
            swiftSettings: settings
        ),
        .executableTarget(
            name: "SkillManager",
            dependencies: ["SkillManagerCore"],
            swiftSettings: settings
        ),
        .testTarget(
            name: "SkillManagerCoreTests",
            dependencies: ["SkillManagerCore"],
            swiftSettings: settings
        ),
    ]
)
