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

  @Argument(
    help:
      "Declared source alias, source ID, Git URL, local directory, or well-known URL, optionally followed by selectors such as @branch:main."
  )
  var source: String
  @OptionGroup var location: ScopeOptions
  @OptionGroup var discovery: SourcePathOptions
  @OptionGroup var requirements: RequirementOptions

  func run() throws {
    let change = try withRecovery {
      try SkillOperations.watchOperations().add(
        source, requirement: requirements.requirement, path: discovery.path,
        scope: location.scope)
    }
    let suffix =
      if case .revision(let revision) = change.seen { " from \(revision.prefix(7))" } else { "" }
    Terminal.write("Watching \(location.paths.source(change.sourceID))\(Terminal.line(suffix)).\n")
  }
}

struct WatchStatusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status", abstract: "Show changes since each source was last marked seen.")

  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func run() throws {
    let statuses = try SkillOperations.watchOperations().status(scope: location.scope)
    if json {
      try Terminal.json(WatchStatusReport(scope: location.scope.rawValue, statuses: statuses))
    } else {
      Terminal.watchStatus(statuses, paths: location.paths)
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
    let status = try SkillOperations.watchOperations().diff(
      source, name: name, kind: kind, scope: location.scope)
    if json {
      try Terminal.json(WatchDiffReport(scope: location.scope.rawValue, status: status))
    } else {
      Terminal.watchDifferences(status, paths: location.paths)
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
    let change = try withRecovery {
      try SkillOperations.watchOperations().seen(
        source, revision: revision, scope: location.scope)
    }
    let suffix =
      if case .revision(let revision) = change.seen { " at \(revision.prefix(7))" } else { "" }
    Terminal.write(
      "Marked \(location.paths.source(change.sourceID)) seen\(Terminal.line(suffix)).\n")
  }
}

struct RemoveWatch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Stop watching a source; keep its installations.")

  @Argument(help: "Subscribed source alias, source ID, or location.") var source: String
  @OptionGroup var location: ScopeOptions

  func run() throws {
    let change = try withRecovery {
      try SkillOperations.watchOperations().remove(source, scope: location.scope)
    }
    Terminal.write(
      "Stopped watching \(location.paths.source(change.sourceID)); installations are unchanged.\n")
  }
}

private func parseWatchKind(_ value: String) throws -> WatchItemKind {
  guard let kind = WatchItemKind(rawValue: value) else {
    throw ValidationError("Invalid kind '\(value)'; choose skill, instructions, or artifact")
  }
  return kind
}
