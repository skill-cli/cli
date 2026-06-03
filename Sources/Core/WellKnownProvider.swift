import Foundation
import Yams

public struct WellKnownRemoteSkill: Equatable, Sendable {
  public var installName: String
  public var description: String
  public var sourceURL: URL
  public var digest: String?
  public var files: [String: Data]

  public init(
    installName: String, description: String, sourceURL: URL, digest: String? = nil,
    files: [String: Data]
  ) {
    self.installName = installName
    self.description = description
    self.sourceURL = sourceURL
    self.digest = digest
    self.files = files
  }
}

public struct WellKnownProvider: Sendable {
  private static let maxArchiveFiles = 1000
  private static let maxArchiveUnpackedBytes = 50 * 1024 * 1024

  public var fetch: @Sendable (URL) throws -> Data

  public init(
    fetch: @escaping @Sendable (URL) throws -> Data = { url in try Data(contentsOf: url) }
  ) {
    self.fetch = fetch
  }

  public func sourceIdentifier(for rawURL: String) -> String {
    guard let url = URL(string: rawURL), var host = url.host else {
      return "unknown"
    }
    if host.hasPrefix("www.") {
      host.removeFirst(4)
    }
    return host
  }

  public func indexURLCandidates(for rawURL: String) throws -> [(
    index: URL, base: URL, wellKnownPath: String
  )] {
    guard let url = URL(string: rawURL), let scheme = url.scheme, let host = url.host else {
      throw CoreError.invalidSource("invalid well-known URL: \(rawURL)")
    }
    let basePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let pathPrefix = basePath.isEmpty ? "" : "/" + basePath
    let root = "\(scheme)://\(host)"
    let paths = [".well-known/agent-skills", ".well-known/skills"]
    var candidates: [(URL, URL, String)] = []
    for wellKnownPath in paths {
      candidates.append(
        (
          URL(string: "\(root)\(pathPrefix)/\(wellKnownPath)/index.json")!,
          URL(string: "\(root)\(pathPrefix)")!,
          wellKnownPath
        ))
      if !pathPrefix.isEmpty {
        candidates.append(
          (
            URL(string: "\(root)/\(wellKnownPath)/index.json")!,
            URL(string: root)!,
            wellKnownPath
          ))
      }
    }
    return candidates
  }

  public func fetchAllSkills(from rawURL: String) throws -> [WellKnownRemoteSkill] {
    if let direct = try fetchDirectSkillMD(from: rawURL) {
      return [direct]
    }
    var lastError: Error?
    for candidate in try indexURLCandidates(for: rawURL) {
      do {
        let data = try fetch(candidate.index)
        let index = try JSONDecoder().decode(WellKnownIndex.self, from: data)
        let skills = try normalize(
          index: index, indexURL: candidate.index, baseURL: candidate.base,
          wellKnownPath: candidate.wellKnownPath)
        if !skills.isEmpty {
          return skills
        }
      } catch {
        lastError = error
        continue
      }
    }
    if let lastError {
      throw lastError
    }
    return []
  }

  private func fetchDirectSkillMD(from rawURL: String) throws -> WellKnownRemoteSkill? {
    guard let url = URL(string: rawURL), url.path.lowercased().hasSuffix("skill.md") else {
      return nil
    }
    let data = try fetch(url)
    let text = String(data: data, encoding: .utf8) ?? ""
    let metadata = try parseFrontmatter(text)
    let fallbackName = url.deletingLastPathComponent().lastPathComponent
    let name = metadata.name ?? PathSafety.sanitizeName(fallbackName)
    let description = metadata.description ?? "Well-known skill"
    return WellKnownRemoteSkill(
      installName: PathSafety.sanitizeName(name),
      description: TextSanitizer.sanitizeMetadata(description),
      sourceURL: url,
      digest: "sha256:" + FileHash.sha256Hex(data: data),
      files: ["SKILL.md": data]
    )
  }

