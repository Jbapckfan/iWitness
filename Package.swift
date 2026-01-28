// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OnTheRecord",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "OnTheRecordCore",
            targets: ["OnTheRecordCore"]
        )
    ],
    targets: [
        .target(
            name: "OnTheRecordCore",
            dependencies: [],
            path: "OnTheRecord/Sources"
        )
    ]
)
