import AgentsCore
import AgentsSkills
import ArgumentParser
import Foundation

struct Watch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "watch", abstract: "Subscribe to sources and inspect upstream changes.",
    subcommands: [
      AddWatch.self, WatchStatusCommand.self, DiffWatch.self, SeenWatch.self, RemoveWatch.self,
    ],
    defaultSubcommand: WatchStatusCommand.self)
}

struct AddWatch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Subscribe to a source without installing its content.")

  @Argument(help: "Declared source alias, source ID, Git URL, local directory, or well-known URL.")
  var source: String
  @OptionGroup var location: ScopeOptions
  @OptionGroup var discovery: SourcePathOptions
  @OptionGroup var requirements: RequirementOptions

  func run() throws {
    let (id, seen) = try withRecovery {
      let environment = RuntimeEnvironment()
      let sources = try StateStore(scope: location.scope, environment: environment)
        .loadDeclaration().sources
      var input = source
      if sources[source] == nil {
        input =
          try sources.keys.sorted().first {
            try sources[$0]?.identity(environment: environment) == source
          } ?? source
      }
      let id = try declaredSourceID(input, sources: sources, environment: environment)
      let seen = try SkillOperations.watchOperations().add(
        input, requirement: requirements.requirement, path: discovery.path,
        scope: location.scope)
      return (id, seen)
    }
    let suffix =
      if case .revision(let revision) = seen { " from \(revision.prefix(7))" } else { "" }
    Terminal.write("Watching \(Terminal.line(id + suffix)).\n")
  }
}

struct WatchStatusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status", abstract: "Show changes since each source was last marked seen.")

  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func run() throws {
    let statuses = try withRecovery {
      try SkillOperations.watchOperations().status(scope: location.scope)
    }
    if json {
      try Terminal.json(WatchStatusReport(scope: location.scope.rawValue, statuses: statuses))
    } else {
      Terminal.watchStatus(statuses)
    }
  }
}

struct DiffWatch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "diff", abstract: "Show before/after content for a watched source or item.")

  @Argument(help: "Subscribed source alias, source ID, or location.") var source: String
  @Argument(help: "Limit changes to this item name.") var name: String?
  @Option(help: "Limit changes to skill, instructions, or artifact.", transform: parseWatchKind)
  var kind: WatchItemKind?
  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func run() throws {
    let status = try withRecovery {
      try SkillOperations.watchOperations().diff(
        source, name: name, kind: kind, scope: location.scope)
    }
    if json {
      try Terminal.json(WatchDiffReport(scope: location.scope.rawValue, status: status))
    } else {
      Terminal.watchDifferences(status)
    }
  }
}

struct SeenWatch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "seen", abstract: "Mark a watched source's current content or Git revision seen.")

  @Argument(help: "Subscribed source alias, source ID, or location.") var source: String
  @Option(help: "Mark this Git revision seen instead of the current head.") var revision: String?
  @OptionGroup var location: ScopeOptions

  func run() throws {
    let (id, seen) = try withRecovery {
      let environment = RuntimeEnvironment()
      let declaration = try StateStore(scope: location.scope, environment: environment)
        .loadDeclaration()
      let id = try watchedSourceID(source, declaration: declaration, environment: environment)
      let seen = try SkillOperations.watchOperations().seen(
        source, revision: revision, scope: location.scope)
      return (id, seen)
    }
    let suffix = if case .revision(let revision) = seen { " at \(revision.prefix(7))" } else { "" }
    Terminal.write("Marked \(Terminal.line(id)) seen\(Terminal.line(suffix)).\n")
  }
}

struct RemoveWatch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Stop watching a source; keep its installations.")

  @Argument(help: "Subscribed source alias, source ID, or location.") var source: String
  @OptionGroup var location: ScopeOptions

  func run() throws {
    let id = try withRecovery {
      let environment = RuntimeEnvironment()
      let declaration = try StateStore(scope: location.scope, environment: environment)
        .loadDeclaration()
      let id = try watchedSourceID(source, declaration: declaration, environment: environment)
      try SkillOperations.watchOperations().remove(source, scope: location.scope)
      return id
    }
    Terminal.write("Stopped watching \(Terminal.line(id)); installations are unchanged.\n")
  }
}

private func parseWatchKind(_ value: String) throws -> WatchItemKind {
  guard let kind = WatchItemKind(rawValue: value) else {
    throw ValidationError("Invalid kind '\(value)'; choose skill, instructions, or artifact")
  }
  return kind
}

// Mutations return a baseline or void. Confirmation identities follow core's
// subscribed-alias, subscribed-ID, then location precedence without fetching.
func watchedSourceID(
  _ input: String, declaration: Declaration, environment: RuntimeEnvironment
) throws -> String {
  let aliases = declaration.watch ?? []
  if !aliases.contains(input) {
    for alias in aliases {
      if try declaration.sources[alias]?.identity(environment: environment) == input {
        return input
      }
    }
  }
  return try declaredSourceID(input, sources: declaration.sources, environment: environment)
}

private func declaredSourceID(
  _ input: String, sources: [String: SourceDeclaration], environment: RuntimeEnvironment
) throws -> String {
  if let source = sources[input] {
    return try source.identity(environment: environment)
  }
  return try SourceParser.identity(
    for: SourceParser.parse(
      input, currentDirectory: environment.projectDirectory,
      homeDirectory: environment.homeDirectory))
}
