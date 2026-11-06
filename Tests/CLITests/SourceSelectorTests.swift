import AgentsCore
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
    #expect(
      declaration.sources == [
        "source": SourceDeclaration(
          kind: .local, location: fixture.source.path, requirement: .branch("main"), path: nil,
          environment: SourceEnvironment(
            projectDirectory: fixture.project, homeDirectory: fixture.home))
      ])
    #expect(try declaration.skills?["source"]?.select == .names(["demo"]))
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
    #expect(!FileManager.default.fileExists(atPath: fixture.state("Agents.swift").path))
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
    let watched = try fixture.declaration().sources
    #expect(Set(watched.keys) == ["source", "mirror-source"])
  }
}
