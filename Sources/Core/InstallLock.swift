import Foundation

public struct LockFile: Codable, Equatable, Sendable {
  public var version: Int
  public var originHash: String?
  public var pins: [SourcePin]

  public init(version: Int = 1, originHash: String? = nil, pins: [SourcePin] = []) {
    self.version = version
    self.originHash = originHash
    self.pins = pins
  }
}

public struct SourcePin: Codable, Equatable, Sendable {
  public var identity: String
  public var kind: String
  public var location: String
  public var requirement: SourceRequirement?
  public var state: PinState
  public var skills: [PinnedSkill]

  public init(
    identity: String, kind: String, location: String, requirement: SourceRequirement? = nil,
    state: PinState, skills: [PinnedSkill] = []
  ) {
    self.identity = identity
    self.kind = kind
    self.location = location
    self.requirement = requirement
    self.state = state
    self.skills = skills
  }
}

public struct PinState: Codable, Equatable, Sendable {
  public var revision: String?
  public var branch: String?
  public var ref: String?
  public var version: String?
  public var artifactDigest: String?

  public init(
    revision: String? = nil, branch: String? = nil, ref: String? = nil, version: String? = nil,
    artifactDigest: String? = nil
  ) {
    self.revision = revision
    self.branch = branch
    self.ref = ref
    self.version = version
    self.artifactDigest = artifactDigest
  }
}

public struct PinnedSkill: Codable, Equatable, Sendable {
  public var identity: String
  public var name: String
  public var path: String
  public var contentHash: String
  public var installations: [InstallationPin]

  public init(
    identity: String, name: String, path: String, contentHash: String,
    installations: [InstallationPin]
  ) {
    self.identity = identity
    self.name = name
    self.path = path
    self.contentHash = contentHash
    self.installations = installations
  }
}

public struct InstallationPin: Codable, Equatable, Sendable {
  public var scope: InstallScope
  public var agent: AgentID
  public var mode: InstallMode
  public var path: String

  public init(scope: InstallScope, agent: AgentID, mode: InstallMode, path: String) {
    self.scope = scope
    self.agent = agent
    self.mode = mode
    self.path = path
  }
}

public enum InstallLockStore {
  public static func projectResolvedURL(environment: RuntimeEnvironment) -> URL {
    environment.projectDirectory.appendingPathComponent(".agent/skills.resolved")
  }

  public static func globalResolvedURL(environment: RuntimeEnvironment) -> URL {
    if let stateHome = environment.environment["XDG_STATE_HOME"].flatMap({ $0.isEmpty ? nil : $0 })
    {
      return URL(fileURLWithPath: stateHome).appendingPathComponent("skills/skills.resolved")
    }
    return environment.homeDirectory.appendingPathComponent(".agents/skills.resolved")
  }

  public static func projectLockURL(environment: RuntimeEnvironment) -> URL {
    projectResolvedURL(environment: environment)
  }

  public static func globalLockURL(environment: RuntimeEnvironment) -> URL {
    globalResolvedURL(environment: environment)
  }

  public static func lockURL(scope: InstallScope, environment: RuntimeEnvironment) -> URL {
    scope == .project
      ? projectResolvedURL(environment: environment) : globalResolvedURL(environment: environment)
  }

  public static func load(scope: InstallScope, environment: RuntimeEnvironment) throws
    -> LockFile
  {
    for url in candidateURLs(scope: scope, environment: environment) {
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      if let lock = try? decoder.decode(LockFile.self, from: data), lock.version >= 1 {
        return lock
      }
      if let legacy = try? decoder.decode(LegacyLocalLockFile.self, from: data), legacy.version >= 1
      {
        return legacy.toLockFile()
      }
    }

    return LockFile()
  }

