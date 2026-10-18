import AgentsCore
import AgentsSkills
import Foundation
import Testing

@testable import CLI

struct WatchReportTests {
  @Test func confirmationUsesSubscribedAliasThenSubscribedIdentity() throws {
    let fixture = try CLIFixture()
    let environment = RuntimeEnvironment(
      projectDirectory: fixture.project, homeDirectory: fixture.home,
      environment: fixture.environment)
    let id = "example.invalid/rules"
    var declaration = Declaration(
      sources: [
        id: SourceDeclaration(kind: .local, location: fixture.source.path),
        "remote": SourceDeclaration(kind: .git, location: "https://example.invalid/rules.git"),
      ], watch: ["remote"])
    #expect(try watchedSourceID(id, declaration: declaration, environment: environment) == id)
    declaration.watch = [id, "remote"]
    #expect(
      try watchedSourceID(id, declaration: declaration, environment: environment) == "local:"
        + fixture.source.path)
  }

  @Test func wellKnownRenderingAndDigests() throws {
    let fixture = try CLIFixture()
    let environment = RuntimeEnvironment(
      projectDirectory: fixture.project, homeDirectory: fixture.home,
      environment: fixture.environment)
    let location = "https://watch.example.test"
    let original = SkillOperations.watchOperations(fetch: artifactFetch("Original"))
    try original.add(location, environment: environment)
    var output = ""
    Terminal.watchStatus(try original.status(environment: environment)) { output += $0 }
    #expect(output == "\(location)  up to date\n")

    let updated = SkillOperations.watchOperations(fetch: artifactFetch("Updated"))
    let statuses = try updated.status(environment: environment)
    output = ""
    Terminal.watchStatus(statuses) { output += $0 }
    #expect(output == "\(location)  1 artifact changed\n  ~ changed  demo (artifact)   1 file\n")
    let report = WatchStatusReport(scope: "project", statuses: statuses)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    let sources = try #require(json["sources"] as? [[String: Any]])
    let source = try #require(sources.first)
    #expect(source["commitCount"] == nil)
    let seen = try #require((source["seen"] as? [String: Any])?["artifacts"] as? [String: String])
    let current = try #require(
      (source["current"] as? [String: Any])?["artifacts"] as? [String: String])
    #expect(seen["demo"]?.hasPrefix("sha256:") == true && seen != current)
    let item = try #require((source["changes"] as? [[String: Any]])?.first)
    #expect(item["oldDigest"] as? String == seen["demo"])
    #expect(item["newDigest"] as? String == current["demo"])
    #expect(item["oldPath"] == nil && item["newPath"] == nil && item["files"] == nil)

    let expanded = SkillOperations.watchOperations(
      fetch: artifactFetch("Updated", names: ["demo", "new"]))
    output = ""
    Terminal.watchStatus(try expanded.status(environment: environment)) { output += $0 }
    #expect(output.hasPrefix("\(location)  2 artifacts changed\n"))
    #expect(
      output.hasSuffix("  + new      new (artifact)\n  ~ changed  demo (artifact)   1 file\n"))
  }

  @Test func watchJSONPreservesEntryKinds() throws {
    let entries: [WatchFileEntry] = [
      .file(Data([0, 255]), executable: true), .directory, .symbolicLink("../target\u{1B}"),
    ]
    let encoded = try JSONEncoder().encode(entries.map(FileEntry.init))
    let values = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
    #expect(values[0]["base64"] as? String == "AP8=")
    #expect(values[0]["executable"] as? Bool == true)
    #expect(values[1] as? [String: String] == ["kind": "directory"])
    #expect(values[2]["destination"] as? String == "../target\u{1B}")
  }
}

private func artifactFetch(_ body: String, names: [String] = ["demo"])
  -> @Sendable (URL) throws -> Data
{
  { url in
    if url.path.hasSuffix("index.json") {
      return try JSONSerialization.data(withJSONObject: [
        "skills": names.map { ["name": $0, "description": "Fixture", "files": ["SKILL.md"]] }
      ])
    }
    return Data("---\nname: demo\ndescription: Fixture\n---\n\(body)\n".utf8)
  }
}
