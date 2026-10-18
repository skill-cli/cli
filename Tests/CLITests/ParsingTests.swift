import AgentsCore
import ArgumentParser
import Testing

@testable import CLI

struct ParsingTests {
  @Test func addOptions() throws {
    let command = try #require(
      try SkillCLI.parseAsRoot([
        "add", "owner/repo", "one", "two", "--agent", "codex", "--agent", "claude",
        "--scope", "user", "--path", "collection", "--full-depth", "--mode", "copy", "--branch",
        "main",
      ]) as? Add)
    #expect(command.source == "owner/repo")
    #expect(command.names == ["one", "two"])
    #expect(command.agents.recipients == [.claudeCode, .codex])
    #expect(command.location.scope == .user)
    #expect(command.discovery.path == "collection" && command.discovery.fullDepth)
    #expect(command.mode == .copy && !command.all)
    #expect(command.requirements.requirement == .branch("main"))
    let all = try #require(try SkillCLI.parseAsRoot(["add", ".", "--all"]) as? Add)
    #expect(all.all && all.names.isEmpty)
    #expect(all.location.scope == .project && all.mode == .link)
    #expect(all.agents.recipients == nil && all.requirements.requirement == nil)
  }

  @Test(arguments: [
    (["--branch", "main"], SourceRequirement.branch("main")),
    (["--revision", "abc123"], .revision("abc123")),
    (["--exact", "1.2.3"], .exact("1.2.3")),
    (["--from", "1.2.3"], .upToNextMajor(from: "1.2.3")),
    (["--up-to-next-minor-from", "1.2.3"], .upToNextMinor(from: "1.2.3")),
    (["--from", "1.2.3", "--to", "2.0.0"], .range(from: "1.2.3", to: "2.0.0")),
  ])
  func requirements(arguments: [String], expected: SourceRequirement) throws {
    let command = try #require(
      try SkillCLI.parseAsRoot(["add", "owner/repo"] + arguments) as? Add)
    #expect(command.requirements.requirement == expected)
  }

  @Test(arguments: ["link", "copy", "edit"])
  func modes(_ mode: String) throws {
    let command = try #require(
      try SkillCLI.parseAsRoot(["add", ".", "--mode", mode]) as? Add)
    #expect(command.mode.rawValue == mode)
  }

  @Test func listOptions() throws {
    let source = try #require(
      try SkillCLI.parseAsRoot([
        "list", "team", "--path", "skills", "--full-depth", "--json", "--scope", "user",
        "--agent", "gemini",
      ]) as? ListSkills)
    #expect(source.source == "team" && source.discovery.path == "skills")
    #expect(source.discovery.fullDepth && source.json && source.location.scope == .user)
    #expect(source.agents.recipients == [.geminiCLI])
    let installed = try #require(try SkillCLI.parseAsRoot(["list"]) as? ListSkills)
    #expect(installed.source == nil && installed.agents.recipients == nil)
  }

  @Test func removeOptions() throws {
    let command = try #require(
      try SkillCLI.parseAsRoot([
        "remove", "one", "two", "--scope", "user", "--agent", "cursor", "--agent",
        "opencode",
      ]) as? Remove)
    #expect(command.names == ["one", "two"] && command.location.scope == .user)
    #expect(command.agents.recipients == [.cursor, .opencode])
    let all = try #require(try SkillCLI.parseAsRoot(["remove", "one"]) as? Remove)
    #expect(all.agents.recipients == nil)
  }

  @Test func lifecycleOptions() throws {
    let install = try #require(
      try SkillCLI.parseAsRoot(["install", "--scope", "user"]) as? Install)
    #expect(install.location.scope == .user)
    let update = try #require(
      try SkillCLI.parseAsRoot(["update", "--scope", "user", "--apply"]) as? UpdateSkills)
    #expect(update.options.apply && !update.options.json && update.options.location.scope == .user)
    let preview = try #require(try SkillCLI.parseAsRoot(["update", "--json"]) as? UpdateSkills)
    #expect(preview.options.json && !preview.options.apply)
    let named = try #require(
      try SkillCLI.parseAsRoot(["update", "one", "two", "--json", "--scope", "user"])
        as? UpdateSkills)
    #expect(named.names == ["one", "two"] && named.options.json)
    #expect(named.options.location.scope == .user)
    let apply = try #require(
      try SkillCLI.parseAsRoot(["update", "--apply"]) as? UpdateSkills)
    #expect(apply.options.apply && apply.names.isEmpty)
  }

  @Test func doctorOptions() throws {
    let doctor = try #require(
      try SkillCLI.parseAsRoot([
        "doctor", "--root", "first", "second", "--root", "third", "--agent", "codex", "--json",
      ]) as? Doctor)
    #expect(doctor.root == ["first", "second", "third"])
    #expect(doctor.json && doctor.agents.recipients == [.codex])
    let user = try #require(try SkillCLI.parseAsRoot(["doctor", "--scope", "user"]) as? Doctor)
    #expect(user.root.isEmpty && user.location.scope == .user)
  }

  @Test func initializeArguments() throws {
    let current = try #require(try SkillCLI.parseAsRoot(["init"]) as? Initialize)
    #expect(current.name == nil)
    let named = try #require(try SkillCLI.parseAsRoot(["init", "demo"]) as? Initialize)
    #expect(named.name == "demo")
  }

  @Test(arguments: [
    ["unknown"], ["add"], ["remove"],
    ["add", ".", "name", "--all"], ["add", ".", "--mode", "unknown"],
    ["add", ".", "--branch", "main", "--revision", "123"],
    ["add", ".", "--exact", "1.0.0", "--from", "1.0.0"],
    ["add", ".", "--to", "2.0.0"], ["add", ".", "--exact", "invalid"],
    ["add", ".", "--from", "2.0.0", "--to", "1.0.0"],
    ["add", ".", "--mode", "edit", "--branch", "main"],
    ["list", "--scope", "global"], ["list", "--agent", "unknown"],
    ["list", "--path", "skills"], ["list", "--full-depth"],
    ["install", "--agent", "codex"], ["install", "--mode", "copy"], ["install", "source"],
    ["update", "--apply", "--json"], ["doctor", "--scope", "user", "--root", "."],
    ["add", ".", "--json"], ["init", "one", "two"],
  ])
  func invalidArguments(_ arguments: [String]) {
    #expect(throws: (any Error).self) { try SkillCLI.parseAsRoot(arguments) }
  }
}
