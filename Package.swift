// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iWitness",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "iWitnessCore",
            targets: ["iWitnessCore"]
        )
    ],
    targets: [
        .target(
            name: "iWitnessCore",
            dependencies: [],
            path: "iWitness/Sources"
        )
    ]
)
