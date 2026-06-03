import Foundation
import Testing

@testable import Core

@Suite("Install Lock")
struct InstallLockTests {
  @Test func savesLocksDeterministicallyWithTrailingNewline() throws {
    let project = try lockTemporaryDirectory()
    let home = try lockTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let lock = LockFile(pins: [
      SourcePin(
        identity: "z-source",
        kind: "localFileSystem",
        location: "/tmp/z",
        state: PinState(),
        skills: [
          PinnedSkill(
            identity: "z-skill",
            name: "Z Skill",
            path: "skills/z/SKILL.md",
            contentHash: "z",
            installations: [
              InstallationPin(
                scope: .project, agent: .cursor, mode: .copy, path: ".agents/skills/z"),
              InstallationPin(
                scope: .project, agent: .codex, mode: .copy, path: ".agents/skills/z"),
            ]),
          PinnedSkill(
            identity: "a-skill",
            name: "A Skill",
            path: "skills/a/SKILL.md",
            contentHash: "a",
            installations: [
              InstallationPin(scope: .project, agent: .codex, mode: .copy, path: ".agents/skills/a")
            ]),
        ]),
      SourcePin(
        identity: "a-source",
        kind: "localFileSystem",
        location: "/tmp/a",
        state: PinState(),
        skills: []),
    ])

    try InstallLockStore.save(lock, scope: .project, environment: environment)
    let first = try String(
      contentsOf: InstallLockStore.projectLockURL(environment: environment), encoding: .utf8)
    try InstallLockStore.save(lock, scope: .project, environment: environment)
    let second = try String(
      contentsOf: InstallLockStore.projectLockURL(environment: environment), encoding: .utf8)

    #expect(first == second)
    #expect(first.hasSuffix("\n"))
    #expect(
      first.range(of: "\"identity\" : \"a-source\"")!.lowerBound
        < first.range(of: "\"identity\" : \"z-source\"")!.lowerBound)
    #expect(
      first.range(of: "\"identity\" : \"a-skill\"")!.lowerBound
        < first.range(of: "\"identity\" : \"z-skill\"")!.lowerBound)
    #expect(
      first.range(of: "\"agent\" : \"codex\"")!.lowerBound
        < first.range(of: "\"agent\" : \"cursor\"")!.lowerBound)
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills.resolved").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills-lock.json").path))
  }

  @Test func loadsLegacyProjectLockButSavesProjectResolvedFile() throws {
    let project = try lockTemporaryDirectory()
    let home = try lockTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let agentDirectory = project.appendingPathComponent(".agent")
    try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
    try """
    {
      "version": 1,
      "pins": [
        {
          "identity": "source",
          "kind": "localFileSystem",
          "location": "/tmp/source",
          "state": {},
          "skills": [
            {
              "identity": "demo",
              "name": "Demo",
              "path": "skills/demo/SKILL.md",
              "contentHash": "abc123",
              "installations": [
                {
                  "scope": "project",
                  "agent": "codex",
                  "mode": "copy",
                  "path": ".agents/skills/demo"
                }
              ]
            }
          ]
        }
      ]
    }
    """.write(
      to: project.appendingPathComponent(".agent/skills-lock.json"),
      atomically: true,
      encoding: .utf8)

    var lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock.pins.flatMap(\.skills).map(\.identity) == ["demo"])

    lock.pins[0].skills[0].contentHash = "def456"
    try InstallLockStore.save(lock, scope: .project, environment: environment)
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills.resolved").path))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills-lock.json").path))

    let saved = try String(
      contentsOf: project.appendingPathComponent(".agent/skills.resolved"), encoding: .utf8)
    #expect(saved.contains("\"contentHash\" : \"def456\""))
  }

  @Test func loadsLegacyGlobalLocksButSavesGlobalResolvedFile() throws {
    let project = try lockTemporaryDirectory()
    let home = try lockTemporaryDirectory()
    let xdgState = try lockTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: ["XDG_STATE_HOME": xdgState.path])
    let legacyDirectory = xdgState.appendingPathComponent("skills")
    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    try """
    {
      "version": 1,
      "skills": {
        "legacy-skill": {
          "source": "owner/repo",
          "ref": "main",
          "sourceType": "github",
          "skillPath": "skills/legacy-skill/SKILL.md",
          "computedHash": "abc123"
        }
      }
    }
    """.write(
      to: legacyDirectory.appendingPathComponent(".skill-lock.json"),
      atomically: true,
      encoding: .utf8)

    let lock = try InstallLockStore.load(scope: .global, environment: environment)
    #expect(lock.pins.flatMap(\.skills).map(\.identity) == ["legacy-skill"])

    try InstallLockStore.save(lock, scope: .global, environment: environment)
    #expect(
      FileManager.default.fileExists(
        atPath: xdgState.appendingPathComponent("skills/skills.resolved").path))
  }

  @Test func hashesFoldersDeterministicallyIgnoringMetadata() throws {
    let root = try lockTemporaryDirectory()
    try "one".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try "two".write(
      to: root.appendingPathComponent("nested/b.txt"), atomically: true, encoding: .utf8)

    let first = try FileHash.folderHash(root)
    let second = try FileHash.folderHash(root)
    #expect(first == second)

    try "ignored".write(
      to: root.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "ignored".write(
      to: root.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
    #expect(try FileHash.folderHash(root) == first)

    try "changed".write(
      to: root.appendingPathComponent("nested/b.txt"), atomically: true, encoding: .utf8)
    #expect(try FileHash.folderHash(root) != first)
  }

  @Test func mergesUpdatesRemovesAndHashesLocalLockEntries() throws {
    let project = try lockTemporaryDirectory()
    let home = try lockTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let source = SourcePin(
      identity: "owner/repo",
      kind: "remoteSourceControl",
      location: "owner/repo",
      state: PinState(ref: "main"))
    let first = PinnedSkill(
      identity: "alpha",
      name: "Alpha",
      path: "skills/alpha/SKILL.md",
      contentHash: "hash-a",
      installations: [
        InstallationPin(scope: .project, agent: .codex, mode: .copy, path: ".agents/skills/alpha")
      ])
    let second = PinnedSkill(
      identity: "beta",
      name: "Beta",
      path: "skills/beta/SKILL.md",
      contentHash: "hash-b",
      installations: [
        InstallationPin(scope: .project, agent: .codex, mode: .copy, path: ".agents/skills/beta")
      ])

    try InstallLockStore.merge(
      pinnedSkill: first, into: source, scope: .project, environment: environment)
    var lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock.pins.flatMap(\.skills).map(\.identity) == ["alpha"])
    #expect(lock.pins[0].state.ref == "main")

    var updatedFirst = first
    updatedFirst.contentHash = "hash-a2"
    try InstallLockStore.merge(
      pinnedSkill: updatedFirst, into: source, scope: .project, environment: environment)
    try InstallLockStore.merge(
      pinnedSkill: second, into: source, scope: .project, environment: environment)
    lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock.pins.flatMap(\.skills).map(\.identity).sorted() == ["alpha", "beta"])
    #expect(lock.pins.flatMap(\.skills).first { $0.identity == "alpha" }?.contentHash == "hash-a2")

    try InstallLockStore.remove(
      skillNames: ["alpha"], agents: [.codex], scope: .project, environment: environment)
    lock = try InstallLockStore.load(scope: .project, environment: environment)
    #expect(lock.pins.flatMap(\.skills).map(\.identity) == ["beta"])

    let before = lock
    try InstallLockStore.remove(
      skillNames: ["missing"], agents: [.codex], scope: .project, environment: environment)
    #expect(try InstallLockStore.load(scope: .project, environment: environment) == before)
  }

}

private func lockTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-lock-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
