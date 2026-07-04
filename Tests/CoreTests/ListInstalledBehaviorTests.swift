import Foundation
import Testing

@testable import Core

@Suite("Installed Skill Listing")
struct InstalledSkillListingTests {
  @Test func listsInstalledSkillsFromFilesystemShapes() throws {
    let project = try listInstalledTemporaryDirectory()
    let home = try listInstalledTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    #expect(
      try RuntimeService.listInstalled(scope: .project, agents: [.codex], environment: environment)
        .isEmpty)

    try writeInstalledSkill(project: project, name: "skill-1")
    try writeInstalledSkill(project: project, name: "skill-2")
    try FileManager.default.createDirectory(
      at: project.appendingPathComponent(".agents/skills/no-skill-md"),
      withIntermediateDirectories: true)
    try writeInstalledSkillFile(
      project.appendingPathComponent(".agents/skills/invalid-skill/SKILL.md"),
      contents: "# Invalid\nNo frontmatter")

    let names = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment
    ).map(\.name).sorted()
    #expect(names == ["skill-1", "skill-2"])
  }

  @Test func ignoresDanglingAndFileSymlinksWhenListingInstalledSkills() throws {
    let project = try listInstalledTemporaryDirectory()
    let home = try listInstalledTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    let skills = project.appendingPathComponent(".agents/skills")
    try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)

    try FileManager.default.createSymbolicLink(
      at: skills.appendingPathComponent("broken"),
      withDestinationURL: project.appendingPathComponent("missing"))
    try "# not a skill".write(
      to: project.appendingPathComponent("not-a-skill.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: skills.appendingPathComponent("file-link"),
      withDestinationURL: project.appendingPathComponent("not-a-skill.md"))

    #expect(
      try RuntimeService.listInstalled(scope: .project, agents: [.codex], environment: environment)
        .isEmpty)
  }

  @Test func listsDirectorySymlinksAndAgentSpecificDirectories() throws {
    let project = try listInstalledTemporaryDirectory()
    let home = try listInstalledTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    let shared = project.appendingPathComponent("shared/linked-skill")
    try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
    try writeInstalledSkillFile(
      shared.appendingPathComponent("SKILL.md"),
      contents: """
        ---
        name: linked-skill
        description: Skill reached through a directory symlink
        ---
        """)
    let universal = project.appendingPathComponent(".agents/skills")
    try FileManager.default.createDirectory(at: universal, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: universal.appendingPathComponent("linked-skill"), withDestinationURL: shared)

    try writeInstalledSkill(
      project: project, name: "claude-only", base: project.appendingPathComponent(".claude/skills"))

    let codex = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment)
    #expect(codex.map(\.name) == ["linked-skill"])

    let claude = try RuntimeService.listInstalled(
      scope: .project, agents: [.claudeCode], environment: environment)
    #expect(claude.map(\.name) == ["claude-only"])
  }

  @Test func listsManagedSkillsFromResolvedStateAndChecksFilesystemPresence() throws {
    let project = try listInstalledTemporaryDirectory()
    let home = try listInstalledTemporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    let skillDir = sourceRoot.appendingPathComponent("skills/managed")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try writeInstalledSkillFile(
      skillDir.appendingPathComponent("SKILL.md"),
      contents: """
        ---
        name: managed
        description: Managed skill
        ---
        """)
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex],
        skillNames: ["managed"],
        environment: environment
      ))

    var managed = try RuntimeService.listManaged(
      scope: .project, agents: [.codex], environment: environment)
    #expect(managed.map(\.name) == ["managed"])
    #expect(managed.first?.sourceIdentity == "source")
    #expect(managed.first?.isInstalled == true)

    try FileManager.default.removeItem(at: project.appendingPathComponent(".agents/skills/managed"))
    managed = try RuntimeService.listManaged(
      scope: .project, agents: [.codex], environment: environment)
    #expect(managed.map(\.name) == ["managed"])
    #expect(managed.first?.isInstalled == false)

    let installed = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment)
    #expect(installed.isEmpty)
  }

  @Test func reportsEditSourceMissingCopyDriftAndInstalledOnlyStatuses() throws {
    let project = try listInstalledTemporaryDirectory()
    let home = try listInstalledTemporaryDirectory()
    let sourceRoot = project.appendingPathComponent("source")
    let skillDir = sourceRoot.appendingPathComponent("skills/editable")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try writeInstalledSkillFile(
      skillDir.appendingPathComponent("SKILL.md"),
      contents: """
        ---
        name: editable
        description: Editable skill
        ---
        """)
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex],
        skillNames: ["editable"],
        mode: .edit,
        environment: environment))
    var managed = try RuntimeService.listManaged(
      scope: .project, agents: [.codex], environment: environment)
    #expect(managed.first?.status == .editLinked)

    try FileManager.default.removeItem(at: sourceRoot)
    managed = try RuntimeService.listManaged(
      scope: .project, agents: [.codex], environment: environment)
    #expect(managed.first?.status == .sourceMissing)

    let copySource = project.appendingPathComponent("copy-source")
    let copySkill = copySource.appendingPathComponent("skills/copied")
    try FileManager.default.createDirectory(at: copySkill, withIntermediateDirectories: true)
    try writeInstalledSkillFile(
      copySkill.appendingPathComponent("SKILL.md"),
      contents: """
        ---
        name: copied
        description: Copied skill
        ---
        """)
    _ = try RuntimeService.add(
      AddOptions(
        source: copySource.path,
        agents: [.codex],
        skillNames: ["copied"],
        mode: .copy,
        environment: environment))
    try "changed".write(
      to: copySkill.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    managed = try RuntimeService.listManaged(
      scope: .project, agents: [.codex], environment: environment)
    #expect(managed.first { $0.name == "copied" }?.status == .copyDrift)

    try writeInstalledSkill(project: project, name: "manual-only")
    let all = try RuntimeService.listInstalled(
      scope: .project, agents: [.codex], environment: environment)
    #expect(all.first { $0.name == "manual-only" }?.status == .installedOnly)

    let report = try RuntimeService.doctor(scope: .project, agents: [.codex], environment: environment)
    #expect(report.ok == false)
    #expect(report.checks.contains { $0.message.contains("source-missing") })
    #expect(report.checks.contains { $0.message.contains("copy-drift") })
    #expect(report.checks.contains { $0.message.contains("installed-only") })
  }

}

private func writeInstalledSkill(
  project: URL, name: String, base: URL? = nil
) throws {
  let root = base ?? project.appendingPathComponent(".agents/skills")
  let skill = root.appendingPathComponent(name)
  try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
  try writeInstalledSkillFile(
    skill.appendingPathComponent("SKILL.md"),
    contents: """
      ---
      name: \(name)
      description: \(name) description
      ---
      """)
}

private func writeInstalledSkillFile(_ file: URL, contents: String) throws {
  try FileManager.default.createDirectory(
    at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
  try contents.write(to: file, atomically: true, encoding: .utf8)
}

private func listInstalledTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-list-installed-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
