// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "skill-cli",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "skill", targets: ["CLI"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    .package(
      url: "https://github.com/agents-tools/core.git",
      revision: "420ca0f91ba83b4ccfe3275f5a2711957ef6a5f1"),
  ],
  targets: [
    .executableTarget(
      name: "CLI",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "AgentsCore", package: "core"),
        .product(name: "AgentsSkills", package: "core"),
      ]),
    .testTarget(name: "CLITests", dependencies: ["CLI"]),
  ],
  swiftLanguageModes: [.v6]
)
