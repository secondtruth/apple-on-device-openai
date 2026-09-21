// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OnDeviceServer",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OnDeviceServer", targets: ["OnDeviceServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0")
    ],
    targets: [
        .target(
            name: "OnDeviceServer",
            dependencies: [.product(name: "Vapor", package: "vapor")]
        ),
        .testTarget(
            name: "OnDeviceServerTests",
            dependencies: ["OnDeviceServer"]
        ),
    ]
)
