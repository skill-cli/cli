import Foundation
import Testing

@testable import CLI

struct ExecutableTests {
  @Test(arguments: ["project", "user"], ["link", "copy"])
  func lifecycle(scope: String, mode: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    let scopeArguments = ["--scope", scope]
    try fixture.success(
      [
        "add", fixture.source.path, "demo", "--agent", "codex", "--mode", mode,
        "--branch", "main", "--path", "skills",
      ] + scopeArguments)
    let list = try fixture.success(["list", "--json"] + scopeArguments).json()
    #expect(Set(list.keys) == ["schemaVersion", "kind", "scope", "skills"])
    #expect(list["schemaVersion"] as? Int == 1 && list["kind"] as? String == "installed")
    #expect(list["scope"] as? String == scope)
    let rows = try #require(list["skills"] as? [[String: Any]])
    let item = try #require(rows.first)
    #expect(rows.count == 1)
    #expect(Set(item.keys) == ["name", "agent", "path", "source", "installed", "status", "mode"])
    #expect(item["name"] as? String == "demo" && item["agent"] as? String == "codex")
    #expect(item["mode"] as? String == mode && item["installed"] as? Bool == true)
    let installed = URL(fileURLWithPath: try #require(item["path"] as? String))
    #expect(installed.path.hasPrefix(fixture.root.path))
    let humanList = try fixture.success(["list"] + scopeArguments).stdout
    let displayPath = scope == "user" ? "~/.agents/skills/demo" : ".agents/skills/demo"
    #expect(humanList.contains(displayPath))
    #expect(!humanList.contains(installed.path))
    let lock = try Data(contentsOf: fixture.state("agents.resolved", scope: scope))
    let declaration = try Data(contentsOf: fixture.state("agents.json", scope: scope))
    try FileManager.default.removeItem(at: installed)
    let missing = try fixture.success(["doctor", "--json"] + scopeArguments).json()
    let roots = try #require(missing["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    #expect(checks.contains { $0["id"] as? String == "missing" })
    let restored = try fixture.success(["install", "--json"] + scopeArguments).json()
    #expect(Set(restored.keys) == ["schemaVersion", "scope", "skills"])
    #expect(restored["schemaVersion"] as? Int == 1 && restored["scope"] as? String == scope)
    let restoredSkills = try #require(restored["skills"] as? [[String: String]])
    #expect(
      restoredSkills == [["name": "demo", "agent": "codex", "mode": mode, "path": installed.path]])
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == lock)
    let file = installed.appendingPathComponent("SKILL.md")
    let original = try Data(contentsOf: file)
    try fixture.skill(body: "Updated upstream content")
    try fixture.commit()
    let human = try fixture.success(["update"] + scopeArguments)
    #expect(human.stdout.contains("-Original content"))
    #expect(human.stdout.contains("+Updated upstream content"))
    let preview = try fixture.success(["update", "--json"] + scopeArguments).json()
    #expect(Set(preview.keys) == ["schemaVersion", "scope", "changed", "skills"])
    #expect(preview["schemaVersion"] as? Int == 1 && preview["changed"] as? Bool == true)
    let updates = try #require(preview["skills"] as? [[String: Any]])
    let update = try #require(updates.first)
    #expect(
      Set(update.keys) == [
        "name", "source", "changed", "oldRevision", "newRevision", "oldHash", "newHash", "files",
      ])
    #expect(update["oldRevision"] as? String != update["newRevision"] as? String)
    let files = try #require(update["files"] as? [[String: Any]])
    let change = try #require(
      files.first { ($0["path"] as? String)?.hasSuffix("SKILL.md") == true })
    #expect(Set(change.keys) == ["path", "before", "after"])
    let before = try #require(change["before"] as? [String: String])
    let after = try #require(change["after"] as? [String: String])
    #expect(Set(before.keys) == ["kind", "base64"] && before["kind"] == "file")
    #expect(Data(base64Encoded: try #require(before["base64"])) == original)
    #expect(try Data(contentsOf: file) == original)
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == lock)
    #expect(try Data(contentsOf: fixture.state("agents.json", scope: scope)) == declaration)
    let applied = try fixture.success(["update", "--apply"] + scopeArguments)
    let diffIndex = try #require(applied.stdout.range(of: "+Updated upstream content")?.lowerBound)
    let appliedIndex = try #require(
      applied.stdout.range(of: "Updated demo for codex.\n")?.lowerBound)
    #expect(diffIndex < appliedIndex)
    #expect(try Data(contentsOf: file) == Data(base64Encoded: try #require(after["base64"])))
    let clean = try fixture.success(["update", "--json"] + scopeArguments).json()
    #expect(clean["changed"] as? Bool == false)
    try fixture.success(["remove", "demo"] + scopeArguments)
    #expect(!FileManager.default.fileExists(atPath: installed.path))
    let empty = try fixture.success(["list", "--json"] + scopeArguments).json()
    #expect((empty["skills"] as? [Any])?.isEmpty == true)
  }

  @Test func sourceDiscoveryAndAllMembership() throws {
    let fixture = try CLIFixture()
    try fixture.skill("one")
    try fixture.skill("two")
    try fixture.commit()
    let available = try fixture.success(["add", fixture.source.path])
    #expect(available.stdout.contains("one") && available.stdout.contains("two"))
    #expect(available.stdout.contains("--all"))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.json").path))
    let list = try fixture.success([
      "list", fixture.source.path, "--full-depth", "--path", "skills", "--json",
    ]).json()
    #expect(Set(list.keys) == ["schemaVersion", "kind", "scope", "source", "skills"])
    #expect(list["kind"] as? String == "source")
    let skills = try #require(list["skills"] as? [[String: Any]])
    #expect(skills.compactMap { $0["name"] as? String } == ["one", "two"])
    #expect(Set(try #require(skills.first).keys) == ["name", "description", "path", "skillFile"])
    try fixture.success(["add", fixture.source.path, "--all", "--mode", "copy"])
    try fixture.skill("three")
    try fixture.commit()
    try fixture.success(["update", "--apply"])
    let expanded = try fixture.success(["list", "--json"]).json()
    #expect((expanded["skills"] as? [[String: Any]])?.count == 6)
    try fixture.success(["remove", "one", "--agent", "codex"])
    let filtered = try fixture.success(["list", "--agent", "codex", "--json"]).json()
    #expect((filtered["skills"] as? [[String: Any]])?.count == 2)
    try fixture.success(["remove", "one"])
    try fixture.success(["update", "--apply"])
    let remaining = try fixture.success(["list", "--json"]).json()
    #expect((remaining["skills"] as? [[String: Any]])?.count == 4)
  }

  @Test func namedUpdateAndDrift() throws {
    let fixture = try CLIFixture()
    try fixture.skill("one")
    try fixture.skill("two")
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path, "--all", "--mode", "copy", "--agent", "codex",
    ])
    let one = fixture.project.appendingPathComponent(".agents/skills/one/SKILL.md")
    let two = fixture.project.appendingPathComponent(".agents/skills/two/SKILL.md")
    let oldTwo = try Data(contentsOf: two)
    try Data("Local drift\n".utf8).write(to: one)
    try fixture.skill("one", body: "New one")
    try fixture.skill("two", body: "New two")
    try fixture.commit()
    let preview = try fixture.success(["update", "one"])
    #expect(preview.stdout.contains("-Local drift"))
    #expect(preview.stdout.contains("+New one"))
    #expect(!preview.stdout.contains("+New two"))
    try fixture.success(["update", "one", "--apply"])
    #expect(try Data(contentsOf: two) == oldTwo)
    #expect(try String(contentsOf: one, encoding: .utf8).contains("New one"))
  }

  @Test func doctorRootsAndReadOnlySchema() throws {
    let fixture = try CLIFixture()
    let report = try fixture.success([
      "doctor", "--root", fixture.project.path, fixture.source.path, "--json",
    ]).json()
    #expect(Set(report.keys) == ["schemaVersion", "ok", "roots"])
    #expect(report["schemaVersion"] as? Int == 1 && report["ok"] as? Bool == true)
    let roots = try #require(report["roots"] as? [[String: Any]])
    #expect(roots.count == 2)
    for root in roots {
      #expect(Set(root.keys) == ["root", "scope", "ok", "checks"])
      #expect(root["scope"] as? String == "project")
      #expect((root["checks"] as? [Any])?.isEmpty == true)
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.json").path))
    #expect(
      !FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agent").path)
    )
    try fixture.skill()
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path, "--mode", "copy", "--agent", "codex",
    ])
    try fixture.skill(body: "Dirty working tree")
    let dirty = try fixture.success(["doctor", "--json"]).json()
    let dirtyRoots = try #require(dirty["roots"] as? [[String: Any]])
    let checks = try #require(dirtyRoots.first?["checks"] as? [[String: Any]])
    let check = try #require(checks.first)
    #expect(Set(check.keys) == ["kind", "id", "status", "message", "path"])
    #expect(check["id"] as? String == "uncommitted-source")
    #expect(check["status"] as? String == "warning" && dirty["ok"] as? Bool == true)
  }

  @Test func initializationAndEditableSource() throws {
    let fixture = try CLIFixture()
    try fixture.success(["init", "demo"], directory: fixture.source)
    try fixture.success([
      "add", fixture.source.path, "--mode", "edit", "--agent", "codex",
    ])
    let target = fixture.project.appendingPathComponent(".agents/skills/demo")
    #expect(try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    try fixture.success(["init"], directory: fixture.home)
    #expect(
      FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("SKILL.md").path))
    let existing = try fixture.run(["init"], directory: fixture.home)
    #expect(existing.status == 1 && existing.stderr.contains("already exists"))
  }

  @Test(arguments: ["project", "user"], ["transaction.json", "transaction.new"])
  func doctorLeavesPendingRecoveryUnchanged(scope: String, journal: String) throws {
    let fixture = try CLIFixture()
    let state = fixture.state("", scope: scope)
    let cache = fixture.state("cache/content", scope: scope)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let files = [
      fixture.state(journal, scope: scope), fixture.state("agents.json", scope: scope),
      fixture.state("agents.resolved", scope: scope), cache.appendingPathComponent("snapshot"),
    ]
    for (file, content) in zip(
      files,
      [
        Data("{}".utf8), Data("incomplete declaration".utf8), Data("incomplete lock".utf8),
        Data([0, 255]),
      ])
    {
      try content.write(to: file)
    }
    let paths = try FileManager.default.subpathsOfDirectory(atPath: state.path).sorted()
    let before = try files.map { try Data(contentsOf: $0) }
    let remedy =
      scope == "user"
      ? "run 'skill install --scope user' to finish recovery"
      : "run 'skill install' in '\(fixture.project.path)' to finish recovery"
    for json in [false, true] {
      let result = try fixture.run(["doctor", "--scope", scope] + (json ? ["--json"] : []))
      #expect(result.status == 1 && result.stderr.isEmpty)
      if json {
        let report = try result.json()
        #expect(Set(report.keys) == ["schemaVersion", "ok", "roots"])
        #expect(report["ok"] as? Bool == false)
        let roots = try #require(report["roots"] as? [[String: Any]])
        #expect(roots.count == 1 && roots.first?["ok"] as? Bool == false)
        let checks = try #require(roots.first?["checks"] as? [[String: Any]])
        #expect(checks.count == 1)
        #expect(checks.compactMap { $0["kind"] as? String } == ["skills"])
        #expect(
          checks.compactMap { $0["id"] as? String } == ["pending-recovery"])
        for check in checks {
          #expect(Set(check.keys) == ["kind", "id", "status", "message", "path"])
          #expect(check["status"] as? String == "error")
          #expect((check["message"] as? String)?.contains(remedy) == true)
          #expect(check["path"] as? String == state.path)
        }
      } else {
        #expect(result.stdout.contains("skills error: Transaction recovery is pending"))
        #expect(result.stdout.contains(remedy))
        #expect(result.stdout.contains(scope == "user" ? "(~/.agents)" : "(.agent)"))
      }
      #expect(try FileManager.default.subpathsOfDirectory(atPath: state.path).sorted() == paths)
      #expect(try files.map { try Data(contentsOf: $0) } == before)
    }
  }

  @Test func previewDescribesEntryTypesAndDeletions() throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    let source = fixture.source.appendingPathComponent("skills/demo")
    try Data([0, 255]).write(to: source.appendingPathComponent("binary"))
    try FileManager.default.createSymbolicLink(
      atPath: source.appendingPathComponent("link").path, withDestinationPath: "SKILL.md")
    try Data("remove me".utf8).write(to: source.appendingPathComponent("obsolete"))
    try fixture.commit()
    try fixture.success([
      "add", fixture.source.path, "--mode", "copy", "--agent", "codex",
    ])
    let target = fixture.project.appendingPathComponent(".agents/skills/demo")
    try FileManager.default.createDirectory(
      at: target.appendingPathComponent("empty"), withIntermediateDirectories: true)
    try Data([0, 254]).write(to: source.appendingPathComponent("binary"))
    try FileManager.default.removeItem(at: source.appendingPathComponent("link"))
    try FileManager.default.createSymbolicLink(
      atPath: source.appendingPathComponent("link").path, withDestinationPath: "binary")
    try FileManager.default.removeItem(at: source.appendingPathComponent("obsolete"))
    try fixture.commit()
    let preview = try fixture.success(["update", "demo", "--json"]).json()
    let updates = try #require(preview["skills"] as? [[String: Any]])
    let files = try #require(updates.first?["files"] as? [[String: Any]])
    let byName = Dictionary(
      uniqueKeysWithValues: try files.map { file in
        let path = try #require(file["path"] as? String)
        return (URL(fileURLWithPath: path).lastPathComponent, file)
      })
    #expect(
      (byName["binary"]?["before"] as? [String: String]) == ["kind": "file", "base64": "AP8="])
    #expect(
      (byName["binary"]?["after"] as? [String: String]) == ["kind": "file", "base64": "AP4="])
    #expect(
      (byName["link"]?["after"] as? [String: String]) == [
        "kind": "symlink", "destination": "binary",
      ])
    #expect((byName["empty"]?["before"] as? [String: String]) == ["kind": "directory"])
    #expect(byName["empty"]?["after"] == nil && byName["obsolete"]?["after"] == nil)
    let apply = try fixture.success(["update", "demo", "--apply"])
    #expect(apply.stdout.contains("Binary file demo/binary differs"))
    #expect(
      apply.stdout.contains("link demo/link: SKILL.md -> binary")
        && apply.stdout.contains("directory demo/empty removed"))
    #expect(apply.stdout.contains("+++ /dev/null"))
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("obsolete").path))
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("empty").path))
  }

  @Test(arguments: [
    ["--help"], ["add", "--help"],
    ["list", "--help"], ["remove", "--help"],
    ["update", "--help"], ["init", "--help"],
    ["install", "--help"], ["doctor", "--help"],
    [], ["help"], ["help", "add"],
  ])
  func help(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.success(arguments)
    #expect(result.stdout.contains("USAGE:"))
    let isRoot = arguments.isEmpty || arguments == ["--help"] || arguments == ["help"]
    #expect(result.stdout.contains("--version") == isRoot)
  }

  @Test func commandsAcceptOptionsAndPositionals() throws {
    let fixture = try CLIFixture()
    try fixture.skill("unknown")
    try fixture.commit()
    let listing = try fixture.success([
      "list", "--json", "--path", "skills", fixture.source.path,
      "--scope=user", "--full-depth",
    ]).json()
    let skills = try #require(listing["skills"] as? [[String: Any]])
    #expect(skills.compactMap { $0["name"] as? String } == ["unknown"])
    try fixture.success([
      "add", "--scope", "user", "--agent", "codex", "--mode=copy",
      fixture.source.path, "unknown",
    ])
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.home.appendingPathComponent(".agents/skills/unknown/SKILL.md").path))
  }

  @Test func helpStopsCommandValidationAtTerminator() throws {
    let fixture = try CLIFixture()
    #expect(try fixture.success(["--help", "--", "unknown"]).stdout.contains("USAGE:"))
  }

  @Test(arguments: [["--scope", "user"], ["--scope=user"]])
  func helpOptionValuesAreNotCommands(_ options: [String]) throws {
    let result = try CLIFixture().run(["help", "list"] + options)
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.contains("Unknown option '--scope'"))
  }

  @Test func emptyInstallJSON() throws {
    let result = try CLIFixture().success(["install", "--json"]).json()
    #expect(Set(result.keys) == ["schemaVersion", "scope", "skills"])
    #expect((result["skills"] as? [Any])?.isEmpty == true)
  }

  @Test func rootHelpExamples() throws {
    let fixture = try CLIFixture()
    let result = try fixture.success(["--help"])
    #expect(result.stdout.contains("OVERVIEW: Manage agent skills from declared sources."))
    #expect(
      result.stdout.contains(
        """
        Examples:
          skill add github.com/owner/skills pdf-forms
          skill list
          skill install
          skill update               Preview what re-resolving would change
          skill update --apply       Write the updates and the new lock
        """))
  }

  @Test(arguments: [
    (
      [
        ["add"], ["list"], ["remove"], ["update"],
        ["install"], ["doctor"],
      ],
      "Where state lives: project (./.agent) or user (~/.agents). Default: project."
    ),
    (
      [["add"]],
      "Agent to install for: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: the agents already recorded for this skill or source, else the declaration's agents, else codex and claude-code."
    ),
    (
      [["list"], ["remove"], ["doctor"]],
      "Limit to this agent: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: all recipients."
    ),
    (
      [["add"]],
      "How to install: link (default), copy, or edit (a live link to a local source)."
    ),
    (
      [["add"], ["list"]],
      "Search this subdirectory of the source."
    ),
    ([["doctor"]], "Audit these project directories read-only. Repeat for several."),
    (
      [["add"]],
      "Skills to add. Omit to add the source's only skill, or to list the choices when it has several."
    ),
  ])
  func optionHelp(commands: [[String]], text: String) throws {
    let fixture = try CLIFixture()
    for command in commands {
      let result = try fixture.success(command + ["--help"])
      #expect(
        result.stdout.split(whereSeparator: \.isWhitespace).joined(separator: " ").contains(text))
    }
  }

  @Test func version() throws {
    let fixture = try CLIFixture()
    #expect(try fixture.success(["--version"]).stdout == "skill \(BuildInfo.version)\n")
  }

  @Test(arguments: [
    ["unknown"], ["unknown", "--help"], ["help", "unknown"], ["remove"],
    ["--help", "unknown"], ["-h", "unknown"], ["unknown", "-h"],
    ["--help", "-"], ["-", "-h"], ["help", "unknown", "--help"],
    ["help", "list", "--scope=user", "unknown"], ["--version", "--help", "unknown"],
    ["install", "--agent", "codex"], ["install", "--mode", "copy"],
    ["add", ".", "--exact", "bad"], ["update", "--json", "--apply"],
    ["add", ".", "--version"],
    ["list", "--version"], ["remove", "demo", "--version"],
    ["update", "--version"], ["init", "--version"],
    ["install", "--version"], ["doctor", "--version"],
    ["--version", "list"],
  ])
  func usageFailures(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.run(arguments)
    #expect(result.status == 64)
    #expect(result.stdout.isEmpty && result.stderr.hasPrefix("Error:"))
    #expect(result.stderr.split(separator: "\n").dropFirst().allSatisfy { $0.hasPrefix("  ") })
    #expect(result.stderr.hasSuffix("\n  Run 'skill --help' for usage.\n"))
    if arguments.contains("unknown") {
      #expect(result.stderr.contains("Unknown command 'unknown'"))
    } else if arguments.contains("-") {
      #expect(result.stderr.contains("Unknown command '-'"))
    }
  }

  @Test func operationFailureAndEnvironmentIsolation() throws {
    let fixture = try CLIFixture()
    #expect(fixture.environment["HOME"] == fixture.home.path)
    #expect(
      fixture.environment["CODEX_HOME"] == nil && fixture.environment["CLAUDE_CONFIG_DIR"] == nil)
    #expect(!fixture.environment.keys.contains { $0.hasPrefix("XDG_") })
    #expect(
      Set(fixture.environment.keys.filter { $0.hasPrefix("GIT_CONFIG_") }) == [
        "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL",
      ])
    let result = try fixture.run(["remove", "missing\nname"])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(result.stderr.split(separator: "\n").dropFirst().allSatisfy { $0.hasPrefix("  ") })
    #expect(result.stderr.hasSuffix("\n  Check the source, names, and paths.\n"))
  }
}
