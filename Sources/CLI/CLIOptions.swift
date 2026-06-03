import ArgumentParser
import Core

func parseAgents(_ values: [String], all: Bool) throws -> [AgentID] {
  if all || values.contains("*") {
    return AgentID.allCases
  }
  if values.isEmpty {
    return [.codex]
  }
  return try values.map(AgentID.parse)
}

enum CLIScope: String, ExpressibleByArgument {
  case project
  case user

  var installScope: InstallScope {
    switch self {
    case .project:
      return .project
    case .user:
      return .global
    }
  }
}

enum CLIMode: String, ExpressibleByArgument {
  case link
  case copy

  var installMode: InstallMode {
    switch self {
    case .link:
      return .symlink
    case .copy:
      return .copy
    }
  }
}

func parseAddAgents(_ values: [String]) throws -> [AgentID] {
  if values.contains("*") {
    return AgentID.allCases
  }
  if !values.isEmpty {
    return try values.map(AgentID.parse)
  }
  return [.codex]
}

func parseSourceRequirement(
  branch: String?,
  revision: String?,
  exact: String?,
  fromVersion: String?,
  upToNextMinorFrom: String?,
  to: String?
) throws -> SourceRequirement? {
  let values = [
    branch.map { ("branch", $0) },
    revision.map { ("revision", $0) },
    exact.map { ("exact", $0) },
    fromVersion.map { ("from", $0) },
    upToNextMinorFrom.map { ("up-to-next-minor-from", $0) },
  ].compactMap { $0 }
  guard values.count <= 1 else {
    throw ValidationError("pass only one source requirement")
  }
  if to != nil, fromVersion == nil {
    throw ValidationError("--to requires --from")
  }
  if to != nil, upToNextMinorFrom != nil {
    throw ValidationError("--to cannot be combined with --up-to-next-minor-from")
  }
  if let branch {
    return .branch(branch)
  }
  if let revision {
    return .revision(revision)
  }
  if let exact {
    return .exact(exact)
  }
  if let fromVersion {
    if let to {
      return .range(from: fromVersion, to: to)
    }
    return .upToNextMajor(from: fromVersion)
  }
  if let upToNextMinorFrom {
    return .upToNextMinor(from: upToNextMinorFrom)
  }
  return nil
}
