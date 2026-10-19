import Foundation
import Testing

struct SourceSelectorTests {
  @Test func addStoresSelectorsAsDeclarationFields() throws {
    let fixture = try CLIFixture()
    try fixture.skill("demo")
    try fixture.skill("other")
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path + "@branch:main@skill:demo", "--agent", "codex",
    ])
    let declaration = try fixture.declaration()
    let sources = try #require(declaration["sources"] as? [String: [String: String]])
    #expect(sources == ["source": ["local": fixture.source.path, "branch": "main"]])
    let skills = try #require(declaration["skills"] as? [String: [String: Any]])
    #expect(skills["source"]?["select"] as? [String] == ["demo"])
  }

  @Test func sourceListingFiltersToTheSelectedSkill() throws {
    let fixture = try CLIFixture()
    try fixture.skill("demo")
    try fixture.skill("other")
    try fixture.commit()
    let listing = try fixture.success(["list", fixture.source.path + "@skill:demo"]).stdout
    #expect(listing.contains("demo") && !listing.contains("other"))
  }

  @Test func conflictingSelectorAndOptionFailWithoutWriting() throws {
    let fixture = try CLIFixture()
    try fixture.skill("demo")
    try fixture.commit()
    let result = try fixture.run([
      "add", fixture.source.path + "@branch:main", "--branch", "other", "--agent", "codex",
    ])
    #expect(result.status == 1)
    #expect(result.stderr.contains("different requirements"))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.json").path))
  }

  @Test func sourcesSharingALastComponentGetDistinctAliases() throws {
    let fixture = try CLIFixture()
    try fixture.skill("demo")
    try fixture.commit()
    let mirror = fixture.root.appendingPathComponent("mirror/source")
    try FileManager.default.createDirectory(
      at: mirror.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fixture.git(["clone", "--quiet", fixture.source.path, mirror.path])
    try fixture.success(["add", fixture.source.path, "--agent", "codex"])
    try fixture.success(["watch", "add", mirror.path])
    let watched = try #require(try fixture.declaration()["sources"] as? [String: Any])
    #expect(Set(watched.keys) == ["source", "mirror-source"])
  }
}
