// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "skill-cli",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "skill", targets: ["CLI"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    .package(
      url: "https://github.com/agents-tools/core.git",
      revision: "c15076ca3a0b0db2ccffa2df10e342e03f1754c5"),
  ],
  targets: [
    .executableTarget(
      name: "CLI",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "AgentsCore", package: "core"),
        .product(name: "AgentsManifest", package: "core"),
        .product(name: "AgentsSkills", package: "core"),
        .product(name: "AgentsUpdates", package: "core"),
      ]),
    .testTarget(
      name: "CLITests",
      dependencies: [
        "CLI",
        .product(name: "AgentsCore", package: "core"),
        .product(name: "AgentsManifest", package: "core"),
        .product(name: "AgentsInstructions", package: "core"),
        .product(name: "AgentsUpdates", package: "core"),
      ]),
  ],
  swiftLanguageModes: [.v6]
)
