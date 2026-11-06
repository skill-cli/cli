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
      revision: "994b82027d12edd3d7c63187a534150086993f7f"),
  ],
  targets: [
    .executableTarget(
      name: "CLI",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "AgentsCore", package: "core"),
        .product(name: "AgentsManifest", package: "core"),
        .product(name: "AgentsSkills", package: "core"),
      ]),
    .testTarget(
      name: "CLITests",
      dependencies: [
        "CLI",
        .product(name: "AgentsManifest", package: "core"),
        .product(name: "AgentsDescription", package: "core"),
      ]),
  ],
  swiftLanguageModes: [.v6]
)
