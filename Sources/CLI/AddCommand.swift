import ArgumentParser
import Core

struct Add: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Add skills from a source.", aliases: ["a"])

  @Argument var source: String
  @Option(name: .long) var scope: CLIScope = .project
  @Option(name: [.short, .customLong("agent")], parsing: .upToNextOption) var agentValues:
    [String] = []
  @Option(name: [.short, .customLong("skill")], parsing: .upToNextOption) var skillValues:
    [String] = []
  @Option(name: .long) var mode: CLIMode = .link
  @Flag(name: .long) var all = false
  @Flag(name: .long) var fullDepth = false
  @Option(name: .long) var path: String?
  @Flag(name: .long) var watch = false
  @Flag(name: .long) var watchOnly = false
  @Flag(name: .long) var replaceRequirement = false
  @Option(name: .long) var branch: String?
  @Option(name: .long) var revision: String?
  @Option(name: .long) var exact: String?
  @Option(name: .customLong("from")) var fromVersion: String?
  @Option(name: .customLong("up-to-next-minor-from")) var upToNextMinorFrom: String?
  @Option(name: .long) var to: String?

  mutating func run() throws {
    if watch && watchOnly {
      throw ValidationError("--watch and --watch-only are mutually exclusive")
    }
    let environment = RuntimeEnvironment()
    let agents = try parseAddAgents(agentValues)
    let wantsAllSkills = all || skillValues.contains("*")
    let sourceRequirement = try parseSourceRequirement(
      branch: branch,
      revision: revision,
      exact: exact,
      fromVersion: fromVersion,
      upToNextMinorFrom: upToNextMinorFrom,
      to: to
    )
    let outcome = try RuntimeService.add(
      AddOptions(
        source: source,
        agents: agents,
        skillNames: wantsAllSkills ? [] : skillValues,
        scope: scope.installScope,
        mode: mode.installMode,
        listOnly: false,
        all: wantsAllSkills,
        allowMultipleSkills: wantsAllSkills,
        fullDepth: fullDepth,
        path: path,
        sourceRequirement: sourceRequirement,
        watch: watch,
        watchOnly: watchOnly,
        replaceRequirement: replaceRequirement,
        environment: environment
      ))

    for record in outcome.watched {
      for path in record.watchedPaths {
        print("watched \(record.watchID) path \(path.path)")
      }
    }

    for result in outcome.installed {
      print("installed \(result.skill) for \(result.agent.rawValue) at \(result.path)")
    }
  }
}
