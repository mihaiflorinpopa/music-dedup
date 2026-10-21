// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MusicDedup",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MusicDedup", targets: ["MusicDedup"]),
        .library(name: "MusicDedupCore", targets: ["MusicDedupCore"]),
    ],
    dependencies: [
        // Auto-updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "MusicDedupCore"),
        .executableTarget(
            name: "MusicDedup",
            dependencies: ["MusicDedupCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework is copied into Music Dedup.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MusicDedupCoreTests", dependencies: ["MusicDedupCore"]),
    ]
)
