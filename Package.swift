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
    targets: [
        .target(name: "SwarmCadenceCore"),
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
