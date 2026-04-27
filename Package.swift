// swift-tools-version: 5.9

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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")
    ],
    targets: [
        .target(
            name: "SwarmCadenceCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "SwarmCadenceCLI",
            dependencies: ["SwarmCadenceCore"]
        ),
        .testTarget(
            name: "SwarmCadenceTests",
            dependencies: ["SwarmCadenceCore"]
        )
    ]
)
