// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swarm-cadence",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "swarm-cadence", targets: ["SwarmCadenceCLI"]),
        .library(name: "SwarmCadenceCore", targets: ["SwarmCadenceCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "SwarmCadenceCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .target(
            name: "SwarmCadenceCommands",
            dependencies: ["SwarmCadenceCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .executableTarget(
            name: "SwarmCadenceCLI",
            dependencies: ["SwarmCadenceCommands"]
        ),
        .testTarget(
            name: "SwarmCadenceTests",
            dependencies: ["SwarmCadenceCore", "SwarmCadenceCommands"]
        )
    ]
)
