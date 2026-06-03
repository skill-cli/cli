import Foundation
import Testing

@testable import Core

extension RuntimeServiceWorkflowTests {
  @Test func initializesSkillSkeletonsAndRejectsOverwrites() throws {
    let root = try temporaryDirectory()
    let created = try RuntimeService.initializeSkill(named: "My Skill", directory: root)
    let skillFile = created.appendingPathComponent("SKILL.md")
    #expect(created.lastPathComponent == "my-skill")
    #expect(FileManager.default.fileExists(atPath: skillFile.path))
    let parsed = try #require(try Discovery.parseSkill(at: skillFile, includeInternal: true))
    #expect(parsed.name == "my-skill")

    #expect(throws: CoreError.self) {
      _ = try RuntimeService.initializeSkill(named: "My Skill", directory: root)
    }
  }

  @Test func installsCopiedSkillsAndUpdatesProjectLock() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    let skillDir = sourceRoot.appendingPathComponent("skills/example")
    try FileManager.default.createDirectory(
      at: skillDir.appendingPathComponent(".local"), withIntermediateDirectories: true)
    try """
    ---
    name: Example Skill
    description: Example description
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try "keep".write(
      to: skillDir.appendingPathComponent(".local/config"), atomically: true, encoding: .utf8)
    try "drop".write(
      to: skillDir.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let outcome = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex, .cursor],
        skillNames: ["Example Skill"],
        scope: .project,
        mode: .copy,
        environment: environment
      ))

    #expect(outcome.installed.count == 2)
    let installed = project.appendingPathComponent(".agents/skills/example-skill")
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("SKILL.md").path))
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent(".local/config").path)
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: installed.appendingPathComponent("metadata.json").path))

    let lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock.pins.count == 1)
    #expect(lock.pins[0].skills[0].installations.count == 2)
    #expect(lock.pins[0].kind == "localFileSystem")

    try FileManager.default.removeItem(at: project.appendingPathComponent(".agents/skills"))
    let resolvedInstall = try RuntimeService.installProjectResolved(environment: environment)
    #expect(resolvedInstall.count == 2)
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("SKILL.md").path))

    try "new".write(
      to: skillDir.appendingPathComponent("extra.md"), atomically: true, encoding: .utf8)
    let pendingUpdates = try RuntimeService.updateInstalled(
      scope: .project, environment: environment, apply: false)
    #expect(
      pendingUpdates.contains { $0.skill == "Example Skill" && $0.changed && $0.installed.isEmpty })
    let appliedUpdates = try RuntimeService.updateInstalled(
      scope: .project, environment: environment, apply: true)
    #expect(
      appliedUpdates.contains { $0.skill == "Example Skill" && $0.changed && !$0.installed.isEmpty }
    )
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("extra.md").path))

    _ = try RuntimeService.remove(
      skillNames: ["Example Skill"], scope: .project, agents: [.codex, .cursor],
      environment: environment)
    let afterRemove = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(afterRemove.pins.isEmpty)
  }

  @Test func cleansRemovedFilesAndPreservesDotfilesOnReinstall() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    let skillDir = sourceRoot.appendingPathComponent("skills/clean")
    try FileManager.default.createDirectory(
      at: skillDir.appendingPathComponent(".config"), withIntermediateDirectories: true)
    try """
    ---
    name: Clean Skill
    description: Clean install skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try "keep".write(
      to: skillDir.appendingPathComponent(".config/settings"), atomically: true, encoding: .utf8)
    try "old".write(
      to: skillDir.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path, agents: [.codex], skillNames: ["Clean Skill"], scope: .project,
        mode: .copy, environment: environment))
    let installed = project.appendingPathComponent(".agents/skills/clean-skill")
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("old.txt").path))

    try FileManager.default.removeItem(at: skillDir.appendingPathComponent("old.txt"))
    try "new".write(
      to: skillDir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path, agents: [.codex], skillNames: ["Clean Skill"], scope: .project,
        mode: .copy, environment: environment))

    #expect(
      !FileManager.default.fileExists(atPath: installed.appendingPathComponent("old.txt").path))
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("new.txt").path))
    #expect(
      FileManager.default.fileExists(
        atPath: installed.appendingPathComponent(".config/settings").path))
  }
}

