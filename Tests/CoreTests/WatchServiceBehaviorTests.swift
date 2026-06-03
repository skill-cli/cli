import Foundation
import Testing

@testable import Core

@Suite("Watch Service")
struct WatchServiceTests {
  @Test func loadsLegacyWatchLedgerButSavesStateFile() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let agentDirectory = project.appendingPathComponent(".agent")
    try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
    try """
    schema_version: 1
    watches:
    - watch_id: legacy
      source:
        identity: legacy
        kind: localFileSystem
        location: /tmp/legacy
        state: {}
        skills: []
      checkout_path:
      watch_baseline: baseline
      current_head: baseline
      watched_paths:
      - path: skills/legacy
        tracking: {}
        review_coverage: {}
      events: []
    """.write(
      to: agentDirectory.appendingPathComponent("watched-skills.yaml"),
      atomically: true,
      encoding: .utf8)

    let ledger = try WatchLedgerStore.load(environment: environment)
    #expect(ledger.watches.map(\.watchID) == ["legacy"])

    try WatchLedgerStore.save(ledger, environment: environment)
    #expect(
      FileManager.default.fileExists(
        atPath: agentDirectory.appendingPathComponent("skills-state.json").path))
    #expect(
      FileManager.default.fileExists(
        atPath: agentDirectory.appendingPathComponent("watched-skills.yaml").path))
  }

  @Test func refreshWatchedHeadDoesNotAdvanceReviewCursors() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    let skillDir = repo.appendingPathComponent("skills/sample")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: Sample
    description: Sample skill
    ---

    v1
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try initGitRepo(repo)
    let baseline = try gitHead(repo)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(repo.path, environment: environment)
    let watch = try WatchService.add(
      source: source, path: "skills/sample", environment: environment, apply: true)
    #expect(watch.watchBaseline == baseline)

    try "\nchange\n".write(
      to: skillDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "change"])
    let head = try gitHead(repo)
    #expect(head != baseline)

    _ = try WatchService.refreshWatchedHead(environment: environment, apply: true)
    var ledger = try WatchLedgerStore.load(environment: environment)
    var record = try #require(ledger.watches.first)
    #expect(record.currentHead == head)
    #expect(record.watchedPaths[0].lastSeen == nil)
    #expect(record.watchedPaths[0].tracking.lastCheckedCommit == nil)
    #expect(record.watchedPaths[0].reviewCoverage.reviewedCommit == nil)

    let packets = try WatchService.check(
      watchID: record.watchID, path: "skills/sample", environment: environment, apply: true)
    #expect(packets[0].baseCommit == baseline)
    #expect(packets[0].headCommit == head)
    #expect(packets[0].changedFiles.contains { $0.path == "skills/sample/notes.md" })

    ledger = try WatchLedgerStore.load(environment: environment)
    record = try #require(ledger.watches.first)
    #expect(record.watchedPaths[0].tracking.lastCheckedCommit == head)
    #expect(record.watchedPaths[0].lastSeen == nil)

    _ = try WatchService.done(
      watchID: record.watchID, path: "skills/sample", note: "distiller accepted",
      environment: environment, apply: true)
    ledger = try WatchLedgerStore.load(environment: environment)
    record = try #require(ledger.watches.first)
    #expect(record.watchedPaths[0].lastSeen == head)
    #expect(record.watchedPaths[0].reviewCoverage.reviewedCommit == head)
    #expect(record.events.contains { $0.type == "done" && $0.note == "distiller accepted" })
  }

  @Test func requiresCheckedCommitForWatchDoneUnlessExplicit() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    let skillDir = repo.appendingPathComponent("skills/sample")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: Sample
    description: Sample skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try initGitRepo(repo)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(repo.path, environment: environment)
    _ = try WatchService.add(
      source: source, path: "skills/sample", requestedID: "sample", environment: environment,
      apply: true)

    #expect(throws: CoreError.self) {
      _ = try WatchService.done(
        watchID: "sample", path: "skills/sample", environment: environment, apply: true)
    }

    _ = try WatchService.done(
      watchID: "sample", path: "skills/sample", commit: "manual-review", note: "explicit",
      environment: environment, apply: true)
    let ledger = try WatchLedgerStore.load(environment: environment)
    let state = try #require(ledger.watches.first?.watchedPaths.first)
    #expect(state.reviewCoverage.reviewedCommit == "manual-review")
  }

  @Test func appliesAllWatchOperationsOnlyToEligiblePaths() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    for name in ["a", "b"] {
      let skillDir = repo.appendingPathComponent("skills/\(name)")
      try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
      try """
      ---
      name: \(name)
      description: \(name) skill
      ---
      """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
    try initGitRepo(repo)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(repo.path, environment: environment)
    _ = try WatchService.add(
      source: source, path: "skills/a", requestedID: "multi", environment: environment, apply: true)
    _ = try WatchService.addPath(
      watchID: "multi", path: "skills/b", environment: environment, apply: true)

    _ = try WatchService.diff(watchID: "multi", path: "skills/b", environment: environment)
    var ledger = try WatchLedgerStore.load(environment: environment)
    var record = try #require(ledger.watches.first)
    #expect(record.watchedPaths.first { $0.path == "skills/b" }?.tracking.lastCheckedCommit == nil)

    _ = try WatchService.check(
      watchID: "multi", path: "skills/a", environment: environment, apply: true)
    _ = try WatchService.done(
      watchID: "multi", path: nil, all: true, environment: environment, apply: true)

    ledger = try WatchLedgerStore.load(environment: environment)
    record = try #require(ledger.watches.first)
    let a = try #require(record.watchedPaths.first { $0.path == "skills/a" })
    let b = try #require(record.watchedPaths.first { $0.path == "skills/b" })
    #expect(a.reviewCoverage.reviewedCommit != nil)
    #expect(b.reviewCoverage.reviewedCommit == nil)

    _ = try WatchService.seen(
      watchID: "multi", path: nil, all: true, commit: "seen-marker", environment: environment,
      apply: true)
    ledger = try WatchLedgerStore.load(environment: environment)
    record = try #require(ledger.watches.first)
    #expect(record.watchedPaths.allSatisfy { $0.lastSeen == "seen-marker" })
  }

  @Test func refreshesRemoteWatchedHeadCheckout() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let remoteRepo = try temporaryDirectory()
    let skillDir = remoteRepo.appendingPathComponent("skills/remote")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: remote
    description: Remote skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try initGitRepo(remoteRepo)
    let baseline = try gitHead(remoteRepo)

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let checkout = project.appendingPathComponent(".agent/cache/sources/remote-source")
    let ledger = WatchLedger(watches: [
      WatchRecord(
        watchID: "remote-source",
        source: SourcePin(
          identity: "remote-source",
          kind: "remoteSourceControl",
          location: remoteRepo.path,
          state: PinState(branch: "master")
        ),
        checkoutPath: checkout.path,
        watchBaseline: baseline,
        currentHead: baseline,
        watchedPaths: [WatchPathState(path: "skills/remote")]
      )
    ])
    try WatchLedgerStore.save(ledger, environment: environment)

    try "changed".write(
      to: skillDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", remoteRepo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", remoteRepo.path, "commit", "-m", "change"])
    let head = try gitHead(remoteRepo)

    _ = try WatchService.refreshWatchedHead(
      watchID: "remote-source", environment: environment, apply: true)
    let refreshed = try WatchLedgerStore.load(environment: environment)
    #expect(refreshed.watches[0].currentHead == head)
    #expect(
      FileManager.default.fileExists(
        atPath: checkout.appendingPathComponent("skills/remote/notes.md").path))
  }

  @Test func mergesWatchPathsAndRequiresExplicitRequirementReplacement() throws {
    let project = try temporaryDirectory()
    let home = try temporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    for name in ["a", "b"] {
      let skillDir = repo.appendingPathComponent("skills/\(name)")
      try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
      try """
      ---
      name: \(name)
      description: \(name)
      ---
      """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
    try initGitRepo(repo)
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = try SourceResolver.resolve(repo.path, environment: environment)

    _ = try WatchService.upsert(
      source: source,
      paths: ["skills/a"],
      requestedID: "repo-watch",
      environment: environment,
      apply: true)
    _ = try WatchService.done(
      watchID: "repo-watch",
      path: "skills/a",
      commit: "reviewed-a",
      environment: environment,
      apply: true)
    _ = try WatchService.upsert(
      source: source,
      paths: ["skills/b"],
      environment: environment,
      apply: true)

    var ledger = try WatchLedgerStore.load(environment: environment)
    var record = try #require(ledger.watches.first)
    #expect(ledger.watches.count == 1)
    #expect(record.watchedPaths.map(\.path).sorted() == ["skills/a", "skills/b"])
    #expect(
      record.watchedPaths.first { $0.path == "skills/a" }?.reviewCoverage.reviewedCommit
        == "reviewed-a")

    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "branch", "other"])
    let branchSource = try SourceResolver.resolve(
      repo.path, environment: environment, requirement: .branch("other"))
    #expect(throws: CoreError.self) {
      _ = try WatchService.upsert(
        source: branchSource,
        paths: ["skills/a"],
        environment: environment,
        apply: true)
    }
    _ = try WatchService.upsert(
      source: branchSource,
      paths: ["skills/a"],
      environment: environment,
      replaceRequirement: true,
      apply: true)
    ledger = try WatchLedgerStore.load(environment: environment)
    record = try #require(ledger.watches.first)
    #expect(record.source.requirement == .branch("other"))
    #expect(record.watchedPaths.allSatisfy { $0.reviewCoverage.reviewedCommit == nil })
    #expect(record.events.contains { $0.type == "source_requirement_replaced" })
  }
}
