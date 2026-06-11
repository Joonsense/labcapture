// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LabCapture",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LabCapture",
            path: "Sources/LabCapture"
        )
    ]
)
