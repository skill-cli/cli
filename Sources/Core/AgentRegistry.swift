import Foundation

public enum AgentID: String, Codable, CaseIterable, Sendable {
  case codex
  case claudeCode = "claude-code"
  case cursor
  case geminiCLI = "gemini-cli"
  case opencode

  public var displayName: String {
    switch self {
    case .codex:
      return "Codex"
    case .claudeCode:
      return "Claude Code"
    case .cursor:
      return "Cursor"
    case .geminiCLI:
      return "Gemini CLI"
    case .opencode:
      return "OpenCode"
    }
  }

  public static func parse(_ raw: String) throws -> AgentID {
    if raw == "claude" || raw == "claude-code" {
      return .claudeCode
    }
    if raw == "gemini" || raw == "gemini-cli" {
      return .geminiCLI
    }
    guard let id = AgentID(rawValue: raw) else {
      throw CoreError.unsupported(
        "unsupported agent '\(raw)'. Supported agents: \(AgentID.supportedList)")
    }
    return id
  }

  public static var supportedList: String {
    AgentID.allCases.map(\.rawValue).joined(separator: ", ")
  }
}

public enum InstallScope: String, Codable, Sendable {
  case project
  case global
}

public enum InstallMode: String, Codable, Sendable {
  case symlink
  case copy
}

public struct RuntimeEnvironment: Sendable {
  public var projectDirectory: URL
  public var homeDirectory: URL
  public var environment: [String: String]

  public init(
    projectDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    homeDirectory: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.projectDirectory = projectDirectory.standardizedFileURL
    let resolvedHome =
      homeDirectory
      ?? environment["HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser
    self.homeDirectory = resolvedHome.standardizedFileURL
    self.environment = environment
  }
}

public enum AgentRegistry {
  public static func cacheDirectory(scope: InstallScope, environment: RuntimeEnvironment) -> URL {
    switch scope {
    case .project:
      return environment.projectDirectory.appendingPathComponent(".agent/cache")
    case .global:
      if let cacheHome = environment.environment["XDG_CACHE_HOME"].flatMap({
        $0.isEmpty ? nil : $0
      }) {
        return URL(fileURLWithPath: cacheHome).appendingPathComponent("skill-cli")
      }
      #if os(macOS)
        return environment.homeDirectory.appendingPathComponent("Library/Caches/skill-cli")
      #else
        return environment.homeDirectory.appendingPathComponent(".cache/skill-cli")
      #endif
    }
  }

  public static func sourceCacheDirectory(scope: InstallScope, environment: RuntimeEnvironment)
    -> URL
  {
    cacheDirectory(scope: scope, environment: environment).appendingPathComponent("sources")
  }

  public static func wellKnownCacheDirectory(scope: InstallScope, environment: RuntimeEnvironment)
    -> URL
  {
    cacheDirectory(scope: scope, environment: environment).appendingPathComponent("well-known")
  }

  public static func canonicalSkillsDirectory(
    scope: InstallScope, environment: RuntimeEnvironment
  ) -> URL {
    switch scope {
    case .project:
      return environment.projectDirectory.appendingPathComponent(".agents/skills")
    case .global:
      return environment.homeDirectory.appendingPathComponent(".agents/skills")
    }
  }

  public static func usesCanonicalSkillsDirectory(
    for agent: AgentID, scope: InstallScope, environment: RuntimeEnvironment
  ) -> Bool {
    switch scope {
    case .project:
      let canonical = canonicalSkillsDirectory(scope: scope, environment: environment)
        .standardizedFileURL.path
      return projectSkillsDirectory(for: agent, environment: environment).standardizedFileURL.path
        == canonical
    case .global:
      return usesUniversalProjectSkillsDirectory(for: agent, environment: environment)
    }
  }

  public static func installSkillsDirectory(
    for agent: AgentID, scope: InstallScope, environment: RuntimeEnvironment
  ) -> URL {
    if usesCanonicalSkillsDirectory(for: agent, scope: scope, environment: environment) {
      return canonicalSkillsDirectory(scope: scope, environment: environment)
    }
    return skillsDirectory(for: agent, scope: scope, environment: environment)
  }

  public static func detectedInstalledAgents(environment: RuntimeEnvironment) -> [AgentID] {
    AgentID.allCases.filter { isInstalled($0, environment: environment) }
  }

  public static func projectSkillsDirectory(for agent: AgentID, environment: RuntimeEnvironment)
    -> URL
  {
    switch agent {
    case .claudeCode:
      return environment.projectDirectory.appendingPathComponent(".claude/skills")
    case .codex, .cursor, .geminiCLI, .opencode:
      return environment.projectDirectory.appendingPathComponent(".agents/skills")
    }
  }

