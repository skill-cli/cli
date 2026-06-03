import Foundation
import Yams

public struct Skill: Codable, Equatable, Sendable {
  public var name: String
  public var description: String
  public var path: String
  public var skillFile: String
  public var pluginName: String?

  public init(
    name: String, description: String, path: String, skillFile: String, pluginName: String? = nil
  ) {
    self.name = name
    self.description = description
    self.path = path
    self.skillFile = skillFile
    self.pluginName = pluginName
  }
}

public struct DiscoveryOptions: Sendable {
  public var includeInternal: Bool
  public var fullDepth: Bool

  public init(includeInternal: Bool = false, fullDepth: Bool = false) {
    self.includeInternal = includeInternal
    self.fullDepth = fullDepth
  }
}

public enum Discovery {
  private static let skipDirectories = Set([
    "node_modules", ".git", "dist", "build", "__pycache__", "__pypackages__",
  ])

  public static func parseSkill(at skillFile: URL, includeInternal: Bool = false) throws -> Skill? {
    let content = try String(contentsOf: skillFile, encoding: .utf8)
    let data: [String: Any]
    do {
      data = try parseFrontmatter(content)
    } catch {
      return nil
    }
    guard let name = data["name"] as? String,
      let description = data["description"] as? String,
      !name.isEmpty,
      !description.isEmpty
    else {
      return nil
    }

    if let metadata = data["metadata"] as? [String: Any],
      metadata["internal"] as? Bool == true,
      !includeInternal
    {
      return nil
    }

    let directory = skillFile.deletingLastPathComponent()
    return Skill(
      name: TextSanitizer.sanitizeMetadata(name),
      description: TextSanitizer.sanitizeMetadata(description),
      path: directory.path,
      skillFile: skillFile.path
    )
  }

  public static func discover(
    in base: URL, subpath: String? = nil, options: DiscoveryOptions = DiscoveryOptions()
  ) throws -> [Skill] {
    let searchRoot =
      try subpath.map { try PathSafety.resolvedChild(base: base, subpath: $0) } ?? base
    let pluginGroups = pluginGroupings(base: searchRoot)
    let projectInstalledSkillNames = projectInstalledAgentSkillNames(base: searchRoot)
    var skills: [Skill] = []
    var seen = Set<String>()

    @discardableResult
    func addSkillDirectory(_ directory: URL) throws -> Bool {
      let skillFile = directory.appendingPathComponent("SKILL.md")
      guard FileManager.default.fileExists(atPath: skillFile.path) else { return false }
      guard var skill = try parseSkill(at: skillFile, includeInternal: options.includeInternal)
      else { return false }
      let key = skill.name.lowercased()
      guard !seen.contains(key) else { return true }
      if isProjectInstalledAgentSkill(directory, base: searchRoot),
        projectInstalledSkillNames.contains(PathSafety.sanitizeName(skill.name))
      {
        return false
      }
      skill.pluginName = pluginGroups[directory.standardizedFileURL.path]
      skills.append(skill)
      seen.insert(key)
      return true
    }

    try addSkillDirectory(searchRoot)
    if !skills.isEmpty, !options.fullDepth {
      return skills
    }

    var priorityDirectories = [
      searchRoot,
      searchRoot.appendingPathComponent("skills"),
      searchRoot.appendingPathComponent("skills/.curated"),
      searchRoot.appendingPathComponent("skills/.experimental"),
      searchRoot.appendingPathComponent("skills/.system"),
      searchRoot.appendingPathComponent(".agents/skills"),
      searchRoot.appendingPathComponent(".claude/skills"),
      searchRoot.appendingPathComponent(".codex/skills"),
      searchRoot.appendingPathComponent(".opencode/skills"),
    ]
    priorityDirectories.append(contentsOf: pluginSkillSearchDirectories(base: searchRoot))

    for directory in priorityDirectories {
      let candidates =
        directory.standardizedFileURL.path == searchRoot.standardizedFileURL.path
        ? directSkillDirectories(directory)
        : boundedSkillContainerDirectories(directory)
      for candidate in candidates {
        try addSkillDirectory(candidate)
      }
    }

    if skills.isEmpty || options.fullDepth {
      for directory in recursiveSkillDirectories(under: searchRoot) {
        try addSkillDirectory(directory)
      }
    }

    return skills
  }