  public func materialize(_ skills: [WellKnownRemoteSkill], into checkout: URL) throws {
    if FileManager.default.fileExists(atPath: checkout.path) {
      try FileManager.default.removeItem(at: checkout)
    }
    try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
    for skill in skills {
      let skillRoot = checkout.appendingPathComponent("skills").appendingPathComponent(
        skill.installName)
      try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)
      for (relativePath, data) in skill.files {
        let safe = try PathSafety.sanitizeSubpath(relativePath)
        let target = skillRoot.appendingPathComponent(safe)
        guard PathSafety.isContained(target, in: skillRoot) else {
          throw CoreError.unsafePath("well-known file escapes skill root: \(relativePath)")
        }
        try FileManager.default.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
      }
    }
  }

  private func normalize(index: WellKnownIndex, indexURL: URL, baseURL: URL, wellKnownPath: String)
    throws -> [WellKnownRemoteSkill]
  {
    switch index {
    case .v1(let entries):
      return try entries.map { entry in
        var files: [String: Data] = [:]
        for file in entry.files {
          let safe = try PathSafety.sanitizeSubpath(file)
          let fileURL =
            baseURL
            .appendingPathComponent(wellKnownPath)
            .appendingPathComponent(entry.name)
            .appendingPathComponent(safe)
          files[safe] = try fetch(fileURL)
        }
        return WellKnownRemoteSkill(
          installName: entry.name,
          description: entry.description,
          sourceURL: baseURL.appendingPathComponent(wellKnownPath).appendingPathComponent(
            entry.name
          ).appendingPathComponent("SKILL.md"),
          files: files
        )
      }
    case .v2(let entries):
      return try entries.map { entry in
        guard let artifactURL = URL(string: entry.url, relativeTo: indexURL)?.absoluteURL else {
          throw CoreError.invalidSource("invalid artifact URL: \(entry.url)")
        }
        let data = try fetch(artifactURL)
        try verifyDigest(data: data, expected: entry.digest)
        let files: [String: Data]
        switch entry.type {
        case "skill-md":
          files = ["SKILL.md": data]
        case "archive":
          files = try unpackArchive(data, artifactURL: artifactURL)
        default:
          throw CoreError.invalidSource("unsupported well-known artifact type: \(entry.type)")
        }
        return WellKnownRemoteSkill(
          installName: entry.name,
          description: entry.description,
          sourceURL: artifactURL,
          digest: entry.digest,
          files: files
        )
      }
    }
  }

  private func verifyDigest(data: Data, expected: String) throws {
    guard expected.hasPrefix("sha256:") else {
      throw CoreError.invalidSource("unsupported digest format: \(expected)")
    }
    let actual = "sha256:" + FileHash.sha256Hex(data: data)
    guard actual == expected else {
      throw CoreError.invalidSource("well-known digest mismatch")
    }
  }

  private func parseFrontmatter(_ raw: String) throws -> (name: String?, description: String?) {
    guard raw.hasPrefix("---") else {
      return (nil, nil)
    }
    let pattern = #"^---\r?\n([\s\S]*?)\r?\n---\r?\n?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
      let range = Range(match.range(at: 1), in: raw)
    else {
      return (nil, nil)
    }
    let yaml = TextSanitizer.stripTerminalEscapes(String(raw[range]))
    let data = (try? Yams.load(yaml: yaml) as? [String: Any]) ?? [:]
    return (
      (data["name"] as? String).map(TextSanitizer.sanitizeMetadata),
      (data["description"] as? String).map(TextSanitizer.sanitizeMetadata)
    )
  }

  private func unpackArchive(_ data: Data, artifactURL: URL) throws -> [String: Data] {
    let lowerPath = artifactURL.path.lowercased()
    if lowerPath.hasSuffix(".zip") || data.starts(with: [0x50, 0x4b]) {
      return try unpackZip(data)
    }
    return try unpackTarGz(data)
  }

  private func unpackTarGz(_ data: Data) throws -> [String: Data] {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("skill-cli-well-known")
      .appendingPathComponent(UUID().uuidString)
    let archive = tempRoot.appendingPathComponent("artifact.tar.gz")
    let extract = tempRoot.appendingPathComponent("extract")
    try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
    try data.write(to: archive)
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let verboseListing = try ProcessRunner.run(
      "/usr/bin/env", arguments: ["tar", "-tvzf", archive.path]
    ).stdout
      .split(separator: "\n")
      .map(String.init)
      .filter { !$0.isEmpty }
    for line in verboseListing {
      guard let type = line.first, type == "-" || type == "d" else {
        throw CoreError.invalidSource("well-known archive contains unsupported entry type")
      }
    }

    let listing = try ProcessRunner.run("/usr/bin/env", arguments: ["tar", "-tzf", archive.path])
      .stdout
      .split(separator: "\n")
      .map(String.init)
      .filter { !$0.isEmpty && $0 != "." && $0 != "./" }
    guard listing.count <= Self.maxArchiveFiles else {
      throw CoreError.invalidSource("well-known archive has too many files")
    }
    for path in listing {
      _ = try PathSafety.sanitizeSubpath(path)
    }

    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["tar", "-xzf", archive.path, "-C", extract.path])
    return try collectExtractedFiles(from: extract)
  }

  private func unpackZip(_ data: Data) throws -> [String: Data] {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("skill-cli-well-known")
      .appendingPathComponent(UUID().uuidString)
    let archive = tempRoot.appendingPathComponent("artifact.zip")
    let extract = tempRoot.appendingPathComponent("extract")
    try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
    try data.write(to: archive)
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let verboseListing = try ProcessRunner.run(
      "/usr/bin/env", arguments: ["zipinfo", "-l", archive.path]
    ).stdout
      .split(separator: "\n")
      .map(String.init)
    for line in verboseListing where line.first == "-" || line.first == "d" || line.first == "l" {
      guard let type = line.first, type == "-" || type == "d" else {
        throw CoreError.invalidSource("well-known archive contains unsupported entry type")
      }
    }

    let listing = try ProcessRunner.run(
      "/usr/bin/env", arguments: ["unzip", "-Z", "-1", archive.path]
    ).stdout
      .split(separator: "\n")
      .map(String.init)
      .filter { !$0.isEmpty && !$0.hasSuffix("/") }
    guard listing.count <= Self.maxArchiveFiles else {
      throw CoreError.invalidSource("well-known archive has too many files")
    }
    for path in listing {
      _ = try PathSafety.sanitizeSubpath(path)
    }

    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["unzip", "-q", archive.path, "-d", extract.path])
    return try collectExtractedFiles(from: extract)
  }

  private func collectExtractedFiles(from extract: URL) throws -> [String: Data] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: extract,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsPackageDescendants]
      )
    else {
      return [:]
    }

    var totalBytes = 0
    var files: [String: Data] = [:]
    for case let url as URL in enumerator {
      guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        continue
      }
      let relative = PathSafety.relativePath(url.path, to: extract.path)
      _ = try PathSafety.sanitizeSubpath(relative)
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      totalBytes += values.fileSize ?? 0
      guard totalBytes <= Self.maxArchiveUnpackedBytes else {
        throw CoreError.invalidSource("well-known archive exceeds unpacked size limit")
      }
      files[relative.hasPrefix("./") ? String(relative.dropFirst(2)) : relative] = try Data(
        contentsOf: url)
    }
    guard files.keys.contains(where: { $0.lowercased() == "skill.md" }) else {
      throw CoreError.invalidSource("well-known archive has no SKILL.md")
    }
    return files
  }
}

