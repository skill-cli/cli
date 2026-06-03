import Foundation
import Testing

@testable import Core

@Suite("Source Parser")
struct SourceParserTests {
  @Test func parsesHostedRepositoryShorthandAndWellKnownSourceForms() throws {
    struct Case {
      var name: String
      var input: String
      var type: SourceType
      var url: String
      var ref: String? = nil
      var subpath: String? = nil
      var skillFilter: String? = nil
    }

    let cases = [
      Case(
        name: "GitHub URL - basic repo", input: "https://github.com/owner/repo", type: .github,
        url: "https://github.com/owner/repo.git"),
      Case(
        name: "GitHub URL - with .git suffix", input: "https://github.com/owner/repo.git",
        type: .github, url: "https://github.com/owner/repo.git"),
      Case(
        name: "GitHub URL - with .git suffix and #branch",
        input: "https://github.com/owner/repo.git#feature/install", type: .github,
        url: "https://github.com/owner/repo.git", ref: "feature/install"),
      Case(
        name: "GitHub blob URL anchor is not treated as a ref",
        input: "https://github.com/owner/repo/blob/main/README.md#L10", type: .github,
        url: "https://github.com/owner/repo.git"),
      Case(
        name: "GitHub URL - tree with branch only",
        input: "https://github.com/owner/repo/tree/feature-branch", type: .github,
        url: "https://github.com/owner/repo.git", ref: "feature-branch"),
      Case(
        name: "GitHub URL - tree with branch and path",
        input: "https://github.com/owner/repo/tree/main/skills/my-skill", type: .github,
        url: "https://github.com/owner/repo.git", ref: "main", subpath: "skills/my-skill"),
      Case(
        name: "GitHub URL - tree with slash in path",
        input: "https://github.com/owner/repo/tree/feature/my-feature", type: .github,
        url: "https://github.com/owner/repo.git", ref: "feature", subpath: "my-feature"),
      Case(
        name: "GitLab URL - basic repo", input: "https://gitlab.com/owner/repo", type: .gitlab,
        url: "https://gitlab.com/owner/repo.git"),
      Case(
        name: "GitLab URL - tree with branch only",
        input: "https://gitlab.com/owner/repo/-/tree/develop", type: .gitlab,
        url: "https://gitlab.com/owner/repo.git", ref: "develop"),
      Case(
        name: "GitLab URL - tree with branch and path",
        input: "https://gitlab.com/owner/repo/-/tree/main/src/skills", type: .gitlab,
        url: "https://gitlab.com/owner/repo.git", ref: "main", subpath: "src/skills"),
      Case(
        name: "GitLab URL - subgroup with tree/branch/path",
        input: "https://gitlab.com/group/subgroup/repo/-/tree/main/path/to/skill",
        type: .gitlab, url: "https://gitlab.com/group/subgroup/repo.git", ref: "main",
        subpath: "path/to/skill"),
      Case(
        name: "GitHub shorthand - owner/repo", input: "owner/repo", type: .github,
        url: "https://github.com/owner/repo.git"),
      Case(
        name: "GitHub shorthand - owner/repo/path", input: "owner/repo/skills/my-skill",
        type: .github, url: "https://github.com/owner/repo.git", subpath: "skills/my-skill"),
      Case(
        name: "GitHub shorthand - owner/repo@skill", input: "owner/repo@my-skill", type: .github,
        url: "https://github.com/owner/repo.git", skillFilter: "my-skill"),
      Case(
        name: "GitHub shorthand - owner/repo#branch", input: "owner/repo#my-branch",
        type: .github, url: "https://github.com/owner/repo.git", ref: "my-branch"),
      Case(
        name: "GitHub shorthand - owner/repo/path#branch",
        input: "owner/repo/skills/my-skill#feature/skills", type: .github,
        url: "https://github.com/owner/repo.git", ref: "feature/skills",
        subpath: "skills/my-skill"),
      Case(
        name: "GitHub shorthand - owner/repo#branch@skill",
        input: "owner/repo#my-branch@my-skill", type: .github,
        url: "https://github.com/owner/repo.git", ref: "my-branch", skillFilter: "my-skill"),
      Case(
        name: "Git URL - SSH format", input: "git@github.com:owner/repo.git", type: .git,
        url: "git@github.com:owner/repo.git"),
      Case(
        name: "Git URL - SSH format with #branch",
        input: "git@github.com:owner/repo.git#feature/install", type: .git,
        url: "git@github.com:owner/repo.git", ref: "feature/install"),
      Case(
        name: "Git URL - custom host", input: "https://git.example.com/owner/repo.git",
        type: .git, url: "https://git.example.com/owner/repo.git"),
      Case(
        name: "Git URL - https format with #branch",
        input: "https://git.example.com/owner/repo.git#release-2026", type: .git,
        url: "https://git.example.com/owner/repo.git", ref: "release-2026"),
      Case(
        name: "github:owner/repo - basic", input: "github:owner/repo", type: .github,
        url: "https://github.com/owner/repo.git"),
      Case(
        name: "github:owner/repo/subpath", input: "github:owner/repo/skills/my-skill",
        type: .github, url: "https://github.com/owner/repo.git", subpath: "skills/my-skill"),
      Case(
        name: "github:owner/repo@skill-name", input: "github:owner/repo@my-skill",
        type: .github, url: "https://github.com/owner/repo.git", skillFilter: "my-skill"),
      Case(
        name: "github:owner/repo#branch", input: "github:owner/repo#feature/install",
        type: .github, url: "https://github.com/owner/repo.git", ref: "feature/install"),
      Case(
        name: "gitlab:group/subgroup/repo", input: "gitlab:group/subgroup/repo",
        type: .gitlab, url: "https://gitlab.com/group/subgroup/repo.git"),
      Case(
        name: "custom gitlab domain with deep subgroup paths",
        input: "https://git.corp.com/group/subgroup/project/-/tree/main/src", type: .gitlab,
        url: "https://git.corp.com/group/subgroup/project.git", ref: "main", subpath: "src"),
      Case(
        name: "custom gitlab domain with port number",
        input: "https://git.corp.com:8443/group/repo/-/tree/main", type: .gitlab,
        url: "https://git.corp.com:8443/group/repo.git", ref: "main"),
      Case(
        name: "http protocol custom gitlab", input: "http://git.local/group/repo/-/tree/dev",
        type: .gitlab, url: "http://git.local/group/repo.git", ref: "dev"),
      Case(
        name: "custom domains with .git are generic git",
        input: "https://git.mycompany.com/my-group/my-repo.git", type: .git,
        url: "https://git.mycompany.com/my-group/my-repo.git"),
      Case(
        name: "generic URLs fall through to well-known",
        input: "https://google.com/docs/result", type: .wellKnown,
        url: "https://google.com/docs/result"),
      Case(
        name: "coinbase alias", input: "coinbase/agentWallet", type: .github,
        url: "https://github.com/coinbase/agentic-wallet-skills.git"),
    ]

    for testCase in cases {
      let parsed = try SourceParser.parse(testCase.input)
      #expect(parsed.type == testCase.type, "type: \(testCase.name)")
      #expect(parsed.url == testCase.url, "url: \(testCase.name)")
      #expect(parsed.ref == testCase.ref, "ref: \(testCase.name)")
      #expect(parsed.subpath == testCase.subpath, "subpath: \(testCase.name)")
      #expect(parsed.skillFilter == testCase.skillFilter, "skillFilter: \(testCase.name)")
    }
  }

