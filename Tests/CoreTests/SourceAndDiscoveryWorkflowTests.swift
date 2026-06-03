import Foundation
import Testing

@testable import Core

extension SourceParserTests {
  @Test func parsesHostedRepositoryURLsAndCompatibilitySelectors() throws {
    let github = try SourceParser.parse("https://github.com/owner/repo/tree/main/skills/my-skill")
    #expect(github.type == .github)
    #expect(github.url == "https://github.com/owner/repo.git")
    #expect(github.ref == "main")
    #expect(github.subpath == "skills/my-skill")

    let gitlab = try SourceParser.parse(
      "https://gitlab.com/group/subgroup/repo/-/tree/develop/path/to/skill")
    #expect(gitlab.type == .gitlab)
    #expect(gitlab.url == "https://gitlab.com/group/subgroup/repo.git")
    #expect(gitlab.ref == "develop")
    #expect(gitlab.subpath == "path/to/skill")

    let shorthand = try SourceParser.parse("owner/repo#branch@my-skill")
    #expect(shorthand.type == .github)
    #expect(shorthand.ref == "branch")
    #expect(shorthand.skillFilter == "my-skill")

    let blob = try SourceParser.parse("https://github.com/owner/repo/blob/main/README.md#L10")
    #expect(blob.ref == nil)

    let huggingFace = try SourceParser.parse("https://huggingface.co/spaces/owner/repo")
    #expect(huggingFace.type == .git)
  }
}

extension SourceResolutionTests {
  @Test func branchRequirementsCheckoutFetchedRemoteBranchHead() throws {
    let root = try temporaryDirectory()
    let source = root.appendingPathComponent("source")
    let skill = source.appendingPathComponent("skills/demo")
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try """
    ---
    name: demo
    description: initial branch head
    ---
    """.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try initGitRepo(source)
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", source.path, "branch", "-M", "master"])

    let bare = root.appendingPathComponent("remote.git")
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "clone", "--bare", source.path, bare.path])

    let environment = RuntimeEnvironment(
      projectDirectory: root.appendingPathComponent("project"),
      homeDirectory: root.appendingPathComponent("home"),
      environment: [:])
    try FileManager.default.createDirectory(
      at: environment.projectDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: environment.homeDirectory, withIntermediateDirectories: true)
    let remote = URL(fileURLWithPath: bare.path).absoluteString

    let first = try SourceResolver.resolve(
      remote, environment: environment, requirement: .branch("master"))
    let initialRevision = try #require(first.revision)

    try """
    ---
    name: demo
    description: updated branch head
    ---
    """.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", source.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", source.path, "commit", "-m", "update"])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", source.path, "push", bare.path, "master"])

    let second = try SourceResolver.resolve(
      remote, environment: environment, requirement: .branch("master"))
    #expect(second.revision != initialRevision)
    let text = try String(
      contentsOf: second.checkoutURL.appendingPathComponent("skills/demo/SKILL.md"),
      encoding: .utf8)
    #expect(text.contains("updated branch head"))
  }
}

extension PathSafetyAndSanitizationTests {
  @Test func rejectsTraversalInSourceSelectorsAndSubpaths() throws {
    #expect(throws: CoreError.self) {
      _ = try SourceParser.parse("owner/repo/../outside")
    }
    #expect(throws: CoreError.self) {
      _ = try PathSafety.sanitizeSubpath("/absolute")
    }
  }
}

extension SkillDiscoveryTests {
  @Test func discoversSkillsFromFrontmatterAndPluginManifest() throws {
    let root = try temporaryDirectory()
    let skill = root.appendingPathComponent("plugin/skills/write")
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try """
    ---
    name: Write Docs\u{001B}[31m
    description: Documentation helper
    ---

    Body
    """.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
    try """
    {
      "metadata": { "pluginRoot": "./plugin" },
      "plugins": [
        { "name": "docs", "source": "./", "skills": ["./skills/write"] }
      ]
    }
    """.write(
      to: root.appendingPathComponent(".claude-plugin/marketplace.json"), atomically: true,
      encoding: .utf8)

    let skills = try Discovery.discover(in: root)
    #expect(skills.count == 1)
    #expect(skills[0].name == "Write Docs")
    #expect(skills[0].pluginName == "docs")
  }

  @Test func respectsFullDepthAndInternalSkillFiltering() throws {
    let root = try temporaryDirectory()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("nested/public"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("nested/internal"), withIntermediateDirectories: true)
    try """
    ---
    name: Root
    description: Root skill
    ---
    """.write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try """
    ---
    name: Public
    description: Public skill
    ---
    """.write(
      to: root.appendingPathComponent("nested/public/SKILL.md"), atomically: true, encoding: .utf8)
    try """
    ---
    name: Internal
    description: Internal skill
    metadata:
      internal: true
    ---
    """.write(
      to: root.appendingPathComponent("nested/internal/SKILL.md"), atomically: true, encoding: .utf8
    )

    let shallow = try Discovery.discover(in: root)
    #expect(shallow.map(\.name) == ["Root"])

    let fullDepth = try Discovery.discover(in: root, options: DiscoveryOptions(fullDepth: true))
    #expect(fullDepth.map(\.name).contains("Root"))
    #expect(fullDepth.map(\.name).contains("Public"))
    #expect(!fullDepth.map(\.name).contains("Internal"))

    let withInternal = try Discovery.discover(
      in: root, options: DiscoveryOptions(includeInternal: true, fullDepth: true))
    #expect(withInternal.map(\.name).contains("Internal"))
  }

  @Test func skipsInvalidFrontmatterValues() throws {
    let root = try temporaryDirectory()
    let invalidName = root.appendingPathComponent("skills/invalid-name")
    let invalidDescription = root.appendingPathComponent("skills/invalid-description")
    try FileManager.default.createDirectory(at: invalidName, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: invalidDescription, withIntermediateDirectories: true)
    try """
    ---
    name: 123
    description: Invalid name
    ---
    """.write(to: invalidName.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try """
    ---
    name: Invalid Description
    description: true
    ---
    """.write(
      to: invalidDescription.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let skills = try Discovery.discover(in: root)
    #expect(skills.isEmpty)
  }

  @Test func skipsMalformedFrontmatterAndKeepsValidSkills() throws {
    let root = try temporaryDirectory()
    let malformed = root.appendingPathComponent("skills/malformed")
    let valid = root.appendingPathComponent("skills/valid")
    try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
    try """
    ---
    name: [unterminated
    description: Broken
    ---
    """.write(to: malformed.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try """
    ---
    name: Valid
    description: Valid skill
    ---
    """.write(to: valid.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

    let skills = try Discovery.discover(in: root)
    #expect(skills.map(\.name) == ["Valid"])
  }
}

extension SkillMatchingTests {
  @Test func filtersSkillsByNameAndDirectoryCaseInsensitively() throws {
    let skill = Skill(
      name: "Code Review",
      description: "Review code",
      path: "/tmp/code-review",
      skillFile: "/tmp/code-review/SKILL.md"
    )
    #expect(Discovery.filter([skill], names: ["code review"]).map(\.name) == ["Code Review"])
    #expect(Discovery.filter([skill], names: ["CODE-REVIEW"]).map(\.name) == ["Code Review"])
    #expect(Discovery.filter([skill], names: ["review"]).isEmpty)
  }
}
