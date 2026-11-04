// swift-tools-version: 6.2
import PackageDescription
import Foundation

let localSparkleArtifactPath = ".local-artifacts/sparkle/Sparkle.xcframework"
let environment = ProcessInfo.processInfo.environment
let prefersLocalSparkleArtifact = environment["APPWINK_USE_LOCAL_SPARKLE_ARTIFACT"] == "1"
let hasLocalSparkleArtifact = FileManager.default.fileExists(atPath: localSparkleArtifactPath)
let usesLocalSparkleArtifact = prefersLocalSparkleArtifact && hasLocalSparkleArtifact

let packageDependencies: [Package.Dependency] = usesLocalSparkleArtifact
    ? []
    : [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.1"),
    ]

let appWinkDirectDependencies: [Target.Dependency] = usesLocalSparkleArtifact
    ? [
        "AppWinkRuntime",
        "Sparkle",
    ]
    : [
        "AppWinkRuntime",
        .product(name: "Sparkle", package: "Sparkle"),
    ]

let packageTargets: [Target] = (usesLocalSparkleArtifact
    ? [
        .binaryTarget(
            name: "Sparkle",
            path: localSparkleArtifactPath),
    ]
    : []) + [
        .target(
            name: "AppWinkCore",
            path: "Sources/AppWinkCore"),
        .target(
            name: "AppWinkRuntime",
            dependencies: ["AppWinkCore"],
            path: "Sources/AppWink"),
        .executableTarget(
            name: "AppWink",
            dependencies: appWinkDirectDependencies,
            path: "Sources/AppWinkDirect"),
        .testTarget(
            name: "AppWinkTests",
            dependencies: ["AppWinkRuntime"],
            path: "Tests/AppWinkTests"),
        .testTarget(
            name: "AppWinkCoreTests",
            dependencies: ["AppWinkCore"],
            path: "Tests/AppWinkCoreTests"),
    ]

let package = Package(
    name: "AppWink",
    defaultLocalization: "zh-Hans",  // 默认使用简体中文
    platforms: [
        .macOS(.v14),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
