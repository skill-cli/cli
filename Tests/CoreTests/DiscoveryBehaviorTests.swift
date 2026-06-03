import Foundation
import Testing

@testable import Core

@Suite("Skill Discovery")
struct SkillDiscoveryTests {
  @Test func discoversNestedSkillsWhenFullDepthIsEnabled() throws {
    let root = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(root, name: "root-skill")
    try writeDiscoverySkill(
      root.appendingPathComponent("skills/nested-skill"), name: "nested-skill")

    #expect(try Discovery.discover(in: root).map(\.name) == ["root-skill"])
    #expect(
      try Discovery.discover(in: root, options: DiscoveryOptions(fullDepth: true)).map(\.name)
        .sorted() == ["nested-skill", "root-skill"])

    let noRoot = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(noRoot.appendingPathComponent("skills/skill-1"), name: "skill-1")
    try writeDiscoverySkill(noRoot.appendingPathComponent("skills/skill-2"), name: "skill-2")
    #expect(try Discovery.discover(in: noRoot).map(\.name).sorted() == ["skill-1", "skill-2"])
  }

  @Test func boundsNestedContainerDiscoveryDepth() throws {
    let root = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(
      root.appendingPathComponent("skills/product-a/skill-one"), name: "skill-one")
    try writeDiscoverySkill(
      root.appendingPathComponent("skills/product-a/skill-two"), name: "skill-two")
    try writeDiscoverySkill(
      root.appendingPathComponent("skills/product-b/skill-three"), name: "skill-three")
    try writeDiscoverySkill(
      root.appendingPathComponent("examples/category/example"), name: "example")

    #expect(
      try Discovery.discover(in: root).map(\.name).sorted()
        == ["skill-one", "skill-three", "skill-two"])

    let mixed = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(mixed.appendingPathComponent("skills/flat-skill"), name: "flat-skill")
    try writeDiscoverySkill(
      mixed.appendingPathComponent("skills/category/nested-skill"), name: "nested-skill")
    #expect(
      try Discovery.discover(in: mixed).map(\.name).sorted() == ["flat-skill", "nested-skill"])

    let shadowed = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(shadowed.appendingPathComponent("skills/foo"), name: "outer-skill")
    try writeDiscoverySkill(
      shadowed.appendingPathComponent("skills/foo/inner"), name: "inner-skill")
    #expect(try Discovery.discover(in: shadowed).map(\.name) == ["outer-skill"])

    let tooDeep = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(
      tooDeep.appendingPathComponent("skills/level-1/level-2/deep"), name: "deep")
    try writeDiscoverySkill(tooDeep.appendingPathComponent("skills/shallow"), name: "shallow")
    #expect(try Discovery.discover(in: tooDeep).map(\.name) == ["shallow"])
    #expect(
      try Discovery.discover(in: tooDeep, options: DiscoveryOptions(fullDepth: true)).map(\.name)
        .sorted() == ["deep", "shallow"])
  }

  @Test func suppressesLockedProjectAgentContainersDuringDiscovery() throws {
    let root = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(
      root.appendingPathComponent(".agents/skills/category/agent-skill"), name: "agent-skill")
    #expect(try Discovery.discover(in: root).map(\.name) == ["agent-skill"])

    let locked = try discoveryTemporaryDirectory()
    try writeDiscoverySkill(
      locked.appendingPathComponent(".agents/skills/installed-skill"), name: "installed-skill")
    try writeDiscoverySkill(
      locked.appendingPathComponent("skills/source-skill"), name: "source-skill")
    try """
    {
      "version": 1,
      "skills": {
        "installed-skill": {
          "source": "owner/repo",
          "sourceType": "github",
          "skillPath": "skills/installed-skill/SKILL.md",
          "computedHash": "hash"
        }
      }
    }
    """.write(
      to: locked.appendingPathComponent("skills-lock.json"), atomically: true, encoding: .utf8)

    #expect(try Discovery.discover(in: locked).map(\.name) == ["source-skill"])
  }

  @Test func discoversSkillsFromPluginManifests() throws {
    let root = try discoveryTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
    try """
    {
      "metadata": { "pluginRoot": "./plugins" },
      "plugins": [
        { "name": "my-plugin", "source": "my-plugin", "skills": ["./skills/my-skill"] },
        { "name": "other-plugin", "source": "./other-plugin" }
      ]
    }
    """.write(
      to: root.appendingPathComponent(".claude-plugin/marketplace.json"), atomically: true,
      encoding: .utf8)

    try writeDiscoverySkill(
      root.appendingPathComponent("plugins/my-plugin/skills/my-skill"), name: "pluginroot-skill")
    try writeDiscoverySkill(
      root.appendingPathComponent("plugins/other-plugin/skills/auto-discovered"),
      name: "auto-discovered")

    let skills = try Discovery.discover(in: root)
    #expect(skills.map(\.name).sorted() == ["auto-discovered", "pluginroot-skill"])
    #expect(skills.first { $0.name == "pluginroot-skill" }?.pluginName == "my-plugin")
  }

  @Test func rejectsUnsafePluginManifestPathsAndKeepsSafeConventions() throws {
    let root = try discoveryTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
    try """
    {
      "metadata": { "pluginRoot": "custom-plugins" },
      "plugins": [
        { "source": "./my-plugin", "skills": ["./custom-skills/my-skill"] }
      ]
    }
    """.write(
      to: root.appendingPathComponent(".claude-plugin/marketplace.json"), atomically: true,
      encoding: .utf8)

    try writeDiscoverySkill(
      root.appendingPathComponent("custom-plugins/my-plugin/custom-skills/my-skill"),
      name: "unreachable-skill")
    try writeDiscoverySkill(
      root.appendingPathComponent("skills/standard-skill"), name: "standard-skill")

    #expect(try Discovery.discover(in: root).map(\.name) == ["standard-skill"])

    try """
    { "skills": ["/etc/passwd", "invalid-loc/bare-skill", "./valid-loc/valid-skill"] }
    """.write(
      to: root.appendingPathComponent(".claude-plugin/plugin.json"), atomically: true,
      encoding: .utf8
    )
    try writeDiscoverySkill(
      root.appendingPathComponent("invalid-loc/bare-skill"), name: "bare-skill")
    try writeDiscoverySkill(
      root.appendingPathComponent("valid-loc/valid-skill"), name: "valid-skill")

    #expect(
      try Discovery.discover(in: root).map(\.name).sorted() == ["standard-skill", "valid-skill"])
  }

}

private func discoveryTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-discovery-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func writeDiscoverySkill(_ directory: URL, name: String) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try """
  ---
  name: \(name)
  description: \(name) description
  ---
  """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
}
