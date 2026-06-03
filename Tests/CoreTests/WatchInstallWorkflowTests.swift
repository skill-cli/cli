import Foundation
import Testing

@testable import Core

@Suite("Watch Install Workflows")
struct WatchInstallWorkflowTests {
  @Test func installsSingleWatchedPathAndReportsReviewStateInList() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    for name in ["alpha", "beta"] {
      let skillDir = sourceRoot.appendingPathComponent("skills/\(name)")
      try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
      try """
      ---
      name: \(name)
      description: \(name) skill
      ---
      """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(sourceRoot.path, environment: environment)
    let watch = try WatchService.add(
      source: source, path: "skills/beta", requestedID: "beta-watch", environment: environment,
      apply: true)
    _ = try WatchService.check(
      watchID: watch.watchID, path: "skills/beta", environment: environment, apply: true)
    _ = try WatchService.done(
      watchID: watch.watchID, path: "skills/beta", commit: "manual-commit", note: "reviewed",
      environment: environment, apply: true)

    let outcome = try RuntimeService.add(
      AddOptions(
        source: "beta-watch",
        agents: [.codex],
        scope: .project,
        mode: .copy,
        environment: environment
      ))
    #expect(outcome.installed.map(\.skill) == ["beta"])

    let installed = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment)
    let beta = try #require(installed.first { $0.name == "beta" })
    #expect(beta.watchID == "beta-watch")
    #expect(beta.reviewedCommit == "manual-commit")
  }

  @Test func watchOnlyWritesLedgerAndWatchInstallUsesReviewedBaseline() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    let skillDir = repo.appendingPathComponent("skills/demo")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: demo
    description: Baseline
    ---
    baseline
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try initGitRepo(repo)
    let baseline = try gitHead(repo)
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    let watchOnly = try RuntimeService.add(
      AddOptions(
        source: repo.path,
        skillNames: ["demo"],
        scope: .project,
        mode: .copy,
        watchOnly: true,
        environment: environment))
    #expect(watchOnly.watched.first?.watchBaseline == baseline)
    #expect(
      !FileManager.default.fileExists(
        atPath: InstallLockStore.projectLockURL(environment: environment).path))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/demo/SKILL.md").path))

    let installed = try RuntimeService.add(
      AddOptions(
        source: repo.path,
        agents: [.codex],
        skillNames: ["demo"],
        scope: .project,
        mode: .copy,
        watch: true,
        environment: environment))
    #expect(installed.installed.map(\.skill) == ["demo"])

    try """
    ---
    name: demo
    description: Unreviewed
    ---
    current
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "unreviewed"])
    let head = try gitHead(repo)
    #expect(head != baseline)

    _ = try RuntimeService.add(
      AddOptions(
        source: repo.path,
        agents: [.codex],
        skillNames: ["demo"],
        scope: .project,
        mode: .copy,
        watch: true,
        environment: environment))
    let ledger = try WatchLedgerStore.load(environment: environment)
    #expect(ledger.watches.count == 1)
    #expect(ledger.watches[0].currentHead == head)
    #expect(ledger.watches[0].watchBaseline == baseline)

    let installedText = try String(
      contentsOf: project.appendingPathComponent(".agents/skills/demo/SKILL.md"), encoding: .utf8)
    #expect(installedText.contains("Baseline"))
    #expect(!installedText.contains("Unreviewed"))
  }
}