  @Test func extractsOwnerRepoFromHostedAndGitSourceForms() throws {
    let cases: [(String, String?)] = [
      ("https://github.com/owner/repo", "owner/repo"),
      ("https://github.com/owner/repo.git", "owner/repo"),
      ("https://github.com/owner/repo/tree/main/skills/my-skill", "owner/repo"),
      ("owner/repo/skills/my-skill", "owner/repo"),
      ("https://gitlab.com/coresofthq/ai/agent-skills", "coresofthq/ai/agent-skills"),
      ("./my-skills", nil),
      ("https://git.example.com/owner/repo.git", "owner/repo"),
      ("git@github.com:owner/repo.git", "owner/repo"),
      ("https://gitlab.company.com/team/repo", "team/repo"),
      ("https://git.example.com/owner/repo?ref=main", "owner/repo"),
      ("git@gitlab.com:group/subgroup/project/repo.git", "group/subgroup/project/repo"),
      ("ssh://git@git.company.com:7999/org/team/repo.git", "org/team/repo"),
      ("git@github.com:repo.git", nil),
    ]

    for (input, expected) in cases {
      let parsed = try SourceParser.parse(input)
      #expect(SourceParser.ownerRepo(for: parsed) == expected, "ownerRepo: \(input)")
    }
  }

