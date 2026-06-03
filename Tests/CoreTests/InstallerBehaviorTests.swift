import Foundation
import Testing

@testable import Core

@Suite("Installer")
struct InstallerTests {
  @Test func resolvesAgentDirectoriesAndLockLocations() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let codexHome = try behaviorTemporaryDirectory()
    let claudeHome = try behaviorTemporaryDirectory()
    let xdgConfig = try behaviorTemporaryDirectory()
    let xdgCache = try behaviorTemporaryDirectory()
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: [
        "CODEX_HOME": codexHome.path,
        "CLAUDE_CONFIG_DIR": claudeHome.path,
        "XDG_CONFIG_HOME": xdgConfig.path,
        "XDG_CACHE_HOME": xdgCache.path,
      ])

    #expect(
      InstallLockStore.projectLockURL(environment: environment).standardizedFileURL.path
        == project.appendingPathComponent(".agent/skills.resolved").standardizedFileURL.path)
    #expect(
      InstallLockStore.globalLockURL(environment: environment).standardizedFileURL.path
        == home.appendingPathComponent(".agents/skills.resolved").standardizedFileURL.path)
    #expect(
      AgentRegistry.skillsDirectory(for: .codex, scope: .global, environment: environment).path
        == codexHome.appendingPathComponent("skills").path)
    #expect(
      AgentRegistry.skillsDirectory(for: .claudeCode, scope: .global, environment: environment).path
        == claudeHome.appendingPathComponent("skills").path)
    #expect(
      AgentRegistry.skillsDirectory(for: .cursor, scope: .global, environment: environment).path
        == home.appendingPathComponent(".cursor/skills").path)
    #expect(
      AgentRegistry.skillsDirectory(for: .geminiCLI, scope: .project, environment: environment).path
        == project.appendingPathComponent(".agents/skills").path)
    #expect(
      AgentRegistry.skillsDirectory(for: .geminiCLI, scope: .global, environment: environment).path
        == home.appendingPathComponent(".gemini/skills").path)
    #expect(try AgentID.parse("gemini") == .geminiCLI)
    #expect(try AgentID.parse("gemini-cli") == .geminiCLI)
    #expect(
      AgentRegistry.skillsDirectory(for: .opencode, scope: .global, environment: environment).path
        == xdgConfig.appendingPathComponent("opencode/skills").path)
    #expect(
      AgentRegistry.sourceCacheDirectory(scope: .project, environment: environment).path
        == project.appendingPathComponent(".agent/cache/sources").path)
    #expect(
      AgentRegistry.sourceCacheDirectory(scope: .global, environment: environment).path
        == xdgCache.appendingPathComponent("skill-cli/sources").path)
    #expect(
      AgentRegistry.canonicalSkillsDirectory(scope: .global, environment: environment).path
        == home.appendingPathComponent(".agents/skills").path)
    #expect(
      AgentRegistry.usesCanonicalSkillsDirectory(
        for: .codex, scope: .global, environment: environment))
    #expect(
      AgentRegistry.usesCanonicalSkillsDirectory(
        for: .cursor, scope: .global, environment: environment))
    #expect(
      AgentRegistry.usesCanonicalSkillsDirectory(
        for: .geminiCLI, scope: .global, environment: environment))
    #expect(
      AgentRegistry.usesCanonicalSkillsDirectory(
        for: .opencode, scope: .global, environment: environment))
    #expect(
      !AgentRegistry.usesCanonicalSkillsDirectory(
        for: .claudeCode, scope: .global, environment: environment))
  }

  @Test func installsProjectSkillsAsRealDirectories() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    let skillDir = try writeBehaviorSkill(
      root: sourceRoot, path: "skills/self-loop", name: "self-loop")
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex],
        skillNames: ["self-loop"],
        environment: environment))

    let installed = project.appendingPathComponent(".agents/skills/self-loop")
    let values = try installed.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    #expect(values.isDirectory == true)
    #expect(values.isSymbolicLink != true)
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("SKILL.md").path))

    _ = skillDir
  }

  @Test func removesPreexistingSelfLoopBeforeInstall() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: sourceRoot, path: "skills/self-loop", name: "self-loop")
    let canonicalBase = project.appendingPathComponent(".agents/skills")
    let canonical = canonicalBase.appendingPathComponent("self-loop")
    try FileManager.default.createDirectory(at: canonicalBase, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: canonical.path, withDestinationPath: "self-loop")

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex],
        skillNames: ["self-loop"],
        environment: environment))

    let values = try canonical.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    #expect(values.isDirectory == true)
    #expect(values.isSymbolicLink != true)
  }

  @Test func avoidsSelfLoopWhenClaudeDirectoryIsSymlinked() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: sourceRoot, path: "skills/claude", name: "claude")
    let canonicalBase = project.appendingPathComponent(".agents/skills")
    let claudeBase = project.appendingPathComponent(".claude/skills")
    try FileManager.default.createDirectory(at: canonicalBase, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: claudeBase.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: claudeBase.path,
      withDestinationPath: PathSafety.relativePath(
        canonicalBase.path, to: claudeBase.deletingLastPathComponent().path))

    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])
    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.claudeCode],
        skillNames: ["claude"],
        environment: environment))

    let canonical = canonicalBase.appendingPathComponent("claude")
    let values = try canonical.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    #expect(values.isDirectory == true)
    #expect(values.isSymbolicLink != true)
    #expect(
      FileManager.default.fileExists(
        atPath: claudeBase.appendingPathComponent("claude/SKILL.md").path))
  }

  @Test func preservesCanonicalSharedStorageWhileOtherAgentsReferenceIt() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: sourceRoot, path: "skills/shared", name: "shared")
    let environment = RuntimeEnvironment(
      projectDirectory: project, homeDirectory: home, environment: [:])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex, .cursor, .claudeCode],
        skillNames: ["shared"],
        environment: environment))

    let canonical = project.appendingPathComponent(".agents/skills/shared")
    let claude = project.appendingPathComponent(".claude/skills/shared")
    _ = try RuntimeService.remove(
      skillNames: ["shared"], scope: .project, agents: [.claudeCode], environment: environment)
    #expect(!FileManager.default.fileExists(atPath: claude.path))
    #expect(
      FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))

    _ = try RuntimeService.remove(
      skillNames: ["shared"], scope: .project, agents: [.codex, .cursor], environment: environment)
    #expect(!FileManager.default.fileExists(atPath: canonical.path))
  }

  @Test func installsUserScopedUniversalAgentsInCanonicalDirectory() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let codexHome = try behaviorTemporaryDirectory()
    let xdgConfig = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: sourceRoot, path: "skills/native", name: "native")
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: ["CODEX_HOME": codexHome.path, "XDG_CONFIG_HOME": xdgConfig.path])
    let staleCanonical = try writeBehaviorSkill(
      root: home, path: ".agents/skills/native", name: "native")
    let cursorBase = home.appendingPathComponent(".cursor/skills")
    try FileManager.default.createDirectory(at: cursorBase, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: cursorBase.appendingPathComponent("native").path,
      withDestinationPath: PathSafety.relativePath(staleCanonical.path, to: cursorBase.path))
    try writeBehaviorSkill(root: home, path: ".gemini/skills/native", name: "native")
    try writeBehaviorSkill(root: xdgConfig, path: "opencode/skills/native", name: "native")

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex, .cursor, .geminiCLI, .opencode],
        skillNames: ["native"],
        scope: .global,
        mode: .copy,
        environment: environment))

    #expect(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".agents/skills/native/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".cursor/skills/native/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".gemini/skills/native/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: xdgConfig.appendingPathComponent("opencode/skills/native/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: codexHome.appendingPathComponent("skills/native/SKILL.md").path))
  }

  @Test func userScopedGitInstallsUseUserCache() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let codexHome = try behaviorTemporaryDirectory()
    let xdgCache = try behaviorTemporaryDirectory()
    let repo = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: repo, path: "skills/remote", name: "remote")
    try initGitRepo(repo)
    let revision = try gitHead(repo)
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: [
        "CODEX_HOME": codexHome.path,
        "XDG_CACHE_HOME": xdgCache.path,
      ])
    let staleNative = codexHome.appendingPathComponent("skills/remote")
    try writeBehaviorSkill(root: codexHome, path: "skills/remote", name: "remote")

    _ = try RuntimeService.add(
      AddOptions(
        source: "\(repo.path)@revision:\(revision)",
        agents: [.codex],
        skillNames: ["remote"],
        scope: .global,
        mode: .symlink,
        environment: environment))

    let userCache = xdgCache.appendingPathComponent("skill-cli/sources").standardizedFileURL
    let projectCache = project.appendingPathComponent(".agent/cache/sources")
    let installed = home.appendingPathComponent(".agents/skills/remote")
    let values = try installed.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    #expect(values.isDirectory == true)
    #expect(values.isSymbolicLink != true)
    #expect(FileManager.default.fileExists(atPath: userCache.path))
    #expect(!FileManager.default.fileExists(atPath: projectCache.path))
    #expect(
      !FileManager.default.fileExists(
        atPath: staleNative.path))
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("SKILL.md").path))

    try FileManager.default.removeItem(at: installed)
    let restored = try RuntimeService.installResolved(scope: .global, environment: environment)
    #expect(restored.map(\.skill) == ["remote"])
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("SKILL.md").path))
  }

  @Test func userScopedNativeOnlyAgentsLinkToCanonicalInstall() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let claudeHome = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: sourceRoot, path: "skills/claude", name: "claude")
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: ["CLAUDE_CONFIG_DIR": claudeHome.path])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.claudeCode],
        skillNames: ["claude"],
        scope: .global,
        mode: .symlink,
        environment: environment))

    let canonical = home.appendingPathComponent(".agents/skills/claude")
    let installed = claudeHome.appendingPathComponent("skills/claude")
    let values = try installed.resourceValues(forKeys: [.isSymbolicLinkKey])
    #expect(values.isSymbolicLink == true)
    #expect(
      FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))
    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installed.path)
    let target = URL(
      fileURLWithPath: destination,
      relativeTo: installed.deletingLastPathComponent()
    ).standardizedFileURL
    #expect(target.path == canonical.standardizedFileURL.path)
  }

  @Test func installResolvedKeepsNativeOnlyProjectionForSharedUserSkill() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(root: sourceRoot, path: "skills/shared-user", name: "shared-user")
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: [:])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.claudeCode, .codex, .cursor],
        skillNames: ["shared-user"],
        scope: .global,
        mode: .symlink,
        environment: environment))
    _ = try RuntimeService.installResolved(scope: .global, environment: environment)

    let canonical = home.appendingPathComponent(".agents/skills/shared-user")
    let claude = home.appendingPathComponent(".claude/skills/shared-user")
    #expect(
      FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))
    #expect(
      FileManager.default.fileExists(atPath: claude.appendingPathComponent("SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".cursor/skills/shared-user").path))
  }

  @Test func removesUserCanonicalInstallAfterLastReference() throws {
    let project = try behaviorTemporaryDirectory()
    let home = try behaviorTemporaryDirectory()
    let claudeHome = try behaviorTemporaryDirectory()
    let sourceRoot = try behaviorTemporaryDirectory()
    _ = try writeBehaviorSkill(
      root: sourceRoot, path: "skills/shared-global", name: "shared-global")
    let environment = RuntimeEnvironment(
      projectDirectory: project,
      homeDirectory: home,
      environment: ["CLAUDE_CONFIG_DIR": claudeHome.path])

    _ = try RuntimeService.add(
      AddOptions(
        source: sourceRoot.path,
        agents: [.codex, .claudeCode],
        skillNames: ["shared-global"],
        scope: .global,
        mode: .symlink,
        environment: environment))

    let canonical = home.appendingPathComponent(".agents/skills/shared-global")
    let claude = claudeHome.appendingPathComponent("skills/shared-global")
    _ = try RuntimeService.remove(
      skillNames: ["shared-global"], scope: .global, agents: [.codex], environment: environment)
    #expect(
      FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))
    #expect(FileManager.default.fileExists(atPath: claude.path))

    _ = try RuntimeService.remove(
      skillNames: ["shared-global"], scope: .global, agents: [.claudeCode], environment: environment
    )
    #expect(!FileManager.default.fileExists(atPath: claude.path))
    #expect(!FileManager.default.fileExists(atPath: canonical.path))
  }

}

private func behaviorTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-behavior-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@discardableResult
private func writeBehaviorSkill(root: URL, path: String, name: String) throws -> URL {
  let skillDir = root.appendingPathComponent(path)
  try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
  try """
  ---
  name: \(name)
  description: \(name) skill
  ---
  """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  return skillDir
}
