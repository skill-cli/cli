import AgentsCore
import Foundation
import Testing

struct ManifestBoundaryTests {
  @Test(arguments: ["project", "user"])
  func noOpCommandsPreserveDeclarationCommentsAndWatch(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    let options = ["--scope", scope]
    try fixture.success(["add", fixture.source.path, "demo", "--agent", "codex"] + options)
    try fixture.success(["add", fixture.source.path, "demo", "--agent", "codex"] + options)
    try fixture.success(["watch", "add", fixture.source.path] + options)
    let url = fixture.state("Agents.swift", scope: scope)
    let text = try String(contentsOf: url, encoding: .utf8)
    try fixture.writeManifest(
      text.replacingOccurrences(of: "let agents =", with: "// Project choices\nlet agents =")
        .replacingOccurrences(of: ".skills(", with: "/* Skill ownership */ .skills("), scope: scope)
    let declaration = try Data(contentsOf: url)
    let watch = try Data(contentsOf: fixture.state("agents.watch", scope: scope))
    for command in [
      ["add", fixture.source.path, "demo", "--agent", "codex"],
      ["install"], ["update", "--apply"], ["remove", "demo", "--agent", "cursor"],
      ["list", "--json"], ["watch", "--json"],
    ] {
      try fixture.success(command + options)
      #expect(try Data(contentsOf: url) == declaration)
      #expect(try Data(contentsOf: fixture.state("agents.watch", scope: scope)) == watch)
    }
  }

  @Test(arguments: ["project", "user"], ["agents.resolved", "agents.watch"])
  func missingDeclarationExplainsFailureWithoutWriting(scope: String, orphan: String) throws {
    let fixture = try CLIFixture()
    let directory = fixture.state("", scope: scope)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bytes =
      try orphan == "agents.resolved"
      ? JSONEncoder().encode(ResolvedState()) : JSONEncoder().encode(WatchState())
    try bytes.write(to: fixture.state(orphan, scope: scope))
    for command in [
      ["list", "--json"], ["update", "--json"], ["install"],
      ["watch", "--json"], ["watch", "add", fixture.source.path],
    ] {
      let result = try fixture.run(command + ["--scope", scope])
      #expect(result.status == 1 && result.stdout.isEmpty)
      #expect(result.stderr.contains("Missing declaration at"))
      #expect(result.stderr.contains("Agents.swift"))
      #expect(result.stderr.contains("Restore Agents.swift from version control"))
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [orphan])
      #expect(try Data(contentsOf: fixture.state(orphan, scope: scope)) == bytes)
    }
  }

  @Test(arguments: ["project", "user"], ["transaction.new", "transaction.json"])
  func inspectionsLeavePendingRecoveryUnchanged(scope: String, journal: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    let options = ["--scope", scope]
    try fixture.success(["add", fixture.source.path, "demo", "--agent", "codex"] + options)
    try fixture.success(["watch", "add", fixture.source.path] + options)
    let files = ["Agents.swift", "agents.resolved", "agents.watch", journal]
    try Data("unfinished journal".utf8).write(to: fixture.state(journal, scope: scope))
    let before = try files.map { try Data(contentsOf: fixture.state($0, scope: scope)) }
    let directory = fixture.state("", scope: scope)
    let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()
    for command in [
      ["list", "--json"], ["list", fixture.source.path, "--json"], ["update", "--json"],
      ["watch", "--json"], ["watch", "diff", "source", "--json"],
    ] {
      let result = try fixture.run(command + options)
      #expect(result.status == 1 && result.stdout.isEmpty)
      if journal == "transaction.new" {
        #expect(result.stderr.contains("recovery is pending"))
        #expect(result.stderr.contains("skill install"))
      } else {
        #expect(result.stderr.contains("Unresolved transaction conflict"))
        #expect(result.stderr.contains("Retained locations:"))
        #expect(result.stderr.contains("resolve the transaction conflict before retrying"))
      }
      #expect(try files.map { try Data(contentsOf: fixture.state($0, scope: scope)) } == before)
      #expect(try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted() == paths)
    }
  }
}
