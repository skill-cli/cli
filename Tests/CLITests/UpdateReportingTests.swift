import Foundation
import Testing

@testable import CLI

struct UpdateReportingTests {
  @Test func versionsAndExecutableChangesRemainAdditive() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    let script = fixture.source.appendingPathComponent("skills/pdf/run.sh")
    try Data("#!/bin/sh\necho ready\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script.path)
    try fixture.commit()
    try fixture.git(["tag", "1.0.0"])
    try fixture.success(["add", fixture.source.path, "pdf", "--from", "1.0.0", "--mode", "copy"])
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    try fixture.commit()
    try fixture.git(["tag", "1.1.0"])

    let report = try fixture.success(["update", "--json"]).json()
    #expect(report["schemaVersion"] as? Int == 1)
    #expect(report["changed"] as? Bool == true)
    let item = try updateItem(report)
    #expect(item["oldVersion"] as? String == "1.0.0")
    #expect(item["newVersion"] as? String == "1.1.0")
    #expect(item["oldHash"] as? String == item["newHash"] as? String)
    #expect(item["lockMissing"] as? Bool == false)
    #expect((item["oldRevision"] as? String)?.count == 40)
    #expect((item["newRevision"] as? String)?.count == 40)
    let files = try #require(item["files"] as? [[String: Any]])
    #expect(files.count == 2)
    for file in files {
      #expect((file["path"] as? String)?.hasSuffix("/pdf/run.sh") == true)
      let before = try #require(file["before"] as? [String: Any])
      let after = try #require(file["after"] as? [String: Any])
      #expect(before["base64"] as? String == after["base64"] as? String)
      #expect(before["executable"] as? Bool == false)
      #expect(after["executable"] as? Bool == true)
    }
    let preview = try fixture.success(["update"]).stdout
    #expect(preview.hasPrefix("~ changed  pdf"))
    let old = try #require(item["oldRevision"] as? String).prefix(7)
    let new = try #require(item["newRevision"] as? String).prefix(7)
    #expect(preview.contains("1.0.0 (\(old)) -> 1.1.0 (\(new))\n"))
    #expect(preview.components(separatedBy: "mode pdf/run.sh: 644 -> 755\n").count == 2)
    #expect(!preview.contains("--- ") && !preview.contains("= repinned"))
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.contains("mode pdf/run.sh: 644 -> 755\n"))
    #expect(
      applied.hasSuffix(
        "Updated pdf for claude-code, codex: 1.0.0 (\(old)) -> 1.1.0 (\(new)).\n"))
    for directory in [".agents", ".claude"] {
      let target = fixture.project.appendingPathComponent("\(directory)/skills/pdf/run.sh")
      let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
      #expect((attributes[.posixPermissions] as? Int).map { $0 & 0o111 != 0 } == true)
    }
    #expect(try fixture.success(["update"]).stdout == "No skill changes.\n")
  }

  @Test func executableDriftAtSamePinIsChanged() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["add", fixture.source.path, "pdf", "--mode", "copy", "--agent", "codex"])
    let target = fixture.project.appendingPathComponent(".agents/skills/pdf/SKILL.md")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    let item = try updateItem(fixture.success(["update", "--json"]).json())
    #expect(item["oldVersion"] == nil && item["newVersion"] == nil)
    #expect(item["oldRevision"] as? String == item["newRevision"] as? String)
    #expect(item["oldHash"] as? String == item["newHash"] as? String)
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.hasPrefix("~ changed  pdf"))
    #expect(applied.contains("mode pdf/SKILL.md: 755 -> 644\n"))
    #expect(applied.hasSuffix("Updated pdf for codex.\n"))
  }

  @Test func membershipIncludesSharedPathsAndUnchangedRecipients() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.success(["add", fixture.source.path, "pdf", "--mode", "edit"])
    try selection(fixture) { $0["agents"] = ["claude-code", "cursor"] }
    let item = try updateItem(fixture.success(["update", "--json"]).json())
    #expect(item["oldVersion"] == nil && item["newVersion"] == nil)
    #expect(item["oldRevision"] == nil && item["newRevision"] == nil)
    #expect((item["files"] as? [Any])?.isEmpty == true)
    let rows = try #require(item["membership"] as? [[String: Any]])
    #expect(rows.compactMap { $0["agent"] as? String } == ["claude-code", "codex", "cursor"])
    let installed = ["kind": "installed", "mode": "edit"]
    #expect(rows[0]["before"] as? [String: String] == installed)
    #expect(rows[0]["after"] as? [String: String] == installed)
    #expect(rows[1]["before"] as? [String: String] == installed)
    #expect(rows[1]["after"] as? [String: String] == ["kind": "absent"])
    #expect(rows[2]["before"] as? [String: String] == ["kind": "absent"])
    #expect(rows[2]["after"] as? [String: String] == installed)
    #expect(rows[1]["path"] as? String == rows[2]["path"] as? String)
    let preview = try fixture.success(["update"]).stdout
    #expect(preview.contains("  = unchanged  claude-code (edit)  .claude/skills/pdf\n"))
    #expect(preview.contains("  - removed  codex (edit)  .agents/skills/pdf\n"))
    #expect(preview.contains("  + added  cursor (edit)  .agents/skills/pdf\n"))
    #expect(!preview.contains("link pdf:") && !preview.contains("--- "))
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(
      applied.hasSuffix(
        "Removed pdf for codex.\nAdded pdf for cursor.\nUpdated pdf for claude-code.\n"))
    let unchanged = try updateItem(fixture.success(["update", "--json"]).json())
    #expect(unchanged["changed"] as? Bool == false)
    let retained = try #require(unchanged["membership"] as? [[String: Any]])
    #expect(retained.compactMap { $0["agent"] as? String } == ["claude-code", "cursor"])
    #expect(
      retained.allSatisfy {
        $0["before"] as? [String: String] == installed
          && $0["after"] as? [String: String] == installed
      })
  }

  @Test func missingLockReportsUnrecordedMembershipAndApplyRejectsUnmanagedLink() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.success(["add", fixture.source.path, "pdf", "--mode", "edit", "--agent", "codex"])
    try FileManager.default.removeItem(at: fixture.state("agents.resolved"))
    let declaration = try Data(contentsOf: fixture.state("agents.json"))
    let target = fixture.project.appendingPathComponent(".agents/skills/pdf")
    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
    let item = try updateItem(fixture.success(["update", "--json"]).json())
    #expect(item["lockMissing"] as? Bool == true)
    #expect(item["changed"] as? Bool == true)
    #expect((item["files"] as? [Any])?.isEmpty == true)
    let row = try #require((item["membership"] as? [[String: Any]])?.first)
    #expect(row["before"] as? [String: String] == ["kind": "absent"])
    #expect(row["after"] as? [String: String] == ["kind": "installed", "mode": "edit"])
    let preview = try fixture.success(["update"]).stdout
    #expect(preview.hasPrefix("Lock missing: prior skill membership is unrecorded.\n+ new  pdf"))
    #expect(preview.contains("  + added  codex (edit)  .agents/skills/pdf\n"))
    let failed = try fixture.run(["update", "--apply"])
    #expect(failed.status == 1)
    #expect(!failed.stdout.contains("Updated") && !failed.stdout.contains("Added"))
    #expect(failed.stderr.contains("an entry this scope does not manage already exists there"))
    #expect(try Data(contentsOf: fixture.state("agents.json")) == declaration)
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.resolved").path))
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == destination)
  }

  @Test func liveMembershipAddsAndRemovesMissingTargets() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.success(["add", fixture.source.path, "--all", "--mode", "edit", "--agent", "codex"])
    try fixture.skill("review")
    let added = try fixture.success(["update", "--apply"]).stdout
    #expect(added.hasPrefix("+ new  review"))
    #expect(added.contains("  + added  codex (edit)  .agents/skills/review\n"))
    #expect(added.hasSuffix("Added review for codex.\n"))
    try FileManager.default.removeItem(
      at: fixture.project.appendingPathComponent(".agents/skills/pdf"))
    try selection(fixture) { $0["exclude"] = ["pdf"] }
    let item = try updateItem(fixture.success(["update", "--json"]).json())
    #expect((item["files"] as? [Any])?.isEmpty == true)
    let removed = try fixture.success(["update", "--apply"]).stdout
    #expect(removed.hasPrefix("- removed  pdf"))
    #expect(removed.contains("  - removed  codex (edit)  .agents/skills/pdf\n"))
    #expect(removed.hasSuffix("Removed pdf for codex.\n"))
  }

  @Test func versionRepinHasNoContentDiff() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.git(["tag", "1.0.0"])
    try fixture.success(["add", fixture.source.path, "pdf", "--from", "1.0.0", "--agent", "codex"])
    try Data("Other changes\n".utf8).write(to: fixture.source.appendingPathComponent("README.md"))
    try fixture.commit()
    try fixture.git(["tag", "1.1.0"])
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.hasPrefix("= repinned  pdf"))
    #expect(applied.contains("1.0.0 (") && applied.contains(" -> 1.1.0 ("))
    #expect(applied.contains("  = unchanged  codex (link)  .agents/skills/pdf\n"))
    #expect(!applied.contains("--- ") && !applied.contains("link pdf:"))
  }

  @Test func versionedAdditionsAndRemovalsHaveAbsentPins() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.git(["tag", "1.0.0"])
    try fixture.success([
      "add", fixture.source.path, "--all", "--from", "1.0.0", "--agent", "codex",
    ])
    try FileManager.default.removeItem(at: fixture.source.appendingPathComponent("skills/pdf"))
    try fixture.skill("review")
    try fixture.commit()
    try fixture.git(["tag", "1.1.0"])
    let report = try fixture.success(["update", "--json"]).json()
    let items = try #require(report["skills"] as? [[String: Any]])
    let pdf = try #require(items.first { $0["name"] as? String == "pdf" })
    let review = try #require(items.first { $0["name"] as? String == "review" })
    #expect(pdf["oldVersion"] as? String == "1.0.0" && pdf["newVersion"] == nil)
    #expect(review["oldVersion"] == nil && review["newVersion"] as? String == "1.1.0")
    let old = try #require(pdf["oldRevision"] as? String).prefix(7)
    let new = try #require(review["newRevision"] as? String).prefix(7)
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.contains("none -> 1.1.0 (\(new))\n"))
    #expect(applied.contains("1.0.0 (\(old)) -> none\n"))
    #expect(
      applied.hasSuffix(
        "Removed pdf for codex: 1.0.0 (\(old)) -> none.\nAdded review for codex: none -> 1.1.0 (\(new)).\n"
      ))
  }

  @Test func newVersionTagAtSameRevisionIsRepinned() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.git(["tag", "1.0.0"])
    try fixture.success(["add", fixture.source.path, "pdf", "--from", "1.0.0", "--agent", "codex"])
    try fixture.git(["tag", "1.1.0"])
    let item = try updateItem(fixture.success(["update", "--json"]).json())
    #expect(item["oldRevision"] as? String == item["newRevision"] as? String)
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.hasPrefix("= repinned  pdf"))
    #expect(applied.contains("1.0.0 (") && applied.contains(" -> 1.1.0 ("))
    #expect(!applied.contains("--- "))
  }

  private func updateItem(_ report: [String: Any]) throws -> [String: Any] {
    try #require((report["skills"] as? [[String: Any]])?.first)
  }

  private func selection(_ fixture: CLIFixture, edit: (inout [String: Any]) -> Void) throws {
    var declaration = try fixture.declaration()
    var skills = try #require(declaration["skills"] as? [String: [String: Any]])
    let alias = try #require(skills.keys.first)
    var selection = try #require(skills[alias])
    edit(&selection)
    skills[alias] = selection
    declaration["skills"] = skills
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
  }
}
