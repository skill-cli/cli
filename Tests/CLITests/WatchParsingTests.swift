import AgentsCore
import ArgumentParser
import Testing

@testable import CLI

struct WatchParsingTests {
  @Test(arguments: [
    (["--branch", "main"], SourceRequirement.branch("main")),
    (["--revision", "abc123"], .revision("abc123")),
    (["--exact", "1.2.3"], .exact("1.2.3")),
    (["--from", "1.2.3"], .upToNextMajor(from: "1.2.3")),
    (["--up-to-next-minor-from", "1.2.3"], .upToNextMinor(from: "1.2.3")),
    (["--from", "1.2.3", "--to", "2.0.0"], .range(from: "1.2.3", to: "2.0.0")),
  ])
  func addRequirements(arguments: [String], expected: SourceRequirement) throws {
    let command = try #require(
      try SkillCLI.parseAsRoot(
        [
          "watch", "add", "team", "--path", "collection", "--scope", "user",
        ] + arguments) as? AddWatch)
    #expect(command.requirements.requirement == expected && command.source == "team")
    #expect(command.discovery.path == "collection" && command.location.scope == .user)
  }

  @Test(arguments: [[], ["status"]])
  func defaultStatus(_ command: [String]) throws {
    let status = try #require(
      try SkillCLI.parseAsRoot(["watch"] + command + ["--json", "--scope", "user"])
        as? WatchStatusCommand)
    #expect(status.json && status.location.scope == .user)
  }

  @Test(arguments: ["skill", "instructions", "artifact"])
  func diffKinds(_ kind: String) throws {
    let command = try #require(
      try SkillCLI.parseAsRoot([
        "watch", "diff", "team", "shared", "--kind", kind, "--json", "--scope", "user",
      ]) as? DiffWatch)
    #expect(command.source == "team" && command.name == "shared" && command.kind?.rawValue == kind)
    #expect(command.json && command.location.scope == .user)
  }
}