  public static func globalSkillsDirectory(for agent: AgentID, environment: RuntimeEnvironment)
    -> URL
  {
    switch agent {
    case .claudeCode:
      let base = environment.environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
      return URL(
        fileURLWithPath: base ?? environment.homeDirectory.appendingPathComponent(".claude").path
      )
      .appendingPathComponent("skills")
    case .codex:
      let codexHome = environment.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
      return URL(
        fileURLWithPath: codexHome
          ?? environment.homeDirectory.appendingPathComponent(".codex").path
      )
      .appendingPathComponent("skills")
    case .cursor:
      return environment.homeDirectory.appendingPathComponent(".cursor/skills")
    case .geminiCLI:
      return environment.homeDirectory.appendingPathComponent(".gemini/skills")
    case .opencode:
      let configHome =
        environment.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        ?? environment.homeDirectory.appendingPathComponent(".config").path
      return URL(fileURLWithPath: configHome).appendingPathComponent("opencode/skills")
    }
  }

  public static func nativeGlobalScanDirectories(
    for agent: AgentID, environment: RuntimeEnvironment
  ) -> [URL] {
    switch agent {
    case .codex, .cursor, .geminiCLI, .opencode:
      return [
        globalSkillsDirectory(for: agent, environment: environment),
        environment.homeDirectory.appendingPathComponent(".agents/skills"),
      ]
    case .claudeCode:
      return [globalSkillsDirectory(for: agent, environment: environment)]
    }
  }

  public static func projectScanDirectories(
    for agent: AgentID, environment: RuntimeEnvironment
  ) -> [URL] {
    let primary = projectSkillsDirectory(for: agent, environment: environment)
    let additional: [URL]
    switch agent {
    case .geminiCLI:
      additional = [environment.projectDirectory.appendingPathComponent(".gemini/skills")]
    case .codex, .claudeCode, .cursor, .opencode:
      additional = []
    }
    return uniqueDirectories([primary] + additional)
  }

  public static func removalDirectories(
    for agent: AgentID, scope: InstallScope, environment: RuntimeEnvironment
  ) -> [URL] {
    switch scope {
    case .project:
      return projectScanDirectories(for: agent, environment: environment)
    case .global:
      var directories = [globalSkillsDirectory(for: agent, environment: environment)]
      if usesCanonicalSkillsDirectory(for: agent, scope: scope, environment: environment) {
        directories.append(canonicalSkillsDirectory(scope: scope, environment: environment))
      }
      return uniqueDirectories(directories)
    }
  }

  public static func skillsDirectory(
    for agent: AgentID, scope: InstallScope, environment: RuntimeEnvironment
  ) -> URL {
    switch scope {
    case .project:
      return projectSkillsDirectory(for: agent, environment: environment)
    case .global:
      return globalSkillsDirectory(for: agent, environment: environment)
    }
  }

  private static func uniqueDirectories(_ directories: [URL]) -> [URL] {
    var seen = Set<String>()
    return directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
  }

  private static func usesUniversalProjectSkillsDirectory(
    for agent: AgentID, environment: RuntimeEnvironment
  ) -> Bool {
    projectSkillsDirectory(for: agent, environment: environment).standardizedFileURL.path
      == environment.projectDirectory.appendingPathComponent(".agents/skills")
      .standardizedFileURL.path
  }

  private static func isInstalled(_ agent: AgentID, environment: RuntimeEnvironment) -> Bool {
    switch agent {
    case .codex:
      let codexHome = environment.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
      let codexDirectory =
        codexHome.map { URL(fileURLWithPath: $0) }
        ?? environment.homeDirectory.appendingPathComponent(".codex")
      return FileManager.default.fileExists(atPath: codexDirectory.path)
    case .claudeCode:
      let claudeHome = environment.environment["CLAUDE_CONFIG_DIR"].flatMap {
        $0.isEmpty ? nil : $0
      }
      let claudeDirectory =
        claudeHome.map { URL(fileURLWithPath: $0) }
        ?? environment.homeDirectory.appendingPathComponent(".claude")
      return FileManager.default.fileExists(atPath: claudeDirectory.path)
    case .cursor:
      return FileManager.default.fileExists(
        atPath: environment.homeDirectory.appendingPathComponent(".cursor").path)
    case .geminiCLI:
      return FileManager.default.fileExists(
        atPath: environment.homeDirectory.appendingPathComponent(".gemini").path)
    case .opencode:
      let configHome =
        environment.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        ?? environment.homeDirectory.appendingPathComponent(".config").path
      return FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: configHome).appendingPathComponent("opencode").path)
    }
  }
}
