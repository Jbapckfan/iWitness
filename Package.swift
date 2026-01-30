// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OnTheRecord",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
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
            path: "OnTheRecord/Sources",
            exclude: ["Views/Components/CameraPreviewView.swift"]
        ),
        .target(
            name: "OnTheRecordWatch",
            dependencies: [],
            path: "OnTheRecordWatch/Sources"
        ),
        .testTarget(
            name: "OnTheRecordTests",
            dependencies: ["OnTheRecordCore"],
            path: "Tests/OnTheRecordTests"
        )
    ]
)
