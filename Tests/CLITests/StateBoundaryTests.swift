import AgentsCore
import Foundation
import Testing

struct StateBoundaryTests {
  @Test(arguments: [InstallScope.project, .user])
  func lifecyclePreservesInstructions(_ scope: InstallScope) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    let scopeArguments = ["--scope", scope.rawValue]
    try fixture.success(["add", fixture.source.path, "demo", "--mode", "copy"] + scopeArguments)
    let store = StateStore(
      scope: scope,
      environment: RuntimeEnvironment(
        projectDirectory: fixture.project, homeDirectory: fixture.home,
        environment: fixture.environment))
    var declaration = try store.loadDeclaration()
    let alias = try #require(declaration.sources.keys.first)
    declaration.instructions = InstructionsDeclaration(
      agents: [.codex], sections: ["\(alias):rules"],
      chatgpt: ["daily": PromptDeclaration(sections: ["\(alias):rules"], append: "custom.md")])
    var resolved = try store.loadResolved()
    let pin = try #require(resolved.skills["demo"])
    let section = LockedSection(
      name: "rules", source: pin.source, revision: pin.revision,
      path: "instructions/rules.md", hash: try #require(pin.hash))
    let targetRoot = scope == .user ? fixture.home : fixture.project
    let targetKey = scope == .user ? "~/.codex/AGENTS.md" : "AGENTS.md"
    resolved.instructions = LockedInstructions(
      sections: [section],
      chatgpt: ["daily": LockedPrompt(sections: [section], append: "custom.md")],
      targets: [
        targetKey: LockedTarget(
          agents: [.codex], headingOffset: 0, blockHash: section.hash, created: false)
      ])
    try store.save(declaration: declaration, resolved: resolved)
    let targetPaths =
      scope == .user
      ? [".codex/AGENTS.md", ".claude/CLAUDE.md", ".gemini/GEMINI.md", "custom.md"]
      : ["AGENTS.md", "CLAUDE.md", "GEMINI.md", "custom.md"]
    let targetBytes = Data("Owner instructions\r\n<!-- untouched -->\r\n".utf8)
    for path in targetPaths {
      let url = targetRoot.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try targetBytes.write(to: url)
    }
    let installed = targetRoot.appendingPathComponent(".agents/skills/demo/SKILL.md")
    try FileManager.default.removeItem(at: installed)
    try fixture.skill(body: "New committed skill")
    try fixture.commit()
    for command in [
      ["list", "--json"], ["install"], ["update", "--json"], ["update", "--apply"],
      ["add", fixture.source.path, "demo"], ["doctor", "--json"], ["remove", "demo"],
    ] {
      try fixture.success(command + scopeArguments)
      #expect(try store.loadDeclaration().instructions == declaration.instructions)
      #expect(try store.loadResolved().instructions == resolved.instructions)
      #expect(try store.loadResolved().sources[pin.source] == resolved.sources[pin.source])
      for path in targetPaths {
        #expect(try Data(contentsOf: targetRoot.appendingPathComponent(path)) == targetBytes)
      }
    }
    if scope == .project {
      try fixture.success(["doctor", "--root", fixture.project.path, "--json"])
      #expect(try store.loadResolved().instructions == resolved.instructions)
      for path in targetPaths {
        #expect(try Data(contentsOf: targetRoot.appendingPathComponent(path)) == targetBytes)
      }
    }
  }

  @Test(arguments: ["project", "user"])
  func stateUsesAgentsFiles(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    let legacy = ["skills.resolved", "skills-state.json"]
    let bytes = Data("unreadable legacy state\n".utf8)
    for name in legacy {
      let url = fixture.state(name, scope: scope)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: url)
    }
    try fixture.success(["add", fixture.source.path, "--scope", scope])
    try fixture.success(["install", "--scope", scope])
    for name in ["agents.json", "agents.resolved"] {
      #expect(FileManager.default.fileExists(atPath: fixture.state(name, scope: scope).path))
    }
    for name in legacy {
      #expect(try Data(contentsOf: fixture.state(name, scope: scope)) == bytes)
    }
  }
}
