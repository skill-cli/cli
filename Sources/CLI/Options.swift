import AgentsCore
import ArgumentParser
import Foundation

struct ScopeOptions: ParsableArguments {
  @Option(
    help: "Where state lives: project (./.agent) or user (~/.agents). Default: project.",
    transform: parseScope)
  var scope: InstallScope = .project
}

private func parseScope(_ value: String) throws -> InstallScope {
  guard let scope = InstallScope(rawValue: value) else {
    throw ValidationError("Invalid scope '\(value)'; choose project or user")
  }
  return scope
}

struct AgentOptions: ParsableArguments {
  @Option(
    name: .long,
    help:
      "Limit to this agent: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: all recipients.",
    transform: AgentID.parse)
  var agent: [AgentID] = []

  var recipients: [AgentID]? {
    agent.isEmpty ? nil : Array(Set(agent)).sorted { $0.rawValue < $1.rawValue }
  }
}

struct AddAgentOptions: ParsableArguments {
  @Option(
    name: .long,
    help:
      "Agent to install for: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: the agents already recorded for this skill or source, else the declaration's agents, else codex and claude-code.",
    transform: AgentID.parse)
  var agent: [AgentID] = []

  var recipients: [AgentID]? {
    agent.isEmpty ? nil : Array(Set(agent)).sorted { $0.rawValue < $1.rawValue }
  }
}

struct DiscoveryOptions: ParsableArguments {
  @Option(help: "Search this subdirectory of the source.")
  var path: String?

  @Flag(help: "Search all source directories recursively.")
  var fullDepth = false
}

struct RequirementOptions: ParsableArguments {
  @Option(help: "Follow a Git branch.") var branch: String?
  @Option(help: "Pin a Git revision.") var revision: String?
  @Option(help: "Require an exact semantic version.") var exact: String?
  @Option(help: "Require versions from this version up to the next major.") var from: String?
  @Option(help: "Require versions from this version up to the next minor.")
  var upToNextMinorFrom: String?
  @Option(help: "With --from, set an exclusive upper version bound.") var to: String?

  func validate() throws {
    guard [branch, revision, exact, from, upToNextMinorFrom].compactMap({ $0 }).count <= 1,
      to == nil || from != nil
    else {
      throw ValidationError("Choose one requirement; --to must accompany --from")
    }
    if let requirement {
      do {
        // Core's decoder validates the same requirement forms used by declarations.
        _ = try JSONDecoder().decode(
          SourceRequirement.self, from: JSONEncoder().encode(requirement))
      } catch {
        throw ValidationError("\(error); provide a valid source requirement")
      }
    }
  }

  var requirement: SourceRequirement? {
    if let branch { return .branch(branch) }
    if let revision { return .revision(revision) }
    if let exact { return .exact(exact) }
    if let from { return to.map { .range(from: from, to: $0) } ?? .upToNextMajor(from: from) }
    if let upToNextMinorFrom { return .upToNextMinor(from: upToNextMinorFrom) }
    return nil
  }
}

func parseMode(_ value: String) throws -> InstallMode {
  guard let mode = InstallMode(rawValue: value) else {
    throw ValidationError("Invalid mode '\(value)'; choose link, copy, or edit")
  }
  return mode
}
