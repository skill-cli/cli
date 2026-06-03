import ArgumentParser
import Core
import Foundation

struct Init: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init", abstract: "Create a skill skeleton.")

  @Argument var name: String?

  mutating func run() throws {
    let directory = try RuntimeService.initializeSkill(
      named: name, directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let relativeSkillPath =
      name == nil ? "SKILL.md" : "\(directory.lastPathComponent)/SKILL.md"
    print("Initialized skill: \(name ?? directory.lastPathComponent)")
    print("")
    print("Created:")
    print("  \(relativeSkillPath)")
    print("")
    print("Next steps:")
    print("  1. Edit \(relativeSkillPath) to define your skill instructions")
    print("  2. Update the name and description in the frontmatter")
    print("")
    print("Publishing:")
    print("  GitHub:  Push to a repo, then skill add <owner>/<repo>")
    print("  URL:     Host the file, then skill add https://example.com/\(relativeSkillPath)")
  }
}
