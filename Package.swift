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
        )
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
            dependencies: ["ARJArchive"]
        ),
    ]
)
