// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "skill-cli",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "skill", targets: ["CLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
    .package(url: "https://github.com/jpsim/Yams", from: "6.0.0"),
  ],
  targets: [
    .target(
      name: "Core",
      dependencies: [
        "Yams"
      ]
    ),
    .executableTarget(
      name: "CLI",
      dependencies: [
        "Core",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: [
        "Core",
        "Yams",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