  public static func filter(_ skills: [Skill], names: [String]) -> [Skill] {
    guard !names.isEmpty else { return [] }
    let wanted = Set(names.map { $0.lowercased() })
    return skills.filter {
      wanted.contains($0.name.lowercased())
        || wanted.contains(URL(fileURLWithPath: $0.path).lastPathComponent.lowercased())
    }
  }

  private static func parseFrontmatter(_ raw: String) throws -> [String: Any] {
    guard raw.hasPrefix("---") else { return [:] }
    let pattern = #"^---\r?\n([\s\S]*?)\r?\n---\r?\n?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
      let range = Range(match.range(at: 1), in: raw)
    else {
      return [:]
    }
    let yaml = TextSanitizer.stripTerminalEscapes(String(raw[range]))
    return (try Yams.load(yaml: yaml) as? [String: Any]) ?? [:]
  }

  private static func recursiveSkillDirectories(under root: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsPackageDescendants]
      )
    else {
      return []
    }

    var directories: [URL] = []
    for case let url as URL in enumerator {
      if skipDirectories.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        continue
      }
      if FileManager.default.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) {
        directories.append(url)
      }
    }
    return directories
  }

  private static func boundedSkillContainerDirectories(_ container: URL) -> [URL] {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: container,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsPackageDescendants])
    else {
      return []
    }

    var directories: [URL] = []
    for entry in entries.sorted(by: { $0.path < $1.path }) {
      guard isDirectory(entry), !skipDirectories.contains(entry.lastPathComponent) else {
        continue
      }
      if FileManager.default.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path) {
        directories.append(entry)
        continue
      }
      guard
        let nested = try? FileManager.default.contentsOfDirectory(
          at: entry,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsPackageDescendants])
      else {
        continue
      }
      for child in nested.sorted(by: { $0.path < $1.path })
      where isDirectory(child) && !skipDirectories.contains(child.lastPathComponent)
        && FileManager.default.fileExists(atPath: child.appendingPathComponent("SKILL.md").path)
      {
        directories.append(child)
      }
    }
    return directories
  }

  private static func directSkillDirectories(_ container: URL) -> [URL] {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: container,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsPackageDescendants])
    else {
      return []
    }
    return entries.sorted(by: { $0.path < $1.path }).filter {
      isDirectory($0) && !skipDirectories.contains($0.lastPathComponent)
        && FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path)
    }
  }

  private static func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  private static func pluginSkillSearchDirectories(base: URL) -> [URL] {
    var directories: [URL] = []
    let decoder = JSONDecoder()

    let marketplaceURL = base.appendingPathComponent(".claude-plugin/marketplace.json")
    if let data = try? Data(contentsOf: marketplaceURL),
      let manifest = try? decoder.decode(MarketplaceManifest.self, from: data)
    {
      let root = manifest.metadata?.pluginRoot
      if root == nil || root?.hasPrefix("./") == true {
        for plugin in manifest.plugins ?? [] {
          guard plugin.sourceObject == nil else { continue }
          guard isAllowedMarketplaceSource(plugin.source, pluginRoot: root) else { continue }
          let pluginBase = base.appendingPathComponent(root ?? ".").appendingPathComponent(
            plugin.source ?? "."
          ).standardizedFileURL
          guard PathSafety.isContained(pluginBase, in: base) else { continue }
          for skill in plugin.skills ?? [] where skill.hasPrefix("./") {
            let parent = pluginBase.appendingPathComponent(skill).deletingLastPathComponent()
              .standardizedFileURL
            if PathSafety.isContained(parent, in: base) {
              directories.append(parent)
            }
          }
          directories.append(pluginBase.appendingPathComponent("skills"))
        }
      }
    }

    let pluginURL = base.appendingPathComponent(".claude-plugin/plugin.json")
    if let data = try? Data(contentsOf: pluginURL),
      let manifest = try? decoder.decode(PluginManifest.self, from: data)
    {
      for skill in manifest.skills ?? [] where skill.hasPrefix("./") {
        let parent = base.appendingPathComponent(skill).deletingLastPathComponent()
          .standardizedFileURL
        if PathSafety.isContained(parent, in: base) {
          directories.append(parent)
        }
      }
      directories.append(base.appendingPathComponent("skills"))
    }

    return directories
  }

  private static func pluginGroupings(base: URL) -> [String: String] {
    var groups: [String: String] = [:]
    let decoder = JSONDecoder()

    let marketplaceURL = base.appendingPathComponent(".claude-plugin/marketplace.json")
    if let data = try? Data(contentsOf: marketplaceURL),
      let manifest = try? decoder.decode(MarketplaceManifest.self, from: data)
    {
      let root = manifest.metadata?.pluginRoot
      if root == nil || root?.hasPrefix("./") == true {
        for plugin in manifest.plugins ?? [] {
          guard let name = plugin.name else { continue }
          guard plugin.sourceObject == nil else { continue }
          guard isAllowedMarketplaceSource(plugin.source, pluginRoot: root) else { continue }
          let pluginBase = base.appendingPathComponent(root ?? ".").appendingPathComponent(
            plugin.source ?? "."
          ).standardizedFileURL
          guard PathSafety.isContained(pluginBase, in: base) else { continue }
          for skill in plugin.skills ?? [] where skill.hasPrefix("./") {
            let skillDir = pluginBase.appendingPathComponent(skill).standardizedFileURL
            if PathSafety.isContained(skillDir, in: base) {
              groups[skillDir.path] = name
            }
          }
        }
      }
    }

    let pluginURL = base.appendingPathComponent(".claude-plugin/plugin.json")
    if let data = try? Data(contentsOf: pluginURL),
      let manifest = try? decoder.decode(PluginManifest.self, from: data),
      let name = manifest.name
    {
      for skill in manifest.skills ?? [] where skill.hasPrefix("./") {
        let skillDir = base.appendingPathComponent(skill).standardizedFileURL
        if PathSafety.isContained(skillDir, in: base) {
          groups[skillDir.path] = name
        }
      }
    }

    return groups
  }

  private static func isAllowedMarketplaceSource(_ source: String?, pluginRoot: String?) -> Bool {
    guard let source else { return true }
    if source.hasPrefix("./") {
      return true
    }
    return pluginRoot?.hasPrefix("./") == true && !source.hasPrefix("/") && !source.contains("..")
  }

  private static func isProjectInstalledAgentSkill(_ directory: URL, base: URL) -> Bool {
    PathSafety.isContained(
      directory,
      in: base.appendingPathComponent(".agents/skills").standardizedFileURL)
  }

  private static func projectInstalledAgentSkillNames(base: URL) -> Set<String> {
    let environment = RuntimeEnvironment(projectDirectory: base)
    if let lock = try? InstallLockStore.load(scope: .project, environment: environment),
      !lock.pins.isEmpty
    {
      return Set(lock.pins.flatMap(\.skills).map(\.identity))
    }
    let legacyURL = base.appendingPathComponent("skills-lock.json")
    guard let data = try? Data(contentsOf: legacyURL),
      let legacy = try? JSONDecoder().decode(LegacyDiscoveryLock.self, from: data)
    else {
      return []
    }
    return Set(legacy.skills.keys.map(PathSafety.sanitizeName))
  }
}

private struct LegacyDiscoveryLock: Decodable {
  var version: Int
  var skills: [String: LegacyEntry]

  struct LegacyEntry: Decodable {
    var source: String?
    var sourceType: String?
    var skillPath: String?
    var computedHash: String?
  }
}

private struct MarketplaceManifest: Decodable {
  var metadata: Metadata?
  var plugins: [PluginEntry]?

  struct Metadata: Decodable {
    var pluginRoot: String?
  }
}

private struct PluginEntry: Decodable {
  var source: String?
  var sourceObject: SourceObject?
  var skills: [String]?
  var name: String?

  enum CodingKeys: String, CodingKey {
    case source
    case skills
    case name
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    source = try? container.decode(String.self, forKey: .source)
    sourceObject = try? container.decode(SourceObject.self, forKey: .source)
    skills = try? container.decode([String].self, forKey: .skills)
    name = try? container.decode(String.self, forKey: .name)
  }

  struct SourceObject: Decodable {
    var source: String?
    var repo: String?
  }
}

private struct PluginManifest: Decodable {
  var skills: [String]?
  var name: String?
}
