import Foundation
import Testing

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

struct SkillOutputExecutableTests {
  @Test(arguments: [
    ["update"], ["update", "--apply"],
    ["update", "pdf"], ["update", "pdf", "--apply"],
  ])
  func unchangedUpdatesReportNoSkillChanges(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf"])
    let output = try fixture.success(arguments).stdout
    #expect(output == "No skill changes.\n")
  }

  @Test(arguments: ["project", "user"], ["link", "copy"])
  func skillDiffsAppearOnce(scope: String, mode: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    let nested = fixture.source.appendingPathComponent(
      "skills/pdf/templates/skills/pdf/example.txt")
    try FileManager.default.createDirectory(
      at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("Before\n".utf8).write(to: nested)
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path, "pdf", "--scope", scope, "--mode", mode,
    ])
    try fixture.skill("pdf", body: "Updated content")
    try Data("After\n".utf8).write(to: nested)
    try fixture.commit()
    for arguments in [["update"], ["update", "--apply"]] {
      let output = try fixture.success(arguments + ["--scope", scope]).stdout
      #expect(output.components(separatedBy: "--- a/pdf/SKILL.md\n").count == 2)
      #expect(
        output.components(separatedBy: "--- a/pdf/templates/skills/pdf/example.txt\n").count == 2)
      #expect(output.components(separatedBy: "-Original content\n+Updated content\n").count == 2)
      #expect(!output.contains("link pdf:") && !output.contains("cache/"))
      if arguments.contains("--apply") {
        #expect(output.hasSuffix("Updated pdf for claude-code, codex.\n"))
      }
    }
  }

  @Test func installationModeChangesKeepLinks() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf"])
    for mode in ["copy", "edit", "link"] {
      try changeSelection(fixture) { $0["mode"] = mode }
      let output = try fixture.success(["update", "--apply"]).stdout
      let old = mode == "copy" ? "link" : mode == "edit" ? "copy" : "edit"
      #expect(output.contains("  ~ changed  codex (\(old) -> \(mode))  .agents/skills/pdf\n"))
      #expect(output.components(separatedBy: "link pdf:").count == 2)
      #expect(!output.contains("--- a/pdf/SKILL.md"))
      #expect(output.hasSuffix("Updated pdf for claude-code, codex.\n"))
      if mode != "copy" { #expect(output.contains(fixture.source.path + "/skills/pdf")) }
    }
  }

  @Test func divergentCopiesKeepTheirOwnDiffs() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf", "--mode", "copy"])
    try Data("Local Codex content\n".utf8).write(
      to: fixture.project.appendingPathComponent(".agents/skills/pdf/SKILL.md"))
    try fixture.skill("pdf", body: "Updated content")
    try fixture.commit()
    let output = try fixture.success(["update", "--apply"]).stdout
    #expect(output.contains("pdf/SKILL.md (claude-code)\n--- a/pdf/SKILL.md"))
    #expect(output.contains("pdf/SKILL.md (codex)\n--- a/pdf/SKILL.md"))
    #expect(output.contains("-Local Codex content\n"))
    #expect(output.contains("-Original content\n"))
    #expect(output.components(separatedBy: "+Updated content\n").count == 3)
    #expect(output.hasSuffix("Updated pdf for claude-code, codex.\n"))
  }

  @Test func updateRemovalsNameRecipients() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf"])
    try changeSelection(fixture) { $0["agents"] = ["codex"] }
    let partial = try fixture.success(["update", "--apply"]).stdout
    #expect(partial.contains("--- a/pdf/SKILL.md\n+++ /dev/null\n"))
    #expect(!partial.contains("link pdf:"))
    #expect(partial.hasSuffix("Removed pdf for claude-code.\nUpdated pdf for codex.\n"))
    var declaration = try fixture.declaration()
    declaration["skills"] = [String: Any]()
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
    let removed = try fixture.success(["update", "--apply"]).stdout
    #expect(removed.contains("--- a/pdf/SKILL.md\n+++ /dev/null\n"))
    #expect(removed.hasSuffix("Removed pdf for codex.\n"))
    #expect(!removed.contains("Updated pdf") && !removed.contains("link pdf:"))
  }

  @Test func explicitRemovalsNameOnlyRemovedRecipients() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf"])
    let absent = try fixture.success(["remove", "pdf", "--agent", "cursor"]).stdout
    #expect(absent.isEmpty)
    let partial = try fixture.success(["remove", "pdf", "--agent", "claude-code"]).stdout
    #expect(partial == "Removed pdf for claude-code.\n")
    let removed = try fixture.success(["remove", "pdf"]).stdout
    #expect(removed == "Removed pdf for codex.\n")
  }

  @Test func unrelatedUnreadableContentDoesNotLoseSkillOutput() throws {
    let fixture = try CLIFixture()
    try fixture.skill("healthy")
    try fixture.skill("broken")
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path, "healthy", "broken", "--mode", "copy",
    ])
    let fifo = fixture.project.appendingPathComponent(".agents/skills/broken/fifo")
    try #require(mkfifo(fifo.path, 0o600) == 0)
    let list = try fixture.run(["list"])
    #expect(list.status == 1)
    try fixture.skill("healthy", body: "Updated content")
    try fixture.commit()
    let updated = try fixture.success(["update", "healthy", "--apply"]).stdout
    #expect(updated.components(separatedBy: "--- a/healthy/SKILL.md\n").count == 2)
    #expect(updated.hasSuffix("Updated healthy for claude-code, codex.\n"))
    let removed = try fixture.success(["remove", "healthy"]).stdout
    #expect(removed == "Removed healthy for claude-code, codex.\n")
  }

  @Test(arguments: ["update", "remove"])
  func recoveryKeepsRecipientCompletions(_ command: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf"])
    if command == "update" {
      try fixture.skill("pdf", body: "Updated content")
      try fixture.commit()
    }
    let journal = fixture.state("transaction.new")
    try Data("partial journal".utf8).write(to: journal)
    let preview = try fixture.run(["update"])
    #expect(preview.status == 1 && preview.stdout.isEmpty)
    #expect(try Data(contentsOf: journal) == Data("partial journal".utf8))
    let arguments = command == "update" ? ["update", "--apply"] : ["remove", "pdf"]
    let applied = try fixture.run(arguments)
    #expect(applied.status == 0)
    #expect(applied.stderr == "Recovered interrupted transaction at .agent; retrying once.\n")
    let verb = command == "update" ? "Updated" : "Removed"
    #expect(applied.stdout.hasSuffix("\(verb) pdf for claude-code, codex.\n"))
    #expect(!FileManager.default.fileExists(atPath: journal.path))
  }

  private func changeSelection(_ fixture: CLIFixture, edit: (inout [String: Any]) -> Void) throws {
    var declaration = try fixture.declaration()
    var skills = try #require(declaration["skills"] as? [String: [String: Any]])
    let alias = try #require(skills.keys.first)
    var selection = try #require(skills[alias])
    edit(&selection)
    skills[alias] = selection
    declaration["skills"] = skills
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
  }
}