extension InstallLockTests {
  @Test func returnsEmptyLockForCorruptJSON() throws {
    let project = try temporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: try temporaryDirectory(), environment: [:])
    try FileManager.default.createDirectory(
      at: InstallLockStore.projectLockURL(environment: environment).deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try """
    {
      "version": 1,
      "pins": [
    <<<<<<< HEAD
      ]
    }
    """.write(
      to: InstallLockStore.projectLockURL(environment: environment), atomically: true,
      encoding: .utf8
    )

    let lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock == LockFile())
  }

  @Test func migratesLocalLockEntriesFromCompatibilityFormat() throws {
    let project = try temporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: try temporaryDirectory(), environment: [:])
    try FileManager.default.createDirectory(
      at: InstallLockStore.projectLockURL(environment: environment).deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try """
    {
      "version": 1,
      "skills": {
        "demo-skill": {
          "source": "owner/repo",
          "ref": "main",
          "sourceType": "github",
          "skillPath": "skills/demo-skill/SKILL.md",
          "computedHash": "abc123"
        }
      }
    }
    """.write(
      to: InstallLockStore.projectLockURL(environment: environment), atomically: true,
      encoding: .utf8
    )

    let lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock.pins.count == 1)
    #expect(lock.pins[0].identity == "owner/repo")
    #expect(lock.pins[0].location == "https://github.com/owner/repo.git")
    #expect(lock.pins[0].skills[0].path == "skills/demo-skill/SKILL.md")
    #expect(lock.pins[0].skills[0].contentHash == "abc123")
  }
}

extension InstalledSkillListingTests {
  @Test func listsDefaultSymlinkInstallations() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    let skillDir = sourceRoot.appendingPathComponent("skills/linked")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: linked
    description: Linked skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path, agents: [.codex], skillNames: ["linked"], environment: environment)
    )

    let installed = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment)
    #expect(installed.contains { $0.name == "linked" })
  }

  @Test func scansCodexUserDirectoryForGlobalList() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let codexHome = try temporaryDirectory()
    let skillDir = codexHome.appendingPathComponent("skills/native")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: native
    description: Native Codex skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: ["CODEX_HOME": codexHome.path]
    )
    let installed = try RuntimeService.listInstalled(
      scope: .global, agents: [.codex], environment: environment)
    #expect(
      installed.contains {
        $0.name == "native"
          && URL(fileURLWithPath: $0.path).standardizedFileURL.path
            == skillDir.standardizedFileURL.path
      })
  }

  @Test func usesXDGStateForGlobalLockAndXDGConfigForOpenCodeListing() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let xdgState = try temporaryDirectory()
    let xdgConfig = try temporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: [
        "XDG_STATE_HOME": xdgState.path,
        "XDG_CONFIG_HOME": xdgConfig.path,
      ]
    )

    #expect(
      InstallLockStore.globalLockURL(environment: environment).standardizedFileURL.path
        == xdgState.appendingPathComponent("skills/skills.resolved").standardizedFileURL.path)

    let skillDir = xdgConfig.appendingPathComponent("opencode/skills/native-open")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: native-open
    description: Native OpenCode skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let installed = try RuntimeService.listInstalled(
      scope: .global, agents: [.opencode], environment: environment)
    #expect(installed.contains { $0.name == "native-open" })
  }
}

extension InstallerTests {
  @Test func linksClaudeProjectInstallThroughCanonicalDirectory() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    let skillDir = sourceRoot.appendingPathComponent("skills/claude")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: claude
    description: Claude skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path, agents: [.claudeCode], skillNames: ["claude"],
        environment: environment))

    let canonical = project.appendingPathComponent(".agents/skills/claude")
    let claude = project.appendingPathComponent(".claude/skills/claude")
    #expect(
      FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))
    #expect((try? claude.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true)
  }
}

@Suite("Source Resolution")
struct SourceResolutionTests {
  @Test func resolvesSemanticVersionRequirementsFromTags() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    let skillDir = repo.appendingPathComponent("skills/demo")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: demo
    description: v1.0.0
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try initGitRepo(repo)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "tag", "1.0.0"])

    try """
    ---
    name: demo
    description: v1.1.0
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "v1.1.0"])
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "tag", "v1.1.0"])

    try """
    ---
    name: demo
    description: v2.0.0
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "v2.0.0"])
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "tag", "2.0.0"])

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let exact = try SourceResolver.resolve(
      "\(repo.path)@exact:1.0.0", environment: environment)
    #expect(exact.resolvedVersion == "1.0.0")
    #expect(exact.sourcePin.requirement == .exact("1.0.0"))
    #expect(exact.sourcePin.state.version == "1.0.0")
    let exactText = try String(
      contentsOf: exact.checkoutURL.appendingPathComponent("skills/demo/SKILL.md"),
      encoding: .utf8)
    #expect(exactText.contains("v1.0.0"))

    let from = try SourceResolver.resolve(
      repo.path,
      environment: environment,
      requirement: .upToNextMajor(from: "1.0.0")
    )
    #expect(from.resolvedVersion == "1.1.0")
    let range = try SourceResolver.resolve(
      repo.path,
      environment: environment,
      requirement: .range(from: "1.0.0", to: "1.1.0")
    )
    #expect(range.resolvedVersion == "1.0.0")

    #expect(throws: CoreError.self) {
      _ = try SourceResolver.resolve(
        "\(repo.path)@branch:main",
        environment: environment,
        requirement: .revision("abc123"))
    }
  }
}
