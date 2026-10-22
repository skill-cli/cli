import AgentsCore
import AgentsSkills
import Foundation
import Testing

@testable import CLI

struct SkillRenderingTests {
  @Test(arguments: [false, true])
  func userCacheMovesThroughSymlinkedHomeAreHidden(relative: Bool) throws {
    let fixture = try CLIFixture()
    let home = fixture.home.resolvingSymlinksInPath()
    let alias = fixture.root.appendingPathComponent("linked-home")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home)
    let cache = home.appendingPathComponent(".agents/cache/materialized")
    try FileManager.default.createDirectory(
      at: cache.appendingPathComponent("old/pdf"), withIntermediateDirectories: true)
    let target = home.appendingPathComponent(".agents/skills/pdf")
    let before =
      relative ? "../cache/materialized/old/pdf" : cache.appendingPathComponent("old/pdf").path
    let after =
      relative
      ? "../cache/materialized/new/pdf"
      : alias.appendingPathComponent(".agents/cache/materialized/new/pdf").path
    func entry(_ value: SkillFileEntry) throws -> Any {
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    let data = try JSONSerialization.data(withJSONObject: [
      "skill": "pdf", "sourceIdentity": "source", "changed": true,
      "oldRevision": String(repeating: "a", count: 40),
      "newRevision": String(repeating: "b", count: 40),
      "changes": [
        [
          "path": target.path, "before": try entry(.symbolicLink(before)),
          "after": try entry(.symbolicLink(after)),
        ],
        [
          "path": target.appendingPathComponent("SKILL.md").path,
          "before": try entry(.file(Data("Old\n".utf8), executable: false)),
          "after": try entry(.file(Data("New\n".utf8), executable: false)),
        ],
      ],
      "installed": [], "lockMissing": false,
      "membership": [
        [
          "agent": "codex", "path": target.path,
          "before": ["installed": ["mode": "link"]],
          "after": ["installed": ["mode": "link"]],
        ]
      ],
    ])
    let result = try JSONDecoder().decode(UpdateResult.self, from: data)
    let environment = RuntimeEnvironment(
      projectDirectory: fixture.project, homeDirectory: alias, environment: fixture.environment)
    var output = ""
    Terminal.skillFileDifferences(
      result,
      paths: HumanPaths(scope: .user, environment: environment)
    ) { output += $0 }
    #expect(output == "--- a/pdf/SKILL.md\n+++ b/pdf/SKILL.md\n@@ -1 +1 @@\n-Old\n+New\n")
  }
}