private enum WellKnownIndex: Decodable {
  case v1([EntryV1])
  case v2([EntryV2])

  enum CodingKeys: String, CodingKey {
    case schema = "$schema"
    case skills
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schema = try? container.decode(String.self, forKey: .schema)
    if schema == "https://schemas.agentskills.io/discovery/0.2.0/schema.json" {
      let entries = try container.decode([EntryV2].self, forKey: .skills)
      self = .v2(try entries.filterValid())
    } else if schema == nil {
      let entries = try container.decode([EntryV1].self, forKey: .skills)
      self = .v1(try entries.filterValid())
    } else {
      throw CoreError.invalidSource("unsupported well-known schema")
    }
  }
}

private struct EntryV1: Decodable {
  var name: String
  var description: String
  var files: [String]
}

private struct EntryV2: Decodable {
  var name: String
  var type: String
  var description: String
  var url: String
  var digest: String
}

extension Array where Element == EntryV1 {
  fileprivate func filterValid() throws -> [EntryV1] {
    try map { entry in
      guard isValidSkillName(entry.name), !entry.description.isEmpty, !entry.files.isEmpty else {
        throw CoreError.invalidSource("invalid legacy well-known skill entry")
      }
      guard entry.files.contains(where: { $0.lowercased() == "skill.md" }) else {
        throw CoreError.invalidSource("legacy well-known skill has no SKILL.md")
      }
      for file in entry.files {
        _ = try PathSafety.sanitizeSubpath(file)
      }
      return entry
    }
  }
}

extension Array where Element == EntryV2 {
  fileprivate func filterValid() throws -> [EntryV2] {
    try map { entry in
      guard isValidSkillName(entry.name), !entry.description.isEmpty, !entry.url.isEmpty,
        !entry.digest.isEmpty
      else {
        throw CoreError.invalidSource("invalid v0.2 well-known skill entry")
      }
      return entry
    }
  }
}

private func isValidSkillName(_ name: String) -> Bool {
  guard (1...64).contains(name.count) else { return false }
  guard name.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else { return false }
  return !name.hasPrefix("-") && !name.hasSuffix("-") && !name.contains("--")
}
