import Foundation
import Testing

@testable import Core

extension WellKnownSourceTests {
  @Test func fetchesWellKnownSkillMarkdownAndCompatibilityFileIndexes() throws {
    let skillMd = Data(
      """
      ---
      name: code-review
      description: Review code.
      ---
      # Code Review
      """.utf8)
    let digest = "sha256:" + FileHash.sha256Hex(data: skillMd)

    let responsesV2: [String: Data] = [
      "https://example.com/.well-known/agent-skills/index.json": Data(
        """
        {
          "$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
          "skills": [
            {
              "name": "code-review",
              "type": "skill-md",
              "description": "Review code.",
              "url": "code-review/SKILL.md",
              "digest": "\(digest)"
            }
          ]
        }
        """.utf8),
      "https://example.com/.well-known/agent-skills/code-review/SKILL.md": skillMd,
    ]
    let providerV2 = WellKnownProvider { url in
      guard let data = responsesV2[url.absoluteString] else {
        throw CoreError.notFound(url.absoluteString)
      }
      return data
    }

    let v2 = try providerV2.fetchAllSkills(from: "https://example.com")
    #expect(v2.count == 1)
    #expect(v2[0].installName == "code-review")
    #expect(v2[0].files["SKILL.md"] == skillMd)

    let responsesV1: [String: Data] = [
      "https://legacy.example.com/.well-known/agent-skills/index.json": Data(
        """
        {
          "skills": [
            {
              "name": "legacy-skill",
              "description": "Legacy skill.",
              "files": ["SKILL.md", "references/README.md"]
            }
          ]
        }
        """.utf8),
      "https://legacy.example.com/.well-known/agent-skills/legacy-skill/SKILL.md": Data(
        "---\nname: legacy-skill\ndescription: Legacy skill.\n---".utf8),
      "https://legacy.example.com/.well-known/agent-skills/legacy-skill/references/README.md": Data(
        "Reference".utf8),
    ]
    let providerV1 = WellKnownProvider { url in
      guard let data = responsesV1[url.absoluteString] else {
        throw CoreError.notFound(url.absoluteString)
      }
      return data
    }

    let legacy = try providerV1.fetchAllSkills(from: "https://legacy.example.com")
    #expect(legacy.count == 1)
    #expect(legacy[0].files["references/README.md"] == Data("Reference".utf8))
  }

  @Test func fetchesDigestVerifiedTarArchives() throws {
    let archiveRoot = try temporaryDirectory()
    try """
    ---
    name: archive-skill
    description: Archive skill.
    ---
    # Archive
    """.write(to: archiveRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: archiveRoot.appendingPathComponent("references"), withIntermediateDirectories: true)
    try "Reference".write(
      to: archiveRoot.appendingPathComponent("references/README.md"), atomically: true,
      encoding: .utf8)
    let archive = try temporaryDirectory().appendingPathComponent("skill.tar.gz")
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["tar", "-czf", archive.path, "-C", archiveRoot.path, "."])
    let archiveData = try Data(contentsOf: archive)
    let digest = "sha256:" + FileHash.sha256Hex(data: archiveData)

    let responses: [String: Data] = [
      "https://example.com/.well-known/agent-skills/index.json": Data(
        """
        {
          "$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
          "skills": [
            {
              "name": "archive-skill",
              "type": "archive",
              "description": "Archive skill.",
              "url": "archive-skill.tar.gz",
              "digest": "\(digest)"
            }
          ]
        }
        """.utf8),
      "https://example.com/.well-known/agent-skills/archive-skill.tar.gz": archiveData,
    ]
    let provider = WellKnownProvider { url in
      guard let data = responses[url.absoluteString] else {
        throw CoreError.notFound(url.absoluteString)
      }
      return data
    }

    let skills = try provider.fetchAllSkills(from: "https://example.com")
    #expect(skills.count == 1)
    #expect(skills[0].files["SKILL.md"] != nil)
    #expect(skills[0].files["references/README.md"] == Data("Reference".utf8))
  }

  @Test func fetchesDigestVerifiedZipArchives() throws {
    let archiveRoot = try temporaryDirectory()
    try """
    ---
    name: zip-skill
    description: Zip skill.
    ---
    # Zip
    """.write(to: archiveRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: archiveRoot.appendingPathComponent("references"), withIntermediateDirectories: true)
    try "Zip Reference".write(
      to: archiveRoot.appendingPathComponent("references/README.md"), atomically: true,
      encoding: .utf8)
    let archive = try temporaryDirectory().appendingPathComponent("skill.zip")
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["zip", "-qr", archive.path, "."], workingDirectory: archiveRoot)
    let archiveData = try Data(contentsOf: archive)
    let digest = "sha256:" + FileHash.sha256Hex(data: archiveData)

    let responses: [String: Data] = [
      "https://example.com/.well-known/agent-skills/index.json": Data(
        """
        {
          "$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
          "skills": [
            {
              "name": "zip-skill",
              "type": "archive",
              "description": "Zip skill.",
              "url": "zip-skill.zip",
              "digest": "\(digest)"
            }
          ]
        }
        """.utf8),
      "https://example.com/.well-known/agent-skills/zip-skill.zip": archiveData,
    ]
    let provider = WellKnownProvider { url in
      guard let data = responses[url.absoluteString] else {
        throw CoreError.notFound(url.absoluteString)
      }
      return data
    }

    let skills = try provider.fetchAllSkills(from: "https://example.com")
    #expect(skills.count == 1)
    #expect(skills[0].files["SKILL.md"] != nil)
    #expect(skills[0].files["references/README.md"] == Data("Zip Reference".utf8))
  }

  @Test func rejectsSymlinkEntriesInWellKnownArchives() throws {
    let archiveRoot = try temporaryDirectory()
    try "target".write(
      to: archiveRoot.appendingPathComponent("target.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      atPath: archiveRoot.appendingPathComponent("link.txt").path,
      withDestinationPath: "target.txt"
    )
    let archive = try temporaryDirectory().appendingPathComponent("unsafe.tar.gz")
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["tar", "-czf", archive.path, "-C", archiveRoot.path, "."])
    let archiveData = try Data(contentsOf: archive)
    let digest = "sha256:" + FileHash.sha256Hex(data: archiveData)
    let responses: [String: Data] = [
      "https://example.com/.well-known/agent-skills/index.json": Data(
        """
        {
          "$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
          "skills": [
            {
              "name": "unsafe-archive",
              "type": "archive",
              "description": "Unsafe archive.",
              "url": "unsafe.tar.gz",
              "digest": "\(digest)"
            }
          ]
        }
        """.utf8),
      "https://example.com/.well-known/agent-skills/unsafe.tar.gz": archiveData,
    ]
    let provider = WellKnownProvider { url in
      guard let data = responses[url.absoluteString] else {
        throw CoreError.notFound(url.absoluteString)
      }
      return data
    }

    #expect(throws: CoreError.self) {
      _ = try provider.fetchAllSkills(from: "https://example.com")
    }
  }
}
