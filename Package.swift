// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriveStation",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DriveStation", targets: ["DriveStation"])],
    targets: [
        .executableTarget(name: "DriveStation"),
        .testTarget(name: "DriveStationTests", dependencies: ["DriveStation"])
    ]
)
