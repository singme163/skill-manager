// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("BareSlashRegexLiterals"),
]

let package = Package(
    name: "SkillManager",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SkillManagerCore",
            resources: [.copy("Resources/skills-index.json")],
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