  @Test func parsesLocalGitLabSSHAndProviderSpecificSourceForms() throws {
    struct Case {
      var name: String
      var input: String
      var type: SourceType
      var url: String
      var ref: String?
      var subpath: String?
      var skillFilter: String?
    }

    let cwd = URL(fileURLWithPath: "/tmp/skill-cli-parser-cwd")
    let relative = try SourceParser.parse("./my-skills", currentDirectory: cwd)
    #expect(relative.type == .local)
    #expect(relative.localPath?.contains("my-skills") == true)

    let parent = try SourceParser.parse("../other-skills", currentDirectory: cwd)
    #expect(parent.type == .local)
    #expect(parent.localPath?.contains("other-skills") == true)

    let current = try SourceParser.parse(".", currentDirectory: cwd)
    #expect(current.type == .local)
    #expect(current.localPath?.isEmpty == false)

    let absolute = try SourceParser.parse("/home/user/skills", currentDirectory: cwd)
    #expect(absolute.type == .local)
    #expect(absolute.localPath == "/home/user/skills")

    let parseCases: [Case] = [
      Case(
        name: "GitLab URL - with .git suffix",
        input: "https://gitlab.com/owner/repo.git",
        type: .gitlab,
        url: "https://gitlab.com/owner/repo.git"),
      Case(
        name: "GitLab URL - subgroup (2 levels)",
        input: "https://gitlab.com/group/subgroup/repo",
        type: .gitlab,
        url: "https://gitlab.com/group/subgroup/repo.git"),
      Case(
        name: "GitLab URL - subgroup (3 levels)",
        input: "https://gitlab.com/coresofthq/ai/agent-skills",
        type: .gitlab,
        url: "https://gitlab.com/coresofthq/ai/agent-skills.git"),
      Case(
        name: "GitLab URL - deep subgroup with .git suffix",
        input: "https://gitlab.com/org/team/project/repo.git",
        type: .gitlab,
        url: "https://gitlab.com/org/team/project/repo.git"),
      Case(
        name: "GitLab URL - subgroup with tree/branch",
        input: "https://gitlab.com/group/subgroup/repo/-/tree/main",
        type: .gitlab,
        url: "https://gitlab.com/group/subgroup/repo.git",
        ref: "main"),
      Case(
        name: "GitLab URL - trailing slash",
        input: "https://gitlab.com/group/subgroup/repo/",
        type: .gitlab,
        url: "https://gitlab.com/group/subgroup/repo.git"),
      Case(
        name: "GitHub shorthand - owner/repo/ trailing slash",
        input: "owner/repo/",
        type: .github,
        url: "https://github.com/owner/repo.git"),
      Case(
        name: "GitHub shorthand - owner/repo@skill with hyphenated skill name",
        input: "example/agent-skills@demo-skill",
        type: .github,
        url: "https://github.com/example/agent-skills.git",
        skillFilter: "demo-skill"),
      Case(
        name: "Git URL - ssh scheme with #branch",
        input: "ssh://git@git.example.com:7999/owner/repo.git#release-2026",
        type: .git,
        url: "ssh://git@git.example.com:7999/owner/repo.git",
        ref: "release-2026"),
      Case(
        name: "github:googleworkspace/cli",
        input: "github:googleworkspace/cli",
        type: .github,
        url: "https://github.com/googleworkspace/cli.git"),
      Case(
        name: "gitlab:owner/repo - basic",
        input: "gitlab:owner/repo",
        type: .gitlab,
        url: "https://gitlab.com/owner/repo.git"),
    ]

    for testCase in parseCases {
      let parsed = try SourceParser.parse(testCase.input)
      #expect(parsed.type == testCase.type, "type: \(testCase.name)")
      #expect(parsed.url == testCase.url, "url: \(testCase.name)")
      #expect(parsed.ref == testCase.ref, "ref: \(testCase.name)")
      #expect(parsed.subpath == testCase.subpath, "subpath: \(testCase.name)")
      #expect(parsed.skillFilter == testCase.skillFilter, "skillFilter: \(testCase.name)")
    }
  }

