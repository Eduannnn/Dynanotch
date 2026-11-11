// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dynanotch",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "Dynanotch", targets: ["NotchMac"]),
        .library(name: "NotchCore", targets: ["NotchCore"])
    ],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "NotchMac", dependencies: ["NotchCore"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"])
    ],
    swiftLanguageModes: [.v5]
)
