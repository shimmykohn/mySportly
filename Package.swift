// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SportlyCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SportlyCore", targets: ["SportlyCore"])],
    targets: [
        .target(name: "SportlyCore", path: "mySportly/Core"),
        .target(name: "SportlyPersistence", dependencies: ["SportlyCore"], path: "mySportly/Persistence", exclude: ["SecureStorage.swift"]),
        .testTarget(name: "SportlyCoreTests", dependencies: ["SportlyCore"], path: "CoreTests"),
        .testTarget(name: "SportlyPersistenceTests", dependencies: ["SportlyPersistence", "SportlyCore"], path: "PersistenceTests")
    ]
)
