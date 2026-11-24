// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IMContracts",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "IMContracts", targets: ["IMContracts"])
    ],
    targets: [
        .target(name: "IMContracts"),
        .testTarget(
            name: "IMContractsTests",
            dependencies: ["IMContracts"]
        )
    ]
)
