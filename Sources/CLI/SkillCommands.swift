import AgentsCore
import AgentsSkills
import ArgumentParser
import Foundation

struct Add: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Declare and install skills from a source.")

  @Argument(help: "Git URL, local directory, well-known URL, or declared source alias.")
  var source: String
  @Argument(
    help:
      "Skills to add. Omit to add the source's only skill, or to list the choices when it has several."
  )
  var names: [String] = []
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: AddAgentOptions
  @OptionGroup var discovery: DiscoveryOptions
  @OptionGroup var requirements: RequirementOptions
  @Option(
    help: "How to install: link (default), copy, or edit (a live link to a local source).",
    transform: parseMode)
  var mode: InstallMode = .link
  @Flag(help: "Select all skills, including future members on update.") var all = false

  func validate() throws {
    if all && !names.isEmpty {
      throw ValidationError("Use skill names or --all, not both")
    }
    if mode == .edit && requirements.requirement != nil {
      throw ValidationError("--mode edit requires an unpinned local source; remove the requirement")
    }
  }

  func run() throws {
    let outcome = try withRecovery {
      try SkillOperations.add(
        AddOptions(
          source: source, agents: agents.recipients, skillNames: names,
          scope: location.scope, mode: mode, all: all, fullDepth: discovery.fullDepth,
          path: discovery.path, sourceRequirement: requirements.requirement))
    }
    if outcome.installed.isEmpty {
      Terminal.available(outcome.availableSkills)
      Terminal.write("Select names with 'skill add <source> <names...>' or use --all.\n")
    } else {
      Terminal.installed(outcome.installed)
    }
  }
}

struct ListSkills: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List managed skills, or discover skills in a source.")

  @Argument(help: "Inspect this source instead of managed installations.") var source: String?
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: AgentOptions
  @OptionGroup var discovery: DiscoveryOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func validate() throws {
    if source == nil && (discovery.path != nil || discovery.fullDepth) {
      throw ValidationError("--path and --full-depth require a source argument")
    }
  }

  func run() throws {
    if let source {
      let outcome = try withRecovery {
        try SkillOperations.add(
          AddOptions(
            source: source, agents: agents.recipients, scope: location.scope, listOnly: true,
            fullDepth: discovery.fullDepth, path: discovery.path))
      }
      if json {
        try Terminal.json(
          SourceListReport(scope: location.scope.rawValue, outcome: outcome))
      } else {
        Terminal.available(outcome.availableSkills)
      }
    } else {
      let skills = try withRecovery {
        try SkillOperations.listManaged(scope: location.scope, agents: agents.recipients)
      }
      if json {
        try Terminal.json(InstalledListReport(scope: location.scope.rawValue, skills: skills))
      } else if skills.isEmpty {
        Terminal.write("No managed \(location.scope.rawValue) skills.\n")
      } else {
        for skill in skills {
          Terminal.write(
            "\(Terminal.line(skill.name))  \(skill.agent.rawValue)  \(skill.status.rawValue)  \(location.paths.path(skill.path))\n"
          )
        }
      }
    }
  }
}

struct Remove: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove declared skills and their installations.")

  @Argument(help: "Names of managed skills to remove.") var names: [String]
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: AgentOptions

  func validate() throws {
    if names.isEmpty { throw ValidationError("Specify at least one skill name") }
  }

  func run() throws {
    let (removed, previous) = try withRecovery {
      let previous = SkillOutputInventory.read(scope: location.scope, agents: agents.recipients)
      let removed = try SkillOperations.remove(
        skillNames: names, scope: location.scope, agents: agents.recipients)
      return (removed, previous)
    }
    Terminal.removedSkills(removed, previous: previous)
  }
}

struct Initialize: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Create SKILL.md in the current directory or a named subdirectory.")

  @Argument(help: "New skill directory name; omit to use the current directory.") var name: String?

  func run() throws {
    let root = try withRecovery {
      try SkillOperations.initializeSkill(
        named: name, directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
    Terminal.write("Created \(HumanPaths().path(root.appendingPathComponent("SKILL.md").path)).\n")
  }
}
