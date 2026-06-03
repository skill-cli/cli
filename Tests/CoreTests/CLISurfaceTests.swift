import Foundation
import Testing

@Suite("CLI Surface")
struct CLISurfaceTests {
  @Test func exposesCurrentCommandFamilies() throws {
    let help = try runSkills(["--help"])
    #expect(help.exitCode == 0)
    #expect(help.stdout.contains("add"))
    #expect(help.stdout.contains("install"))
    #expect(help.stdout.contains("status"))
    #expect(help.stdout.contains("review"))
    #expect(!help.stdout.contains("experimental_install"))
    #expect(!help.stdout.contains("experimental_sync"))
    #expect(!help.stdout.contains("sync                    "))
    #expect(!help.stdout.contains("unknown-command"))
  }

  @Test func exposesSupportedAliasesAndRejectsUnknownRoutes() throws {
    let banner = try runSkills([]).stdout
    #expect(banner.contains("skill"))
    #expect(!banner.contains("unknown-command"))
    #expect(try runSkills(["--help"]).stdout.contains("SUBCOMMANDS"))
    #expect(try runSkills(["-h"]).stdout.contains("SUBCOMMANDS"))
    #expect(
      try runSkills(["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0.1.0"
    )

    for alias in ["a"] {
      let result = try runSkills([alias, "--help"])
      #expect(result.exitCode == 0, "add alias \(alias)")
    }
    let installHelp = try runSkills(["install", "--help"]).stdout
    #expect(installHelp.contains("Install skills from resolved state"))
    #expect(installHelp.contains("--scope"))
    #expect(try runSkills(["ls", "--help"]).exitCode == 0)
    #expect(try runSkills(["rm", "--help"]).exitCode == 0)
    #expect(try runSkills(["r", "--help"]).exitCode == 0)
    #expect(try runSkills(["remove", "--help"]).stdout.contains("-s, --skill"))
    #expect(try runSkills(["upgrade", "--help"]).exitCode == 0)
    #expect(try runSkills(["check", "--help"]).exitCode == 0)
    #expect(try runSkills(["i", "--help"]).exitCode != 0)
    #expect(try runSkills(["sync", "--help"]).exitCode != 0)
    #expect(try runSkills(["experimental_sync", "--help"]).exitCode != 0)
    #expect(try runSkills(["experimental_install", "--help"]).exitCode != 0)

    let installWithSource = try runSkills(["install", "owner/repo"])
    #expect(installWithSource.exitCode != 0)
    #expect(installWithSource.stderr.contains("Use 'skill add <source>'"))

    let unsupported = try runSkills(["unknown-command", "--help"])
    #expect(unsupported.exitCode != 0)
    #expect(unsupported.stderr.contains("Unknown command 'unknown-command'"))
    let help = try runSkills(["--help"]).stdout
    #expect(!help.contains("unknown-command"))
  }

  @Test func initializesUpdatesInstallsResolvedAndRemovesProjectSkill() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()

    let initResult = try runSkills(
      ["init"], currentDirectory: project, environment: ["HOME": home.path])
    #expect(initResult.exitCode == 0)
    #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("SKILL.md").path))
    #expect(initResult.stdout.contains("Created:"))
    #expect(initResult.stdout.contains("SKILL.md"))

    let source = try cliTemporaryDirectory()
    let skillDir = source.appendingPathComponent("skills/updatable")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: updatable
    description: Updatable skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let add = try runSkills(
      ["add", source.path, "--mode", "copy"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(add.exitCode == 0)
    #expect(add.stdout.contains("installed updatable"))
    #expect(!add.stdout.contains("Install "))

    try "new".write(
      to: skillDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    let update = try runSkills(
      ["update", "--apply"], currentDirectory: project, environment: ["HOME": home.path])
    #expect(update.exitCode == 0)
    #expect(update.stdout.contains("updated updatable"))

    try FileManager.default.removeItem(at: project.appendingPathComponent(".agents/skills"))
    let install = try runSkills(
      ["install"], currentDirectory: project, environment: ["HOME": home.path])
    #expect(install.exitCode == 0)
    #expect(install.stdout.contains("installed updatable"))

    let remove = try runSkills(
      ["remove", "--all"], currentDirectory: project, environment: ["HOME": home.path])
    #expect(remove.exitCode == 0)
    #expect(remove.stdout.contains("removed"))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/updatable").path))
  }

  @Test func validatesAddDiscoverySelectionAndInternalSkillFlags() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()

    let missingSource = try runSkills(
      ["add"], currentDirectory: project, environment: ["HOME": home.path])
    #expect(missingSource.exitCode != 0)
    #expect(missingSource.stderr.contains("Missing expected argument"))

    let emptySource = try cliTemporaryDirectory()
    let noSkills = try runSkills(
      ["add", emptySource.path, "--all"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(noSkills.exitCode != 0)
    #expect(noSkills.stderr.contains("no skills found"))

    let source = try cliTemporaryDirectory()
    let skillDir = source.appendingPathComponent("skills/internal-skill")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: internal-skill
    description: An internal skill
    metadata:
      internal: true
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let hidden = try runSkills(
      ["list", source.path],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(hidden.exitCode != 0)
    #expect(!hidden.stdout.contains("internal-skill"))

    let shown = try runSkills(
      ["list", source.path],
      currentDirectory: project,
      environment: ["HOME": home.path, "INSTALL_INTERNAL_SKILLS": "true"])
    #expect(shown.exitCode == 0)
    #expect(shown.stdout.contains("internal-skill"))

    let stillHidden = try runSkills(
      ["list", source.path],
      currentDirectory: project,
      environment: ["HOME": home.path, "INSTALL_INTERNAL_SKILLS": "false"])
    #expect(stillHidden.exitCode != 0)
    #expect(!stillHidden.stdout.contains("internal-skill"))

    let invalidAgent = try runSkills(
      ["add", source.path, "--all", "--agent", "invalid-agent"],
      currentDirectory: project,
      environment: ["HOME": home.path, "INSTALL_INTERNAL_SKILLS": "1"])
    #expect(invalidAgent.exitCode != 0)
    #expect(invalidAgent.stderr.contains("unsupported agent"))

    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("skills/public-skill"), withIntermediateDirectories: true)
    try """
    ---
    name: public-skill
    description: Public skill
    metadata:
      internal: false
    ---
    """.write(
      to: source.appendingPathComponent("skills/public-skill/SKILL.md"),
      atomically: true,
      encoding: .utf8)
    let publicList = try runSkills(
      ["list", source.path],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(publicList.exitCode == 0)
    #expect(publicList.stdout.contains("public-skill"))

    let wildcardAgents = try runSkills(
      ["add", source.path, "--skill", "public-skill", "--agent", "*", "--mode", "copy"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(wildcardAgents.exitCode == 0)
    #expect(wildcardAgents.stdout.contains("codex"))
    #expect(wildcardAgents.stdout.contains("claude-code"))
    #expect(wildcardAgents.stdout.contains("cursor"))
    #expect(wildcardAgents.stdout.contains("gemini-cli"))
    #expect(wildcardAgents.stdout.contains("opencode"))

    let deepSource = try cliTemporaryDirectory()
    try writeCLISkill(
      at: deepSource.appendingPathComponent("skills/shallow-skill"), name: "shallow-skill")
    try writeCLISkill(
      at: deepSource.appendingPathComponent("skills/level-1/level-2/deep-skill"),
      name: "deep-skill")
    let noFullDepth = try runSkills(
      ["add", deepSource.path, "--skill", "deep-skill"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(noFullDepth.exitCode != 0)
    #expect(noFullDepth.stderr.contains("no skills found"))

    let fullDepthInstall = try runSkills(
      ["add", deepSource.path, "--full-depth", "--skill", "deep-skill"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(fullDepthInstall.exitCode == 0)
    #expect(fullDepthInstall.stdout.contains("installed deep-skill"))

    let fullDepthList = try runSkills(
      ["list", deepSource.path, "--full-depth"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(fullDepthList.exitCode == 0)
    #expect(fullDepthList.stdout.contains("deep-skill"))
  }

  @Test func listsSourceWatchesPathAndInstallsFromWatchID() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let source = project.appendingPathComponent("demo-watch")
    let skillDir = source.appendingPathComponent("skills/demo")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: demo
    description: Demo skill
    ---
    """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let list = try runSkills(
      ["list", source.path],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(list.exitCode == 0)
    #expect(list.stdout.contains("demo"))

    let watch = try runSkills(
      ["add", source.path, "--watch-only", "--path", "skills/demo"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(watch.exitCode == 0)
    #expect(watch.stdout.contains("watched demo-watch path skills/demo"))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills-state.json").path))

    let install = try runSkills(
      ["add", "demo-watch", "--mode", "copy"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(install.exitCode == 0)
    #expect(install.stdout.contains("installed demo"))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/demo/SKILL.md").path))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills.resolved").path))

    let installed = try runSkills(
      ["list", "--json"],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(installed.exitCode == 0)
    #expect(installed.stdout.contains("\"watchID\" : \"demo-watch\""))
  }

  @Test func managesWatchLifecycleFromTopLevelCommands() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let source = try cliTemporaryDirectory()
    try writeCLISkill(at: source.appendingPathComponent("skills/demo"), name: "demo")
    let env = ["HOME": home.path]

    let watchOnly = try runSkills(
      ["add", source.path, "--watch-only", "--path", "skills/demo"],
      currentDirectory: project,
      environment: env)
    #expect(watchOnly.exitCode == 0)
    #expect(watchOnly.stdout.contains("watched"))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills-state.json").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills.resolved").path))

    let list = try runSkills(["list", "--watch"], currentDirectory: project, environment: env)
    #expect(list.exitCode == 0)
    #expect(list.stdout.contains(source.lastPathComponent.lowercased()))

    let status = try runSkills(
      ["status", source.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.exitCode == 0)
    #expect(status.stdout.contains("path skills/demo"))

    let diff = try runSkills(
      ["diff", source.path, "--watch", "--path", "skills/demo"],
      currentDirectory: project,
      environment: env)
    #expect(diff.exitCode == 0)
    #expect(diff.stdout.contains("watch"))

    let seen = try runSkills(
      [
        "review", "seen", source.path, "--watch", "--path", "skills/demo", "--commit",
        "manual-seen",
      ],
      currentDirectory: project,
      environment: env)
    #expect(seen.exitCode == 0)
    #expect(seen.stdout.contains("marked seen"))

    let install = try runSkills(
      ["add", source.path, "--watch", "--path", "skills/demo", "--mode", "copy"],
      currentDirectory: project,
      environment: env)
    #expect(install.exitCode == 0)
    #expect(install.stdout.contains("installed demo"))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/demo/SKILL.md").path))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agent/skills.resolved").path))

    let update = try runSkills(
      [
        "update", source.path, "--from-watch", "--path", "skills/demo", "--mode", "copy", "--apply",
      ],
      currentDirectory: project,
      environment: env)
    #expect(update.exitCode == 0)
    #expect(update.stdout.contains("updated demo from watch"))

    let removePath = try runSkills(
      ["remove", source.path, "--watch", "--path", "skills/demo"],
      currentDirectory: project,
      environment: env)
    #expect(removePath.exitCode == 0)
    #expect(removePath.stdout.contains("removed path skills/demo"))
  }

  @Test func installsUserScopedGeminiSkillInUniversalHome() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let source = try cliTemporaryDirectory()
    try writeCLISkill(at: source.appendingPathComponent("skills/gemini-demo"), name: "gemini-demo")

    let install = try runSkills(
      [
        "add", source.path, "--agent", "gemini", "--skill", "gemini-demo", "--mode", "copy",
        "--scope", "user",
      ],
      currentDirectory: project,
      environment: ["HOME": home.path])
    #expect(install.exitCode == 0)
    #expect(install.stdout.contains("installed gemini-demo for gemini-cli"))
    #expect(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".agents/skills/gemini-demo/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".gemini/skills/gemini-demo/SKILL.md").path))
  }

  @Test func installsAllSkillsAndExplicitAgentTargets() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let source = try cliTemporaryDirectory()
    let env = isolatedCLIEnvironment(home: home)

    for name in ["lark-base", "lark-doc", "lark-im"] {
      try writeCLISkill(
        at: source.appendingPathComponent("skills/\(name)"),
        name: name,
        description: "\(name) skill")
    }

    let larkStyleInstall = try runSkills(
      ["add", source.path, "--all", "--agent", "*", "--scope", "user"],
      currentDirectory: project,
      environment: env)
    #expect(larkStyleInstall.exitCode == 0)
    #expect(larkStyleInstall.stdout.contains("installed lark-base for codex"))
    #expect(larkStyleInstall.stdout.contains("installed lark-doc for claude-code"))
    #expect(larkStyleInstall.stdout.contains("installed lark-im for cursor"))
    #expect(larkStyleInstall.stdout.contains("installed lark-base for gemini-cli"))
    #expect(larkStyleInstall.stdout.contains("installed lark-doc for opencode"))
    #expect(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".agents/skills/lark-base/SKILL.md").path))
    #expect(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".agents/skills/lark-im/SKILL.md").path))
    #expect(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".agents/skills/lark-doc/SKILL.md").path))
    #expect(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".claude/skills/lark-doc/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".cursor/skills/lark-im/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".gemini/skills/lark-base/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: home.appendingPathComponent(".config/opencode/skills/lark-doc/SKILL.md").path))

    let detectedHome = try cliTemporaryDirectory()
    let detectedEnv = isolatedCLIEnvironment(home: detectedHome)
    try FileManager.default.createDirectory(
      at: detectedHome.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: detectedHome.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
    let meegleSource = try cliTemporaryDirectory()
    try writeCLISkill(
      at: meegleSource.appendingPathComponent("skills/meegle"),
      name: "meegle",
      description: "Meegle skill")

    let detectedInstall = try runSkills(
      [
        "add", meegleSource.path, "--agent", "cursor", "gemini", "--scope", "user", "--mode",
        "copy",
      ],
      currentDirectory: project,
      environment: detectedEnv)
    #expect(detectedInstall.exitCode == 0)
    #expect(detectedInstall.stdout.contains("installed meegle for cursor"))
    #expect(detectedInstall.stdout.contains("installed meegle for gemini-cli"))
    #expect(
      FileManager.default.fileExists(
        atPath: detectedHome.appendingPathComponent(".agents/skills/meegle/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: detectedHome.appendingPathComponent(".cursor/skills/meegle/SKILL.md").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: detectedHome.appendingPathComponent(".gemini/skills/meegle/SKILL.md").path))
  }

  @Test func listsInstalledSkillsByScopeAgentAndJSON() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let env = ["HOME": home.path]

    var result = try runSkills(["list"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("No project skills found"))
    #expect(result.stdout.contains("Try listing user skills with --scope user"))

    result = try runSkills(["ls"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("No project skills found"))

    result = try runSkills(["list", "--json"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    let emptyJSON = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [Any]
    #expect(emptyJSON?.isEmpty == true)

    try writeCLISkill(
      at: project.appendingPathComponent(".agents/skills/json-skill"), name: "json-skill",
      description: "A skill for JSON testing")
    try writeCLISkill(
      at: project.appendingPathComponent(".agents/skills/skill-alpha"), name: "skill-alpha")
    try writeCLISkill(
      at: project.appendingPathComponent(".agents/skills/skill-beta"), name: "skill-beta")
    try FileManager.default.createDirectory(
      at: project.appendingPathComponent(".agents/skills/no-skill-md"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: project.appendingPathComponent(".agents/skills/invalid-skill"),
      withIntermediateDirectories: true)
    try "# Invalid\nNo frontmatter here".write(
      to: project.appendingPathComponent(".agents/skills/invalid-skill/SKILL.md"),
      atomically: true,
      encoding: .utf8)

    result = try runSkills(["list", "--json"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    let stillEmptyJSON = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [Any]
    #expect(stillEmptyJSON?.isEmpty == true)

    result = try runSkills(
      ["list", "--all", "--json"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("\"name\" : \"json-skill\""))
    #expect(result.stdout.contains("\"installed\" : true"))
    #expect(result.stdout.contains("\"path\" : "))
    #expect(result.stdout.contains("\"scope\" : \"project\""))
    #expect(result.stdout.contains("\"agents\" : ["))
    #expect(!result.stdout.contains("\u{001B}["))
    #expect(result.stdout.contains("skill-alpha"))
    #expect(result.stdout.contains("skill-beta"))

    result = try runSkills(
      ["list", "--all", "--skill", "skill-alpha", "--json"],
      currentDirectory: project,
      environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("\"name\" : \"skill-alpha\""))
    #expect(!result.stdout.contains("\"name\" : \"skill-beta\""))

    result = try runSkills(["list", "--all"], currentDirectory: project, environment: env)
    #expect(result.stdout.contains("Project Skills"))
    #expect(result.stdout.contains("json-skill"))
    #expect(result.stdout.contains("installed"))
    #expect(result.stdout.contains(".agents/skills/json-skill"))
    #expect(!result.stdout.contains("A skill for JSON testing"))
    #expect(!result.stdout.contains("no-skill-md"))
    #expect(!result.stdout.contains("invalid-skill"))

    result = try runSkills(
      ["list", "--scope", "user"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(!result.stdout.contains("json-skill"))

    result = try runSkills(
      ["list", "-a", "invalid-agent"], currentDirectory: project, environment: env)
    #expect(result.exitCode != 0)
    #expect(result.stderr.contains("unsupported agent"))

    try writeCLISkill(
      at: project.appendingPathComponent(".claude/skills/claude-only"), name: "claude-only")
    result = try runSkills(
      ["list", "--all", "-a", "claude-code"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("claude-only"))

    try writeCLISkill(
      at: project.appendingPathComponent(".gemini/skills/gemini-only"), name: "gemini-only")
    result = try runSkills(
      ["list", "--all", "-a", "gemini"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("gemini-only"))

    let rootHelp = try runSkills(["--help"]).stdout
    #expect(rootHelp.contains("list, ls"))
    #expect(rootHelp.contains("List Options:"))
    #expect(rootHelp.contains("skill list"))
    #expect(rootHelp.contains("skill list --scope user"))
    #expect(rootHelp.contains("--all"))
    #expect(rootHelp.contains("skill list --agent claude-code"))
  }

  @Test func filtersInstalledListBySkillName() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let source = try cliTemporaryDirectory()
    let env = ["HOME": home.path]

    try writeCLISkill(at: source.appendingPathComponent("skills/skill-alpha"), name: "skill-alpha")
    try writeCLISkill(at: source.appendingPathComponent("skills/skill-beta"), name: "skill-beta")

    let add = try runSkills(
      ["add", source.path, "--all", "--mode", "copy"],
      currentDirectory: project,
      environment: env)
    #expect(add.exitCode == 0)

    var result = try runSkills(
      ["list", "--skill", "skill-alpha", "--json"],
      currentDirectory: project,
      environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("\"name\" : \"skill-alpha\""))
    #expect(!result.stdout.contains("\"name\" : \"skill-beta\""))

    result = try runSkills(
      ["list", "--all", "--skill", "skill-beta", "--json"],
      currentDirectory: project,
      environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("\"name\" : \"skill-beta\""))
    #expect(!result.stdout.contains("\"name\" : \"skill-alpha\""))

    result = try runSkills(
      ["list", "--skill", "missing-skill"],
      currentDirectory: project,
      environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("No matching skills found"))
  }

  @Test func removesInstalledSkillsByNameAgentAndScope() throws {
    let project = try cliTemporaryDirectory()
    let home = try cliTemporaryDirectory()
    let env = ["HOME": home.path]

    var result = try runSkills(["remove"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("No skills found"))
    #expect(result.stdout.contains("to remove"))

    result = try runSkills(
      ["remove", "non-existent-skill"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("No skills found"))

    for name in ["skill-one", "skill-two", "skill-three"] {
      try writeCLISkill(at: project.appendingPathComponent(".agents/skills/\(name)"), name: name)
    }

    result = try runSkills(
      ["remove", "non-existent"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("No matching skills"))

    result = try runSkills(
      ["remove", "SKILL-ONE"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("removed"))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/skill-one").path))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/skill-two").path))

    result = try runSkills(
      ["remove", "skill-two", "skill-three"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("removed"))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/skill-two").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/skill-three").path))

    try writeCLISkill(
      at: project.appendingPathComponent(".agents/skills/skill-with-dashes"),
      name: "skill-with-dashes")
    try writeCLISkill(
      at: project.appendingPathComponent(".agents/skills/skill_with_underscores"),
      name: "skill_with_underscores")
    result = try runSkills(
      ["rm", "skill-with-dashes"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/skill-with-dashes").path))
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/skill_with_underscores").path))

    result = try runSkills(["r", "--all"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("removed"))

    try FileManager.default.createDirectory(
      at: project.appendingPathComponent(".agents/skills/invalid-skill"),
      withIntermediateDirectories: true)
    try "readme".write(
      to: project.appendingPathComponent(".agents/skills/invalid-skill/README.md"),
      atomically: true,
      encoding: .utf8)
    try writeCLISkill(
      at: project.appendingPathComponent(".agents/skills/valid-skill"), name: "valid-skill")
    result = try runSkills(
      ["remove", "valid-skill", "--scope", "user"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    result = try runSkills(
      ["remove", "valid-skill", "--agent", "invalid-agent"],
      currentDirectory: project,
      environment: env)
    #expect(result.exitCode != 0)
    #expect(result.stderr.contains("unsupported agent"))
    result = try runSkills(
      ["remove", "valid-skill", "-a", "codex"], currentDirectory: project, environment: env)
    #expect(result.exitCode == 0)
    #expect(
      FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".agents/skills/invalid-skill").path))

    try writeCLISkill(
      at: project.appendingPathComponent(".gemini/skills/gemini-only"), name: "gemini-only")
    result = try runSkills(
      ["remove", "gemini-only", "-a", "gemini"],
      currentDirectory: project,
      environment: env)
    #expect(result.exitCode == 0)
    #expect(
      !FileManager.default.fileExists(
        atPath: project.appendingPathComponent(".gemini/skills/gemini-only").path))

    #expect(try runSkills(["remove", "--help"]).stdout.contains("--scope"))
    #expect(try runSkills(["remove", "-h"]).exitCode == 0)
  }

}

struct CLIResult {
  var stdout: String
  var stderr: String
  var exitCode: Int32
}

func runSkills(
  _ arguments: [String],
  currentDirectory: URL? = nil,
  environment: [String: String] = [:]
) throws -> CLIResult {
  let process = Process()
  process.executableURL = skillsExecutableURL()
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory
  var env = ProcessInfo.processInfo.environment
  for (key, value) in environment {
    env[key] = value
  }
  process.environment = env

  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()

  return CLIResult(
    stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    exitCode: process.terminationStatus
  )
}

func skillsExecutableURL() -> URL {
  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return packageRoot.appendingPathComponent(".build/debug/skill")
}

func cliTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-cli-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func isolatedCLIEnvironment(home: URL) -> [String: String] {
  [
    "HOME": home.path,
    "CODEX_HOME": "",
    "CLAUDE_CONFIG_DIR": "",
    "XDG_CONFIG_HOME": home.appendingPathComponent(".config").path,
  ]
}

private func writeCLISkill(
  at directory: URL, name: String, description: String = "Test skill"
) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try """
  ---
  name: \(name)
  description: \(description)
  ---
  """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
}
