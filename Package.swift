// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ARJArchive",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "ARJArchive",
            targets: ["ARJArchive"]
        ),
        .executable(
            name: "arj",
            targets: ["arj"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ARJArchive",
            dependencies: ["CARJCore"]
        ),
        .target(
            name: "CARJCore",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "ARJArchiveTests",
            dependencies: ["ARJArchive"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .executableTarget(
            name: "arj",
            dependencies: [
                "ARJArchive",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "arjTests",
            dependencies: ["arj"],
            resources: [
                .copy("Snapshots"),
            ]
        ),
    ]
)
