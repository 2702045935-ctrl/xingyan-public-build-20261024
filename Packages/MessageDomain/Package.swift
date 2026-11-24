// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MessageDomain",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MessageDomain", targets: ["MessageDomain"])
    ],
    dependencies: [
        .package(path: "../IMContracts")
    ],
    targets: [
        .target(
            name: "MessageDomain",
            dependencies: [
                .product(name: "IMContracts", package: "IMContracts")
            ]
        ),
        .testTarget(
            name: "MessageDomainTests",
            dependencies: ["MessageDomain", "IMContracts"]
        )
    ]
)
