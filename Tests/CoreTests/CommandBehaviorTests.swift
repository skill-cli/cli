import Foundation
import Testing

@testable import Core

@Suite("Runtime Service Workflows")
struct RuntimeServiceWorkflowTests {
  @Test(arguments: ["add", "watch", "watch-only"], [InstallScope.project, .global])
  func rejectsAddBeforeResolvingSource(_ command: String, scope: InstallScope) throws {
    let root = try commandBehaviorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = RuntimeEnvironment(
      projectDirectory: root, homeDirectory: root.appendingPathComponent("home"), environment: [:])
    let url = InstallLockStore.lockURL(scope: scope, environment: environment)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let malformed = Data("{broken".utf8)
    try malformed.write(to: url)

    #expect(throws: CoreError.invalidState("resolved file \(url.path) could not be decoded")) {
      try RuntimeService.add(
        AddOptions(
          source: root.appendingPathComponent("missing-source").path, scope: scope,
          watch: command == "watch", watchOnly: command == "watch-only", environment: environment))
    }
    #expect(try Data(contentsOf: url) == malformed)
    #expect(
      !FileManager.default.fileExists(
        atPath: WatchLedgerStore.ledgerURL(environment: environment).path))
  }

  @Test(arguments: [InstallMode.copy, .symlink, .edit], [InstallScope.project, .global])
  func rejectsAddBeforeCreatingInstallDirectories(_ mode: InstallMode, scope: InstallScope) throws {
    let root = try commandBehaviorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try writeCommandBehaviorSkill(root: source, path: "two", name: "two")
    let environment = RuntimeEnvironment(
      projectDirectory: root, homeDirectory: root.appendingPathComponent("home"), environment: [:])
    let url = InstallLockStore.lockURL(scope: scope, environment: environment)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let malformed = Data("{broken\n".utf8)
    try malformed.write(to: url)

    #expect(throws: CoreError.self) {
      try RuntimeService.add(
        AddOptions(
          source: source.path, agents: [.codex, .claudeCode], scope: scope, mode: mode,
          environment: environment))
    }
    #expect(try Data(contentsOf: url) == malformed)
    for agent in [AgentID.codex, .claudeCode] {
      let directory = AgentRegistry.installSkillsDirectory(
        for: agent, scope: scope, environment: environment)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test(arguments: [
    "add", "install", "update", "remove-all", "remove-named", "watch",
    "update-watch-inferred", "update-watch-explicit",
  ])
  func rejectsMutationsBeforeChangingInstalledFiles(_ command: String) throws {
    let root = try commandBehaviorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let sourceSkill = try writeCommandBehaviorSkill(root: source, path: "one", name: "one")
    let environment = RuntimeEnvironment(
      projectDirectory: root, homeDirectory: root.appendingPathComponent("home"), environment: [:])
    let outcome = try RuntimeService.add(
      AddOptions(
        source: source.path, agents: [.codex, .claudeCode], mode: .copy, watch: true,
        environment: environment))
    let installedFiles = outcome.installed.map {
      URL(fileURLWithPath: $0.path).appendingPathComponent("SKILL.md")
    }
    let originalFiles = try installedFiles.map { try Data(contentsOf: $0) }
    try Data("changed source".utf8).write(to: sourceSkill.appendingPathComponent("extra.txt"))
    try writeCommandBehaviorSkill(root: source, path: "two", name: "two")
    let url = InstallLockStore.projectResolvedURL(environment: environment)
    var malformed = try Data(contentsOf: url)
    malformed.append(Data(",".utf8))
    try malformed.write(to: url)

    #expect(throws: CoreError.invalidState("resolved file \(url.path) could not be decoded")) {
      switch command {
      case "add", "watch":
        _ = try RuntimeService.add(
          AddOptions(
            source: source.path, agents: [.codex, .claudeCode], mode: .copy, all: true,
            watch: command == "watch", environment: environment))
      case "install":
        _ = try RuntimeService.installResolved(environment: environment)
      case "update":
        _ = try RuntimeService.updateInstalled(
          scope: .project, environment: environment, apply: true)
      case "remove-all", "remove-named":
        _ = try RuntimeService.remove(
          skillNames: command == "remove-named" ? ["one"] : [], scope: .project,
          agents: [.codex, .claudeCode], environment: environment)
      default:
        _ = try RuntimeService.updateFromWatch(
          outcome.watched[0].watchID, all: true,
          agents: command == "update-watch-explicit" ? [.codex, .claudeCode] : nil,
          environment: environment, apply: true)
      }
    }
    #expect(try Data(contentsOf: url) == malformed)
    for (file, original) in zip(installedFiles, originalFiles) {
      #expect(try Data(contentsOf: file) == original)
      #expect(
        !FileManager.default.fileExists(
          atPath: file.deletingLastPathComponent().appendingPathComponent("extra.txt").path))
      #expect(
        !FileManager.default.fileExists(
          atPath: file.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("two").path))
    }
  }

  @Test(arguments: [InstallScope.project, .global])
  func watchedUpdateRejectsMalformedStateBeforeInstallingInEitherScope(
    _ malformedScope: InstallScope
  ) throws {
    let root = try commandBehaviorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let sourceSkill = try writeCommandBehaviorSkill(root: source, path: "one", name: "one")
    let environment = RuntimeEnvironment(
      projectDirectory: root, homeDirectory: root.appendingPathComponent("home"), environment: [:])
    var installed: [InstallResult] = []
    var watchID = ""
    let scopes = [InstallScope.project, .global]
    for scope in scopes {
      let outcome = try RuntimeService.add(
        AddOptions(
          source: source.path, scope: scope, mode: .copy, watch: true, environment: environment))
      installed += outcome.installed
      watchID = try #require(outcome.watched.first?.watchID)
    }
    let lockURLs = scopes.map { InstallLockStore.lockURL(scope: $0, environment: environment) }
    let malformedURL = InstallLockStore.lockURL(scope: malformedScope, environment: environment)
    try Data("{broken".utf8).write(to: malformedURL)
    let originalLocks = try lockURLs.map { try Data(contentsOf: $0) }
    try Data("changed source".utf8).write(to: sourceSkill.appendingPathComponent("extra.txt"))

    #expect(throws: CoreError.self) {
      try RuntimeService.updateFromWatch(
        watchID, all: true, environment: environment, apply: true)
    }
    for (url, original) in zip(lockURLs, originalLocks) {
      #expect(try Data(contentsOf: url) == original)
    }
    for result in installed {
      #expect(
        !FileManager.default.fileExists(
          atPath: URL(fileURLWithPath: result.path).appendingPathComponent("extra.txt").path))
    }
  }

  @Test(arguments: ["skills.resolved", "skills-lock.json"])
  func doctorReportsUndecodableResolvedState(_ filename: String) throws {
    let root = try commandBehaviorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = RuntimeEnvironment(
      projectDirectory: root, homeDirectory: root, environment: [:])
    let url = root.appendingPathComponent(".agent/\(filename)")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{broken".utf8).write(to: url)

    let report = try RuntimeService.doctor(
      scope: .project, agents: [.codex], environment: environment)
    #expect(!report.ok)
    let check = try #require(report.checks.first { $0.id == "resolved-file" })
    #expect(check.status == .error)
    #expect(check.message.contains(url.path))
    #expect(check.message.contains("could not be decoded"))
    #expect(check.path == (filename == "skills.resolved" ? url.path : nil))
    #expect(check.hint == "Repair or restore the resolved file before managing installed skills.")
    #expect(report.checks.count == 1)
  }

  @Test func installsAllSkillsAndPreservesLockSourceIdentity() throws {
    let project = try commandBehaviorTemporaryDirectory()
    let home = try commandBehaviorTemporaryDirectory()
    let sourceRoot = try commandBehaviorTemporaryDirectory()
    _ = try writeCommandBehaviorSkill(root: sourceRoot, path: "skills/one", name: "one")
    _ = try writeCommandBehaviorSkill(root: sourceRoot, path: "skills/two", name: "two")
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    #expect(throws: CoreError.self) {
      _ = try SourceResolver.resolve("./missing-source", environment: environment)
    }

    let listed = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        skillNames: ["one"],
        listOnly: true,
        environment: environment))
    #expect(listed.availableSkills.map(\.name) == ["one"])

    let wildcard = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: AgentID.allCases,
        scope: .project,
        mode: .copy,
        all: true,
        environment: environment))
    #expect(Set(wildcard.installed.map(\.agent)) == Set(AgentID.allCases))
    #expect(Set(wildcard.installed.map(\.skill)) == ["one", "two"])

    for (rawSource, expectedLocation) in [
      ("git@github.com:owner/repo.git", "git@github.com:owner/repo.git"),
      (
        "ssh://git@stash.myrepo.com:7999/my/skills.git",
        "ssh://git@stash.myrepo.com:7999/my/skills.git"
      ),
      ("https://github.com/owner/repo.git", "owner/repo"),
    ] {
      let parsed = try SourceParser.parse(rawSource)
      let resolved = ResolvedSource(
        parsed: parsed,
        identity: SourceParser.identity(for: parsed),
        checkoutURL: sourceRoot,
        revision: "abc123",
        requestedRef: parsed.ref)
      let request = InstallRequest(
        source: resolved,
        skills: [
          Skill(
            name: "lock-\(PathSafety.sanitizeName(rawSource))",
            description: "Lock source",
            path: sourceRoot.appendingPathComponent("skills/one").path,
            skillFile: sourceRoot.appendingPathComponent("skills/one/SKILL.md").path)
        ],
        agents: [.codex],
        scope: .project,
        mode: .copy,
        environment: environment)
      _ = try Installer.install(request)
      let lock = try InstallLockStore.load(scope: .project, environment: environment)
      #expect(lock.pins.contains { $0.location == expectedLocation })
    }
  }

  @Test func createsSkillSkeletonInCurrentOrNamedDirectory() throws {
    let project = try commandBehaviorTemporaryDirectory()

    let cwdSkill = try RuntimeService.initializeSkill(named: nil, directory: project)
    #expect(cwdSkill.standardizedFileURL.path == project.standardizedFileURL.path)
    let cwdSkillFile = project.appendingPathComponent("SKILL.md")
    #expect(FileManager.default.fileExists(atPath: cwdSkillFile.path))
    let cwdContent = try String(contentsOf: cwdSkillFile, encoding: .utf8)
    #expect(cwdContent.contains("Instructions for the agent to follow"))
    #expect(cwdContent.contains("## When to use"))

    let named = try RuntimeService.initializeSkill(named: "My Test Skill", directory: project)
    #expect(named.lastPathComponent == "my-test-skill")
    #expect(FileManager.default.fileExists(atPath: named.appendingPathComponent("SKILL.md").path))

    #expect(throws: CoreError.self) {
      _ = try RuntimeService.initializeSkill(named: "My Test Skill", directory: project)
    }
  }

  @Test func listsRemovesAndSkipsDeletedSourceSkillsOnUpdate() throws {
    let project = try commandBehaviorTemporaryDirectory()
    let home = try commandBehaviorTemporaryDirectory()
    let sourceRoot = try commandBehaviorTemporaryDirectory()
    let skillDir = try writeCommandBehaviorSkill(
      root: sourceRoot, path: "skills/remove-me", name: "remove-me")
    _ = try writeCommandBehaviorSkill(root: sourceRoot, path: "skills/keep-me", name: "keep-me")
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    #expect(
      try RuntimeService.listInstalled(
        scope: .project, agents: AgentID.allCases, environment: environment
      )
      .isEmpty)

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        skillNames: ["remove-me", "keep-me"],
        scope: .project,
        mode: .copy,
        all: true,
        environment: environment))
    let installed = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment)
    #expect(installed.map(\.name).sorted() == ["keep-me", "remove-me"])

    #expect(throws: CoreError.self) {
      _ = try RuntimeService.remove(
        skillNames: ["missing"], scope: .project, agents: [.codex], environment: environment)
    }

    let removed = try RuntimeService.remove(
      skillNames: ["REMOVE-ME"], scope: .project, agents: AgentID.allCases, environment: environment
    )
    #expect(removed.contains { $0.contains("remove-me") })
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/keep-me/SKILL.md").path))

    try FileManager.default.removeItem(at: sourceRoot.appendingPathComponent("skills/keep-me"))
    let updates = try RuntimeService.updateInstalled(
      scope: .project, environment: environment, apply: false)
    #expect(updates.contains { $0.skill == "keep-me" && !$0.changed && $0.installed.isEmpty })
    _ = skillDir
  }

  @Test(arguments: [InstallMode.copy, .edit])
  func removesManagedRecordsWithMissingInstallationsOrSources(_ mode: InstallMode) throws {
    let project = try commandBehaviorTemporaryDirectory()
    let home = try commandBehaviorTemporaryDirectory()
    let sourceRoot = try commandBehaviorTemporaryDirectory()
    _ = try writeCommandBehaviorSkill(root: sourceRoot, path: "skills/gone", name: "gone")
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex],
        skillNames: ["gone"],
        scope: .project,
        mode: mode,
        environment: environment))
    try FileManager.default.removeItem(at: sourceRoot)
    try FileManager.default.removeItem(at: project.appendingPathComponent(".agents/skills/gone"))

    #expect(
      try RuntimeService.listInstalled(scope: .project, agents: [.codex], environment: environment)
        .isEmpty)
    let report = try RuntimeService.doctor(
      scope: .project, agents: [.codex], environment: environment)
    #expect(!report.ok)
    if mode == .edit {
      #expect(report.checks.contains { $0.message.contains("source-missing") })
    }
    #expect(
      try RuntimeService.removableSkillNames(
        scope: .project, agents: [.codex], environment: environment
      ).contains("gone"))

    _ = try RuntimeService.remove(
      skillNames: ["gone"], scope: .project, agents: [.codex], environment: environment)
    #expect(try InstallLockStore.load(scope: .project, environment: environment).pins.isEmpty)
    #expect(
      try RuntimeService.doctor(scope: .project, agents: [.codex], environment: environment).ok)
  }

  @Test(arguments: [InstallScope.project, .global])
  func removesMissingRecordsOnlyForSelectedAgentsAndScope(_ scope: InstallScope) throws {
    let root = try commandBehaviorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let sourceSkill = try writeCommandBehaviorSkill(root: source, path: "gone", name: "gone")
    let environment = RuntimeEnvironment(
      projectDirectory: root, homeDirectory: root.appendingPathComponent("home"), environment: [:])
    for installScope in [InstallScope.project, .global] {
      _ = try RuntimeService.add(
        AddOptions(
          source: source.path, agents: [.codex, .cursor], scope: installScope, mode: .edit,
          environment: environment))
      let canonical = AgentRegistry.canonicalSkillsDirectory(
        scope: installScope, environment: environment)
      try FileManager.default.removeItem(at: canonical.appendingPathComponent("gone"))
    }
    let otherScope: InstallScope = scope == .project ? .global : .project
    let otherLockURL = InstallLockStore.lockURL(scope: otherScope, environment: environment)
    let otherLock = try Data(contentsOf: otherLockURL)
    let lockURL = InstallLockStore.lockURL(scope: scope, environment: environment)
    let lockBefore = try Data(contentsOf: lockURL)
    #expect(
      try RuntimeService.removableSkillNames(
        scope: scope, agents: [.codex], environment: environment) == ["gone"])
    #expect(
      try RuntimeService.removableSkillNames(
        scope: scope, agents: [.claudeCode], environment: environment
      ).isEmpty)
    #expect(throws: CoreError.self) {
      try RuntimeService.remove(
        skillNames: ["gone"], scope: scope, agents: [.claudeCode], environment: environment)
    }
    #expect(throws: CoreError.self) {
      try RuntimeService.remove(
        skillNames: ["gone", "unknown"], scope: scope, agents: [.codex], environment: environment)
    }
    #expect(try Data(contentsOf: lockURL) == lockBefore)

    let removed = try RuntimeService.remove(
      skillNames: ["gone"], scope: scope, agents: [.codex], environment: environment)
    #expect(removed.isEmpty)
    let remaining = try RuntimeService.listManaged(
      scope: scope, agents: AgentID.allCases, environment: environment)
    #expect(remaining.map(\.name) == ["gone"])
    #expect(remaining.map(\.agent) == [.cursor])
    #expect(try Data(contentsOf: otherLockURL) == otherLock)
    #expect(
      FileManager.default.fileExists(atPath: sourceSkill.appendingPathComponent("SKILL.md").path))
  }

  @Test func installsWatchedSkillFromReviewedBaselineAndKeepsDryRunReadOnly() throws {
    let project = try commandBehaviorTemporaryDirectory()
    let home = try commandBehaviorTemporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    let skillDir = repo.appendingPathComponent("skills/demo")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: demo
    description: Baseline description
    ---
    baseline body
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try commandBehaviorInitGitRepo(repo)
    let baseline = try commandBehaviorGitHead(repo)
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(repo.path, environment: environment)
    _ = try WatchService.add(
      source: source, path: "skills/demo", requestedID: "demo", environment: environment,
      apply: true)

    try """
    ---
    name: demo
    description: Unreviewed current head
    ---
    current body
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "unreviewed"])
    let head = try commandBehaviorGitHead(repo)
    #expect(head != baseline)

    _ = try WatchService.refreshWatchedHead(environment: environment, apply: true)
    var ledger = try WatchLedgerStore.load(environment: environment)
    #expect(ledger.watches[0].currentHead == head)
    #expect(ledger.watches[0].watchedPaths[0].reviewCoverage.reviewedCommit == nil)

    let installed = try RuntimeService.add(
      AddOptions(source: "demo", scope: .project, mode: .copy, environment: environment))
    #expect(installed.source.watchInstallCommit == baseline)
    let installedSkill = project.appendingPathComponent(".agents/skills/demo/SKILL.md")
    let installedText = try String(contentsOf: installedSkill, encoding: .utf8)
    #expect(installedText.contains("Baseline description"))
    #expect(!installedText.contains("Unreviewed current head"))

    ledger = try WatchLedgerStore.load(environment: environment)
    #expect(ledger.watches[0].watchedPaths[0].lastSeen == nil)
    #expect(ledger.watches[0].watchedPaths[0].reviewCoverage.reviewedCommit == nil)

    let remoteProject = try commandBehaviorTemporaryDirectory()
    let checkout = remoteProject.appendingPathComponent(".agent/cache/sources/remote")
    let remoteEnvironment = RuntimeEnvironment(
      projectDirectory: remoteProject, homeDirectory: home, environment: [:])
    let remoteLedger = WatchLedger(watches: [
      WatchRecord(
        watchID: "remote",
        source: SourcePin(
          identity: "remote",
          kind: "remoteSourceControl",
          location: repo.path,
          state: PinState(branch: "master")),
        checkoutPath: checkout.path,
        watchBaseline: baseline,
        currentHead: baseline,
        watchedPaths: [WatchPathState(path: "skills/demo")])
    ])
    try WatchLedgerStore.save(remoteLedger, environment: remoteEnvironment)
    _ = try WatchService.refreshWatchedHead(
      watchID: "remote", environment: remoteEnvironment, apply: false)
    #expect(!FileManager.default.fileExists(atPath: checkout.path))
    let dryLedger = try WatchLedgerStore.load(environment: remoteEnvironment)
    #expect(dryLedger == remoteLedger)
  }

  @Test func recordsWatchReviewCloseoutReceiptFields() throws {
    let project = try commandBehaviorTemporaryDirectory()
    let home = try commandBehaviorTemporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    _ = try writeCommandBehaviorSkill(root: repo, path: "skills/demo", name: "demo")
    try commandBehaviorInitGitRepo(repo)
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(repo.path, environment: environment)
    _ = try WatchService.add(
      source: source, path: "skills/demo", requestedID: "demo", environment: environment,
      apply: true)
    _ = try WatchService.done(
      watchID: "demo",
      path: "skills/demo",
      commit: "reviewed-commit",
      note: "external receipt",
      status: "reviewed",
      outcome: "accepted",
      openItems: 0,
      granularity: "path",
      environment: environment,
      apply: true)

    let coverage = try #require(
      WatchLedgerStore.load(environment: environment).watches.first?.watchedPaths.first?
        .reviewCoverage)
    #expect(coverage.reviewedCommit == "reviewed-commit")
    #expect(coverage.status == "reviewed")
    #expect(coverage.outcome == "accepted")
    #expect(coverage.openItems == 0)
    #expect(coverage.granularity == "path")
  }

}

private func commandBehaviorTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-command-behavior-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@discardableResult
private func writeCommandBehaviorSkill(root: URL, path: String, name: String) throws -> URL {
  let skillDir = root.appendingPathComponent(path)
  try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
  try """
  ---
  name: \(name)
  description: \(name) description
  ---
  body
  """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  return skillDir
}

private func commandBehaviorInitGitRepo(_ repo: URL) throws {
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "init", repo.path])
  try ProcessRunner.run(
    "/usr/bin/env",
    arguments: ["git", "-C", repo.path, "config", "user.email", "tests@example.com"])
  try ProcessRunner.run(
    "/usr/bin/env", arguments: ["git", "-C", repo.path, "config", "user.name", "Tests"])
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
  try ProcessRunner.run(
    "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "initial"])
}

private func commandBehaviorGitHead(_ repo: URL) throws -> String {
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "rev-parse", "HEAD"])
    .stdout
    .trimmingCharacters(in: .whitespacesAndNewlines)
}
