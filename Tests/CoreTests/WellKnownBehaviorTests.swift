import Foundation
import Testing

@testable import Core

@Suite("Well-Known Sources")
struct WellKnownSourceTests {
  @Test func detectsWellKnownURLsAndProviderIdentifiers() throws {
    let provider = WellKnownProvider()
    #expect(try SourceParser.parse("https://example.com").type == .wellKnown)
    #expect(try SourceParser.parse("https://mintlify.com/docs").type == .wellKnown)
    #expect(try SourceParser.parse("https://docs.example.com/skill.md").type == .wellKnown)
    #expect(try SourceParser.parse("https://github.com/owner/repo").type == .github)
    #expect(try SourceParser.parse("https://gitlab.com/owner/repo").type == .gitlab)
    #expect(try SourceParser.parse("https://huggingface.co/spaces/owner/repo").type == .git)
    #expect(try SourceParser.parse("https://git.example.com/owner/repo.git").type == .git)

    #expect(provider.sourceIdentifier(for: "https://example.com") == "example.com")
    #expect(provider.sourceIdentifier(for: "https://example.com/docs") == "example.com")
    #expect(provider.sourceIdentifier(for: "https://docs.example.com") == "docs.example.com")
    #expect(provider.sourceIdentifier(for: "https://www.mintlify.com/docs") == "mintlify.com")
    #expect(provider.sourceIdentifier(for: "not-a-url") == "unknown")

    let candidates = try provider.indexURLCandidates(for: "https://code.claude.com/docs")
    #expect(
      candidates.map { $0.index.absoluteString } == [
        "https://code.claude.com/docs/.well-known/agent-skills/index.json",
        "https://code.claude.com/.well-known/agent-skills/index.json",
        "https://code.claude.com/docs/.well-known/skills/index.json",
        "https://code.claude.com/.well-known/skills/index.json",
      ])
  }

  @Test func resolvesRelativePathsInLegacyWellKnownIndexes() throws {
    let responses: [String: Data] = [
      "https://code.claude.com/docs/.well-known/skills/index.json": Data(
        """
        {
          "skills": [
            { "name": "claude", "description": "Claude Code.", "files": ["SKILL.md"] }
          ]
        }
        """.utf8),
      "https://code.claude.com/docs/.well-known/skills/claude/SKILL.md": Data(
        "---\nname: claude\ndescription: Claude Code.\n---\n# Claude".utf8),
    ]
    let provider = WellKnownProvider { url in
      guard let data = responses[url.absoluteString] else {
        throw CoreError.notFound(url.absoluteString)
      }
      return data
    }

    let skills = try provider.fetchAllSkills(from: "https://code.claude.com/docs")
    #expect(skills.count == 1)
    #expect(skills[0].installName == "claude")
    #expect(
      skills[0].sourceURL.absoluteString
        == "https://code.claude.com/docs/.well-known/skills/claude/SKILL.md")
  }

  @Test func fetchesDirectSkillMarkdownURL() throws {
    let skillMD = Data(
      """
      ---
      name: direct-skill
      description: Direct skill.
      ---
      # Direct
      """.utf8)
    let provider = WellKnownProvider { url in
      guard url.absoluteString == "https://docs.example.com/skill.md" else {
        throw CoreError.notFound(url.absoluteString)
      }
      return skillMD
    }

    let skills = try provider.fetchAllSkills(from: "https://docs.example.com/skill.md")
    #expect(skills.count == 1)
    #expect(skills[0].installName == "direct-skill")
    #expect(skills[0].files["SKILL.md"] == skillMD)
    #expect(skills[0].digest == "sha256:" + FileHash.sha256Hex(data: skillMD))
  }

}
