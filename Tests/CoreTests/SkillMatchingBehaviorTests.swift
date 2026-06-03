import Foundation
import Testing

@testable import Core

@Suite("Skill Matching")
struct SkillMatchingTests {
  @Test func matchesSkillsByNameAndDirectoryCaseInsensitively() {
    let skills = [
      matchingSkill("convex-best-practices"),
      matchingSkill("Convex Best Practices"),
      matchingSkill("simple-skill"),
      matchingSkill("foo"),
      matchingSkill("bar"),
    ]

    #expect(Discovery.filter(skills, names: ["foo"]).map(\.name) == ["foo"])
    #expect(Discovery.filter(skills, names: ["FOO"]).map(\.name) == ["foo"])
    #expect(
      Discovery.filter(skills, names: ["convex-best-practices"]).map(\.name)
        == ["convex-best-practices"])
    #expect(
      Discovery.filter(skills, names: ["foo", "bar"]).map(\.name).sorted() == ["bar", "foo"])
    #expect(
      Discovery.filter(skills, names: ["Convex Best Practices"]).map(\.name)
        == ["Convex Best Practices"])
    #expect(
      Discovery.filter(skills, names: ["convex best practices"]).map(\.name)
        == ["Convex Best Practices"])
    #expect(Discovery.filter(skills, names: ["Convex", "Best", "Practices"]).isEmpty)
    #expect(Discovery.filter(skills, names: ["Convex", "Best"]).isEmpty)
    #expect(Discovery.filter(skills, names: ["nonexistent"]).isEmpty)
    #expect(Discovery.filter(skills, names: []).isEmpty)
  }

  @Test func rejectsInvalidSkillFrontmatterTypes() throws {
    let cases = [
      ("numeric-name", "name: 123\ndescription: A skill with numeric name", false),
      ("boolean-name", "name: true\ndescription: A skill with boolean name", false),
      ("array-name", "name:\n  - foo\n  - bar\ndescription: A skill with array name", false),
      ("numeric-description", "name: valid-name\ndescription: 456", false),
      ("valid-skill", "name: valid-skill\ndescription: A valid skill", true),
    ]

    for (directoryName, frontmatter, shouldParse) in cases {
      let root = try matchingTemporaryDirectory()
      let skill = root.appendingPathComponent(directoryName)
      try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
      try """
      ---
      \(frontmatter)
      ---

      # \(directoryName)
      """.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

      let parsed = try Discovery.parseSkill(at: skill.appendingPathComponent("SKILL.md"))
      #expect((parsed != nil) == shouldParse, "frontmatter type case: \(directoryName)")
    }
  }

}

private func matchingSkill(_ name: String) -> Skill {
  Skill(name: name, description: "desc", path: "/tmp/\(name)", skillFile: "/tmp/\(name)/SKILL.md")
}

private func matchingTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-matching-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