  public static func save(
    _ lock: LockFile, scope: InstallScope, environment: RuntimeEnvironment
  ) throws {
    let url = lockURL(scope: scope, environment: environment)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(normalized(lock))
    var text = String(data: data, encoding: .utf8) ?? "{}"
    if !text.hasSuffix("\n") {
      text.append("\n")
    }
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  public static func merge(
    pinnedSkill: PinnedSkill, into sourcePin: SourcePin, scope: InstallScope,
    environment: RuntimeEnvironment
  ) throws {
    var lock = try load(scope: scope, environment: environment)
    var source = sourcePin
    if let sourceIndex = lock.pins.firstIndex(where: {
      $0.identity == source.identity && $0.location == source.location
    }) {
      source = lock.pins[sourceIndex]
      source.state = sourcePin.state
      source.requirement = sourcePin.requirement
      if let skillIndex = source.skills.firstIndex(where: { $0.identity == pinnedSkill.identity }) {
        var existing = source.skills[skillIndex]
        existing.name = pinnedSkill.name
        existing.path = pinnedSkill.path
        existing.contentHash = pinnedSkill.contentHash
        for installation in pinnedSkill.installations {
          existing.installations.removeAll {
            $0.scope == installation.scope && $0.agent == installation.agent
          }
          existing.installations.append(installation)
        }
        source.skills[skillIndex] = existing
      } else {
        source.skills.append(pinnedSkill)
      }
      lock.pins[sourceIndex] = source
    } else {
      source.skills = [pinnedSkill]
      lock.pins.append(source)
    }
    try save(lock, scope: scope, environment: environment)
  }

  public static func remove(
    skillNames: [String], agents: [AgentID], scope: InstallScope, environment: RuntimeEnvironment
  ) throws {
    var lock = try load(scope: scope, environment: environment)
    let normalizedNames = Set(skillNames.map(PathSafety.sanitizeName))
    for sourceIndex in lock.pins.indices {
      for skillIndex in lock.pins[sourceIndex].skills.indices {
        let shouldRemoveSkill =
          normalizedNames.isEmpty
          || normalizedNames.contains(lock.pins[sourceIndex].skills[skillIndex].identity)
        guard shouldRemoveSkill else { continue }
        lock.pins[sourceIndex].skills[skillIndex].installations.removeAll { installation in
          installation.scope == scope && agents.contains(installation.agent)
        }
      }
      lock.pins[sourceIndex].skills.removeAll { $0.installations.isEmpty }
    }
    lock.pins.removeAll { $0.skills.isEmpty }
    try save(lock, scope: scope, environment: environment)
  }

  private static func normalized(_ lock: LockFile) -> LockFile {
    var result = lock
    result.pins = result.pins.map { pin in
      var source = pin
      source.skills = source.skills.map { skill in
        var pinned = skill
        pinned.installations.sort {
          ($0.scope.rawValue, $0.agent.rawValue, $0.path)
            < ($1.scope.rawValue, $1.agent.rawValue, $1.path)
        }
        return pinned
      }
      source.skills.sort { ($0.identity, $0.path) < ($1.identity, $1.path) }
      return source
    }
    result.pins.sort { ($0.identity, $0.location) < ($1.identity, $1.location) }
    return result
  }

  private static func candidateURLs(scope: InstallScope, environment: RuntimeEnvironment) -> [URL] {
    [
      lockURL(scope: scope, environment: environment),
      legacyLockURL(scope: scope, environment: environment),
    ]
  }

  private static func legacyLockURL(scope: InstallScope, environment: RuntimeEnvironment) -> URL {
    switch scope {
    case .project:
      return environment.projectDirectory.appendingPathComponent(".agent/skills-lock.json")
    case .global:
      if let stateHome = environment.environment["XDG_STATE_HOME"].flatMap({ $0.isEmpty ? nil : $0 }
      ) {
        return URL(fileURLWithPath: stateHome).appendingPathComponent("skills/.skill-lock.json")
      }
      return environment.homeDirectory.appendingPathComponent(".agents/.skill-lock.json")
    }
  }
}

private struct LegacyLocalLockFile: Decodable {
  var version: Int
  var skills: [String: LegacyLocalLockEntry]

  func toLockFile() -> LockFile {
    var sources: [String: SourcePin] = [:]
    for (name, entry) in skills.sorted(by: { $0.key < $1.key }) {
      let parsed = try? SourceParser.parse(
        entry.ref.map { "\(entry.source)#\($0)" } ?? entry.source)
      let identity = parsed.map(SourceParser.identity(for:)) ?? entry.source.lowercased()
      let kind: String
      let location: String
      switch entry.sourceType {
      case "local":
        kind = "localFileSystem"
        location = parsed?.localPath ?? entry.source
      default:
        kind = "remoteSourceControl"
        location = parsed?.url ?? entry.source
      }
      var source =
        sources[identity]
        ?? SourcePin(
          identity: identity,
          kind: kind,
          location: location,
          state: PinState(ref: entry.ref),
          skills: []
        )
      source.skills.append(
        PinnedSkill(
          identity: PathSafety.sanitizeName(name),
          name: name,
          path: entry.skillPath ?? "SKILL.md",
          contentHash: entry.computedHash,
          installations: [
            InstallationPin(
              scope: .project,
              agent: .codex,
              mode: .symlink,
              path: ".agents/skills/\(PathSafety.sanitizeName(name))"
            )
          ]
        ))
      sources[identity] = source
    }
    return LockFile(pins: sources.values.sorted { $0.identity < $1.identity })
  }
}

private struct LegacyLocalLockEntry: Decodable {
  var source: String
  var ref: String?
  var sourceType: String
  var skillPath: String?
  var computedHash: String
}
