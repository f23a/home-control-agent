// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HomeControlShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "HomeControlShared",
            targets: ["HomeControlShared"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/f23a/home-control-client.git", from: "1.6.0")
//        .package(path: "../../home-control-client")
    ],
    targets: [
        .target(
            name: "HomeControlShared",
            dependencies: [
                .product(name: "HomeControlClient", package: "home-control-client")
            ]
        ),
        .testTarget(
            name: "HomeControlSharedTests",
            dependencies: ["HomeControlShared"]
        )
    ]
)