  @Test func extractsOwnerRepoFromHostedGitLabAndSSHSourceForms() throws {
    let parsedCases: [(String, String?)] = [
      ("https://gitlab.com/owner/repo/-/tree/main/skills", "owner/repo"),
      ("https://gitlab.company.com/team/repo", "team/repo"),
      ("https://git.internal.io/myteam/skills.git", "myteam/skills"),
      ("https://git.example.com/owner/repo#readme", "owner/repo"),
      ("https://git.example.com/owner/repo.git?ref=main", "owner/repo"),
      ("https://gitlab.com/group/subgroup/repo?ref=main", "group/subgroup/repo"),
      ("https://gitlab.company.com/division/team/repo.git", "division/team/repo"),
      ("git@gitlab.com:owner/repo.git", "owner/repo"),
      ("git@gitlab.com:group/subgroup/project/repo.git", "group/subgroup/project/repo"),
      ("git@github.com:owner/repo", "owner/repo"),
      ("git@git.company.com:org/team/repo.git", "org/team/repo"),
    ]

    for (input, expected) in parsedCases {
      let parsed = try SourceParser.parse(input)
      #expect(SourceParser.ownerRepo(for: parsed) == expected, "ownerRepo: \(input)")
    }

    let direct = ParsedSource(type: .git, url: "git@github.com:repo.git")
    #expect(SourceParser.ownerRepo(for: direct) == nil)
  }

  @Test func rejectsUnsafeSourceSubpaths() throws {
    for subpath in ["skills/my-skill", "path/to/skill", "src", ".hidden", "file.txt", "..skill"] {
      #expect(try PathSafety.sanitizeSubpath(subpath) == subpath)
    }
    for subpath in ["../etc", "../../etc/passwd", "skills/../../etc", "..\\..\\secret"] {
      #expect(throws: CoreError.self) {
        _ = try PathSafety.sanitizeSubpath(subpath)
      }
    }

    #expect(PathSafety.isSubpathSafe(base: URL(fileURLWithPath: "/tmp/repo"), subpath: "skills"))
    #expect(
      !PathSafety.isSubpathSafe(base: URL(fileURLWithPath: "/tmp/repo"), subpath: "../../etc"))
  }

  @Test func parsesTypedSourceSelectorsAndRejectsConflicts() throws {
    let branchPath = try SourceParser.parse("larksuite/cli@branch:main@path:skills/lark-base")
    #expect(branchPath.type == .github)
    #expect(branchPath.url == "https://github.com/larksuite/cli.git")
    #expect(branchPath.ref == "main")
    #expect(branchPath.requirement == .branch("main"))
    #expect(branchPath.subpath == "skills/lark-base")

    let versionSkill = try SourceParser.parse("larksuite/cli@from:1.2.0@skill:lark-base")
    #expect(versionSkill.requirement == .upToNextMajor(from: "1.2.0"))
    #expect(versionSkill.ref == nil)
    #expect(versionSkill.skillFilter == "lark-base")

    let revisionPath = try SourceParser.parse(
      "larksuite/cli@revision:abc123@path:skills/lark-base")
    #expect(revisionPath.requirement == .revision("abc123"))
    #expect(revisionPath.ref == "abc123")
    #expect(revisionPath.subpath == "skills/lark-base")

    let compatibility = try SourceParser.parse("larksuite/cli#main@lark-base")
    #expect(compatibility.requirement == .ref("main"))
    #expect(compatibility.skillFilter == "lark-base")

    let prefixed = try SourceParser.parse("github:larksuite/cli@branch:main@skill:lark-base")
    #expect(prefixed.requirement == .branch("main"))
    #expect(prefixed.skillFilter == "lark-base")

    #expect(throws: CoreError.self) {
      _ = try SourceParser.parse("larksuite/cli@unknown:value")
    }
    #expect(throws: CoreError.self) {
      _ = try SourceParser.parse("larksuite/cli@branch:main@revision:abc123")
    }
    #expect(throws: CoreError.self) {
      _ = try SourceParser.parse("larksuite/cli@path:skills/a@skill:a")
    }
    #expect(throws: CoreError.self) {
      _ = try SourceParser.parse("larksuite/cli/skills/a@path:skills/b")
    }
  }

}
