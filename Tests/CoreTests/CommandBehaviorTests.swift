import Foundation
import Testing

@testable import Core

@Suite("Runtime Service Workflows")
struct RuntimeServiceWorkflowTests {
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
