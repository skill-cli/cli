import Testing

@testable import Core

@Suite("Update Source Formatting")
struct UpdateSourceFormattingTests {
  @Test func formatsUpdateSourceDescriptions() {
    #expect(
      UpdateSource.formatSourceInput("https://github.com/owner/repo.git", ref: "feature/install")
        == "https://github.com/owner/repo.git#feature/install")
    #expect(
      UpdateSource.formatSourceInput("https://github.com/owner/repo.git")
        == "https://github.com/owner/repo.git")

    #expect(
      UpdateSource.buildUpdateInstallSource(
        source: "owner/repo",
        sourceURL: "https://github.com/owner/repo.git",
        ref: "feature/install",
        skillPath: "SKILL.md")
        == "owner/repo#feature/install")
    #expect(
      UpdateSource.buildUpdateInstallSource(
        source: "owner/repo",
        sourceURL: "https://github.com/owner/repo.git",
        ref: "feature/install",
        skillPath: "skills/my-skill/SKILL.md")
        == "owner/repo/skills/my-skill#feature/install")
    #expect(
      UpdateSource.buildUpdateInstallSource(
        source: "owner/repo",
        sourceURL: "https://github.com/owner/repo.git",
        ref: "feature/install")
        == "https://github.com/owner/repo.git#feature/install")

    #expect(
      UpdateSource.buildLocalUpdateSource(
        source: "owner/repo", ref: "main", skillPath: "skills/my-skill/SKILL.md")
        == "owner/repo/skills/my-skill#main")
    #expect(
      UpdateSource.buildLocalUpdateSource(
        source: "owner/repo", skillPath: "skills/my-skill/SKILL.md")
        == "owner/repo/skills/my-skill")
    #expect(
      UpdateSource.buildLocalUpdateSource(source: "owner/repo", skillPath: "SKILL.md")
        == "owner/repo")
    #expect(
      UpdateSource.buildLocalUpdateSource(source: "owner/repo", ref: "main") == "owner/repo#main")
  }

}
