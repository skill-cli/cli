import Foundation
import Testing

@testable import CLI

struct WatchExecutableTests {
  @Test func declaredAliasTakesPrecedenceOverSourceIdentity() throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    let alias = "example.invalid/rules"
    try FileManager.default.createDirectory(
      at: fixture.state("agents.json").deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: [
      "sources": [
        alias: ["local": fixture.source.path],
        "remote": ["git": "https://example.invalid/rules.git"],
      ]
    ]).write(to: fixture.state("agents.json"))
    let added = try fixture.success(["watch", "add", alias])
    #expect(added.stdout.hasPrefix("Watching local:\(fixture.source.path) from "))
    #expect(try fixture.declaration()["watch"] as? [String] == [alias])
  }

  @Test(arguments: ["project", "user"])
  func subscriptionLifecycle(_ scope: String) throws {
    let fixture = try CLIFixture()
    let scopeOptions = ["--scope", scope]
    let sourceID = "local:" + fixture.source.path
    let fm = FileManager.default
    try fixture.skill("frontend-design", container: "collection/skills")
    try fixture.skill("legacy-docx", container: "collection/skills")
    try fixture.instruction("team-rules", container: "collection/instructions")
    try fixture.instruction("legacy-rules", container: "collection/instructions")
    try fixture.commit()
    let initial = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .newlines)
    #expect(try fixture.success(["watch"] + scopeOptions).stdout == "No watched sources.\n")
    let added = try fixture.success(
      [
        "watch", "add", fixture.source.path, "--path", "collection", "--branch", "main",
      ] + scopeOptions)
    #expect(added.stdout == "Watching \(sourceID) from \(initial.prefix(7)).\n")
    let installed = try fixture.success(["list", "--json"] + scopeOptions).json()
    #expect((installed["skills"] as? [Any])?.isEmpty == true)
    #expect(!fm.fileExists(atPath: fixture.project.appendingPathComponent("AGENTS.md").path))
    #expect(try fixture.success(["watch"] + scopeOptions).stdout == "\(sourceID)  up to date\n")
    let initialStatus = try fixture.success(["watch", "--json"] + scopeOptions).json()
    #expect(Set(initialStatus.keys) == ["schemaVersion", "scope", "sources"])
    #expect(initialStatus["schemaVersion"] as? Int == 1)
    #expect(initialStatus["scope"] as? String == scope)
    let initialSources = try #require(initialStatus["sources"] as? [[String: Any]])
    let alias = try #require(initialSources.first?["alias"] as? String)
    #expect((initialSources.first?["changes"] as? [Any])?.isEmpty == true)
    try fixture.success(["watch", "add", sourceID] + scopeOptions)
    try fixture.success(["watch", "add", alias] + scopeOptions)

    try fixture.success(
      [
        "add", alias, "frontend-design", "--mode", "copy", "--agent", "codex",
      ] + scopeOptions)
    let rows = try #require(
      try fixture.success(["list", "--json"] + scopeOptions).json()["skills"]
        as? [[String: Any]])
    let target = URL(fileURLWithPath: try #require(rows.first?["path"] as? String))
      .appendingPathComponent("SKILL.md")
    let installedBytes = try Data(contentsOf: target)
    let lock = try Data(contentsOf: fixture.state("agents.resolved", scope: scope))

    try fixture.skill("pdf-forms", container: "collection/skills")
    try fixture.instruction("new-rules", container: "collection/instructions")
    try fixture.commit()
    try fixture.skill("frontend-design", body: "Updated content", container: "collection/skills")
    try fixture.instruction(
      "team-rules", body: "Updated instructions", container: "collection/instructions")
    try Data("New reference\n".utf8).write(
      to: fixture.source.appendingPathComponent("collection/skills/frontend-design/reference.txt"))
    try fixture.commit()
    try fm.removeItem(at: fixture.source.appendingPathComponent("collection/skills/legacy-docx"))
    try fm.removeItem(
      at: fixture.source.appendingPathComponent("collection/instructions/legacy-rules.md"))
    try fixture.commit()
    let current = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .newlines)
    try fixture.skill("uncommitted", container: "collection/skills")
    let declaration = try Data(contentsOf: fixture.state("agents.json", scope: scope))
    let baseline = try Data(contentsOf: fixture.state("agents.watch", scope: scope))

    let expected = """
      \(sourceID)  3 commits since \(initial.prefix(7)) (now \(current.prefix(7)))
        + new      new-rules (instructions)
        + new      pdf-forms
        ~ changed  frontend-design   2 files
        ~ changed  team-rules (instructions)   1 file
        - removed  legacy-docx
        - removed  legacy-rules (instructions)

      """
    #expect(try fixture.success(["watch", "status"] + scopeOptions).stdout == expected)
    #expect(try fixture.success(["watch"] + scopeOptions).stdout == expected)
    let report = try fixture.success(["watch", "status", "--json"] + scopeOptions).json()
    let sources = try #require(report["sources"] as? [[String: Any]])
    let source = try #require(sources.first)
    #expect(Set(source.keys) == ["alias", "source", "seen", "current", "commitCount", "changes"])
    #expect(source["source"] as? String == sourceID && source["commitCount"] as? Int == 3)
    #expect((source["seen"] as? [String: String]) == ["revision": initial])
    #expect((source["current"] as? [String: String]) == ["revision": current])
    let changes = try #require(source["changes"] as? [[String: Any]])
    #expect(
      changes.compactMap { $0["name"] as? String } == [
        "legacy-rules", "new-rules", "team-rules", "frontend-design", "legacy-docx", "pdf-forms",
      ])
    let changed = try #require(changes.first { $0["name"] as? String == "frontend-design" })
    #expect(Set(changed.keys) == ["name", "kind", "change", "oldPath", "newPath", "fileCount"])
    #expect(changed["kind"] as? String == "skill" && changed["change"] as? String == "changed")
    #expect(changed["fileCount"] as? Int == 2)
    #expect(changed["oldPath"] as? String == "skills/frontend-design")

    let diff = try fixture.success(["watch", "diff", alias, "frontend-design"] + scopeOptions)
    #expect(diff.stdout.hasPrefix("~ changed  frontend-design  "))
    #expect(
      diff.stdout.contains("--- a/frontend-design/SKILL.md\n+++ b/frontend-design/SKILL.md\n"))
    #expect(diff.stdout.contains("-Original content") && diff.stdout.contains("+Updated content"))
    #expect(!diff.stdout.contains("team-rules"))
    let diffJSON = try fixture.success(
      [
        "watch", "diff", sourceID, "frontend-design", "--kind", "skill", "--json",
      ] + scopeOptions
    ).json()
    #expect(Set(diffJSON.keys) == ["schemaVersion", "scope", "source"])
    let diffSource = try #require(diffJSON["source"] as? [String: Any])
    let diffItems = try #require(diffSource["changes"] as? [[String: Any]])
    #expect(diffItems.count == 1)
    let files = try #require(diffItems.first?["files"] as? [[String: Any]])
    let skillFile = try #require(files.first { $0["path"] as? String == "SKILL.md" })
    let before = try #require(skillFile["before"] as? [String: Any])
    #expect(Set(before.keys) == ["kind", "base64", "executable"])
    #expect(before["kind"] as? String == "file" && before["executable"] as? Bool == false)
    #expect(Data(base64Encoded: try #require(before["base64"] as? String)) == installedBytes)
    let newFile = try #require(files.first { $0["path"] as? String == "reference.txt" })
    #expect(newFile["before"] == nil && newFile["after"] != nil)
    #expect(
      try fixture.success(
        [
          "watch", "diff", fixture.source.path, "frontend-design", "--kind", "instructions",
        ] + scopeOptions
      ).stdout == "up to date\n")
    #expect(try Data(contentsOf: fixture.state("agents.json", scope: scope)) == declaration)
    #expect(try Data(contentsOf: fixture.state("agents.watch", scope: scope)) == baseline)
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == lock)
    #expect(try Data(contentsOf: target) == installedBytes)

    let seen = try fixture.success(["watch", "seen", sourceID] + scopeOptions)
    #expect(seen.stdout == "Marked \(sourceID) seen at \(current.prefix(7)).\n")
    #expect(try fixture.success(["watch"] + scopeOptions).stdout == "\(sourceID)  up to date\n")
    #expect(try fixture.success(["watch", "diff", alias] + scopeOptions).stdout == "up to date\n")
    let older = try fixture.success(
      [
        "watch", "seen", alias, "--revision", String(initial.prefix(9)),
      ] + scopeOptions)
    #expect(older.stdout == "Marked \(sourceID) seen at \(initial.prefix(7)).\n")
    #expect(try fixture.success(["watch"] + scopeOptions).stdout == expected)
    let removed = try fixture.success(["watch", "remove", fixture.source.path] + scopeOptions)
    #expect(removed.stdout == "Stopped watching \(sourceID); installations are unchanged.\n")
    #expect(try fixture.success(["watch"] + scopeOptions).stdout == "No watched sources.\n")
    #expect(try Data(contentsOf: target) == installedBytes)
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == lock)
    #expect((try fixture.declaration(scope: scope)["sources"] as? [String: Any])?[alias] != nil)
  }

  @Test func modesLinksBinaryAndKindFiltering() throws {
    let fixture = try CLIFixture()
    try fixture.skill("shared")
    try fixture.instruction("shared")
    let script = fixture.source.appendingPathComponent("skills/shared/run.sh")
    let link = fixture.source.appendingPathComponent("skills/shared/link")
    try Data("echo hello\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script.path)
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "run.sh")
    try fixture.commit()
    try fixture.success(["watch", "add", fixture.source.path])
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "SKILL.md")
    try Data([0, 255]).write(to: fixture.source.appendingPathComponent("skills/shared/data.bin"))
    try fixture.instruction("shared", body: "Changed\u{1B}[31m instructions\t")
    try fixture.commit()
    let diff = try fixture.success(["watch", "diff", "source", "shared"]).stdout
    #expect(diff.contains("~ changed  shared (instructions)  "))
    #expect(diff.contains("~ changed  shared  "))
    #expect(diff.contains("mode shared/run.sh: 644 -> 755\n"))
    #expect(diff.contains("link shared/link: run.sh -> SKILL.md\n"))
    #expect(diff.contains("Binary file shared/data.bin differs\n"))
    #expect(!diff.contains("\u{1B}") && diff.contains("Changed\\x1b[31m instructions\t"))
    let json = try fixture.success([
      "watch", "diff", "source", "shared", "--kind", "skill", "--json",
    ]).json()
    let source = try #require(json["source"] as? [String: Any])
    let items = try #require(source["changes"] as? [[String: Any]])
    #expect(items.count == 1 && items.first?["fileCount"] as? Int == 3)
    let files = try #require(items.first?["files"] as? [[String: Any]])
    let mode = try #require(files.first { $0["path"] as? String == "run.sh" })
    #expect((mode["before"] as? [String: Any])?["executable"] as? Bool == false)
    #expect((mode["after"] as? [String: Any])?["executable"] as? Bool == true)
    let symlink = try #require(files.first { $0["path"] as? String == "link" })
    #expect(
      symlink["after"] as? [String: String] == ["kind": "symlink", "destination": "SKILL.md"])
  }

  @Test func operationErrorsHaveRemediesAndNoJSON() throws {
    let fixture = try CLIFixture()
    for arguments in [
      ["diff", fixture.source.path, "--json"], ["seen", "missing"],
      ["remove", fixture.source.path],
    ] {
      let result = try fixture.run(["watch"] + arguments)
      #expect(result.status == 1 && result.stdout.isEmpty)
      #expect(result.stderr.contains("Run 'skill watch' to list subscriptions"))
    }
    try fixture.skill()
    try fixture.commit()
    try fixture.success(["watch", "add", fixture.source.path])
    let baseline = try Data(contentsOf: fixture.state("agents.watch"))
    for revision in ["missing-revision", "--all"] {
      let result = try fixture.run(["watch", "seen", "source", "--revision=\(revision)"])
      #expect(result.status == 1 && result.stdout.isEmpty)
      #expect(result.stderr.split(separator: "\n").dropFirst().allSatisfy { $0.hasPrefix("  ") })
      #expect(
        result.stderr.hasSuffix(
          "\n  Provide a Git revision that resolves to a commit in the watched source.\n"))
      #expect(try Data(contentsOf: fixture.state("agents.watch")) == baseline)
    }
  }

  @Test(arguments: ["add", "seen", "remove"])
  func recoveryNoticesStayOnStderr(_ command: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    try fixture.success(["watch", "add", fixture.source.path])
    let staging = fixture.state("transaction.new")
    try Data("partial journal".utf8).write(to: staging)
    let result = try fixture.run(["watch", command, "source"])
    #expect(result.status == 0)
    #expect(
      result.stderr
        == "Recovered interrupted transaction at .agent; retrying once.\n"
    )
    #expect(!result.stdout.contains("Recovered"))
    #expect(!FileManager.default.fileExists(atPath: staging.path))
  }

  @Test(arguments: [
    ["watch", "unknown"], ["watch", "unknown", "--help"], ["watch", "--help", "unknown"],
    ["watch", "-h", "unknown"], ["help", "watch", "unknown"],
    ["watch", "--scope", "user", "unknown"], ["watch", "--scope=user", "--help", "unknown"],
    ["watch", "add"], ["watch", "diff"], ["watch", "seen"], ["watch", "remove"],
    ["watch", "diff", "source", "--kind", "invalid"], ["watch", "status", "--scope", "global"],
    ["watch", "add", "source", "--json"], ["watch", "seen", "source", "--json"],
    ["watch", "remove", "source", "--json"], ["watch", "add", "source", "--full-depth"],
    ["watch", "add", "source", "--branch", "main", "--exact", "1.2.3"],
    ["watch", "--version"],
    ["watch", "seen", "source", "--revision="],
  ])
  func usageErrors(_ arguments: [String]) throws {
    let result = try CLIFixture().run(arguments)
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.split(separator: "\n").dropFirst().allSatisfy { $0.hasPrefix("  ") })
    #expect(result.stderr.hasSuffix("\n  Run 'skill --help' for usage.\n"))
    if arguments.contains("unknown") {
      #expect(result.stderr.contains("Unknown command 'unknown'"))
    }
  }

  @Test(arguments: [
    ["watch", "--help", "--", "unknown"], ["watch", "-h", "--", "unknown"],
  ])
  func helpStopsCommandValidationAtTerminator(_ arguments: [String]) throws {
    #expect(try CLIFixture().success(arguments).stdout.contains("USAGE:"))
  }

  @Test func optionValueTerminatorUsesParserDiagnostic() throws {
    let result = try CLIFixture().run(["watch", "--scope", "--", "unknown", "--help"])
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.contains("Missing value for '--scope <scope>'"))
  }

  @Test func terminatedArgumentsAreNotCommands() throws {
    let result = try CLIFixture().run(["watch", "--", "unknown"])
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.contains("Unexpected argument 'unknown'"))
  }

  @Test(arguments: [[], ["add"], ["status"], ["diff"], ["seen"], ["remove"]])
  func help(_ command: [String]) throws {
    let fixture = try CLIFixture()
    let help = try fixture.success(["watch"] + command + ["--help"]).stdout
    #expect(help.contains("USAGE:") && !help.contains("--version"))
    if command == ["add"] {
      #expect(help.contains("without installing"))
      #expect(help.contains("Search this subdirectory of the source."))
      #expect(help.contains("--up-to-next-minor-from"))
    }
    if command == ["remove"] { #expect(help.contains("keep its installations")) }
  }
}
