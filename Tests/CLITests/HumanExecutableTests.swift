import Foundation
import Testing

@testable import CLI

struct HumanExecutableTests {
  @Test func completionsAndRepinnedSkills() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.skill("unchanged")
    try fixture.commit()
    let added = try fixture.success(["add", fixture.source.path, "--all"]).stdout
    #expect(
      added
        == "Installed pdf for claude-code, codex (link).\nInstalled unchanged for claude-code, codex (link).\n"
    )
    let revision = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    try fixture.skill("pdf", body: "Updated content")
    try fixture.commit()
    let newRevision = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let preview = try fixture.success(["update"]).stdout
    let changed = try #require(preview.range(of: "~ changed  pdf")?.lowerBound)
    let repinned = try #require(preview.range(of: "= repinned  unchanged")?.lowerBound)
    #expect(changed < repinned)
    #expect(preview.contains("\(revision.prefix(7)) -> \(newRevision.prefix(7))"))
    #expect(!preview.contains("link pdf:") && !preview.contains("cache/"))
    #expect(!preview.contains("hash:") && !preview.contains("revision:"))
    #expect(!preview.contains("--- a/unchanged/"))
    let applied = try fixture.success(["update", "--apply"]).stdout
    let pins = "\(revision.prefix(7)) -> \(newRevision.prefix(7))"
    #expect(
      applied.hasSuffix(
        "Updated pdf for claude-code, codex: \(pins).\nUpdated unchanged for claude-code, codex: \(pins).\n"
      ))
    #expect(applied.components(separatedBy: "Updated pdf for claude-code, codex:").count == 2)
  }

  @Test func homeSourcesAndUsageRemedies() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    let source = fixture.home.appendingPathComponent("Developer/skills")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: fixture.source, to: source)
    try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: true)
    let watched = try fixture.success(["watch", "add", source.path]).stdout
    #expect(watched.hasPrefix("Watching local:~/Developer/skills from "))
    #expect(try fixture.success(["watch"]).stdout == "local:~/Developer/skills  up to date\n")
    let invalid = try fixture.run(["unknown"])
    #expect(invalid.status == 64 && invalid.stdout.isEmpty)
    #expect(
      invalid.stderr == "Error: Unknown command 'unknown'.\n  Run 'skill --help' for usage.\n")
  }

  @Test func missingGitSourceHasConciseFailureAndRemedy() throws {
    let fixture = try CLIFixture()
    let source = "file://localhost" + fixture.home.appendingPathComponent("missing.git").path
    try FileManager.default.createDirectory(
      at: fixture.state("agents.json").deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: [
      "sources": ["missing": ["git": source]]
    ]).write(to: fixture.state("agents.json"))
    let failure = try fixture.run(["add", "missing", "--all"])
    #expect(failure.status == 1 && failure.stdout.isEmpty)
    #expect(failure.stderr.hasPrefix("Error: Git could not clone \(source).\n"))
    #expect(!failure.stderr.contains("cache/") && !failure.stderr.contains(".staging-"))
    #expect(failure.stderr.hasSuffix("\n  Check Git access and the source location.\n"))
  }

  @Test func multilineGitFailureKeepsDiagnosticStructure() throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "demo"])
    try FileManager.default.removeItem(at: fixture.source.appendingPathComponent(".git"))
    let failure = try fixture.run(["update"])
    #expect(failure.status == 1 && failure.stdout.isEmpty)
    #expect(failure.stderr.hasPrefix("Error: Git could not fetch \(fixture.source.path).\n"))
    #expect(failure.stderr.contains("\n  fatal: Could not read from remote repository.\n"))
    #expect(
      failure.stderr.hasSuffix(
        "  and the repository exists.\n  Check Git access and the source location.\n"))
    let lines = failure.stderr.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.dropFirst().dropLast().allSatisfy { $0.hasPrefix("  ") })
    #expect(!failure.stderr.contains("cache/") && !failure.stderr.contains("\n  \n"))
    #expect(!failure.stderr.contains("\\n") && !failure.stderr.contains("\n  ."))
  }

  @Test func upstreamControlsAndEmptyFiles() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf", body: "a\tb\r\nControl: \u{1b}[31m\0")
    let removed = fixture.source.appendingPathComponent("skills/pdf/old-empty")
    let added = fixture.source.appendingPathComponent("skills/pdf/new-empty")
    try Data().write(to: removed)
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf"])
    try fixture.success(["watch", "add", fixture.source.path])
    try fixture.skill("pdf", body: "a\tc\nControl: \u{1b}[32m\0")
    try FileManager.default.removeItem(at: removed)
    try Data().write(to: added)
    try fixture.commit()
    for arguments in [["update"], ["watch", "diff", fixture.source.path, "pdf"]] {
      let output = try fixture.success(arguments).stdout
      #expect(output.contains("-a\tb\\r\n"))
      #expect(output.contains("+a\tc\n"))
      #expect(output.contains("-Control: \\x1b[31m\\x00\n"))
      #expect(output.contains("+Control: \\x1b[32m\\x00\n"))
      #expect(output.contains("empty file pdf/new-empty added\n"))
      #expect(output.contains("empty file pdf/old-empty removed\n"))
      #expect(!output.contains("+++ b/pdf/new-empty") && !output.contains("--- a/pdf/old-empty"))
      #expect(!output.contains("\u{1b}") && !output.contains("\r") && !output.contains("\0"))
    }
    let error = try fixture.run(["--unknown\u{1b}[31m"])
    #expect(error.stderr.contains("\\x1b[31m") && !error.stderr.contains("\u{1b}"))
  }

  @Test func editRecipientChange() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path, "pdf", "--mode", "edit", "--agent", "codex",
    ])
    var declaration = try fixture.declaration()
    var skills = try #require(declaration["skills"] as? [String: [String: Any]])
    let alias = try #require(skills.keys.first)
    skills[alias]?["agents"] = ["cursor"]
    declaration["skills"] = skills
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
    let preview = try fixture.success(["update"]).stdout
    #expect(preview.hasPrefix("~ changed  pdf  "))
  }
}
