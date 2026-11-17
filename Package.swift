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
      revision: "7f5d71a8af0ec9861db4ae259f4b0c64d79e2985"),
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
