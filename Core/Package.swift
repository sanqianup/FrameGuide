// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CompositionCore",
    products: [.library(name: "CompositionCore", targets: ["CompositionCore"])],
    targets: [
        .target(name: "CompositionCore"),
        .testTarget(name: "CompositionCoreTests", dependencies: ["CompositionCore"])
    ]
)
