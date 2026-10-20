// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanYourMacCore", targets: ["CleanYourMacCore"]),
        .executable(name: "cym", targets: ["cym"]),
    ],
    targets: [
        .target(name: "CleanYourMacCore"),
        .executableTarget(name: "cym", dependencies: ["CleanYourMacCore"]),
        .testTarget(name: "CleanYourMacCoreTests", dependencies: ["CleanYourMacCore"]),
    ]
)
