import ArgumentParser
import Core

struct Remove: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove installed skills.", aliases: ["rm", "r"])

  @Argument var positionalSkills: [String] = []
  @Option(name: .long) var scope: CLIScope = .project
  @Option(name: [.short, .customLong("agent")], parsing: .upToNextOption) var agentValues:
    [String] = []
  @Option(name: [.customShort("s"), .customLong("skill")], parsing: .upToNextOption)
  var optionSkills: [String] = []
  @Flag(name: .long) var all = false
  @Flag(name: .long) var watch = false
  @Option(name: .long) var path: String?

  mutating func run() throws {
    let names = positionalSkills + optionSkills
    if watch {
      guard let target = names.first else {
        throw ValidationError("pass a watch source or watch id")
      }
      if let path {
        let record = try WatchService.removePath(
          watchID: target, path: path, environment: RuntimeEnvironment(), apply: true)
        print("removed path \(path) from \(record.watchID)")
      } else {
        let record = try WatchService.record(matching: target, environment: RuntimeEnvironment())
        try WatchService.remove(
          watchID: record.watchID, environment: RuntimeEnvironment(), apply: true)
        print("removed \(record.watchID)")
      }
      return
    }
    let agents = try parseAgents(agentValues, all: agentValues.isEmpty)
    let environment = RuntimeEnvironment()
    let installed = try RuntimeService.listInstalled(
      scope: scope.installScope, agents: agents, environment: environment)
    if installed.isEmpty {
      print("No skills found to remove")
      return
    }
    guard all || !names.isEmpty else {
      throw ValidationError("pass one or more skills, --skill, or --all")
    }
    if !all {
      let available = Set(installed.map { PathSafety.sanitizeName($0.name) })
      let missing = names.filter { !available.contains(PathSafety.sanitizeName($0)) }
      if !missing.isEmpty {
        print("No matching skills found")
        return
      }
      print("Removing \(names.joined(separator: ", "))")
    }
    let removed = try RuntimeService.remove(
      skillNames: all ? [] : names, scope: scope.installScope, agents: agents,
      environment: environment)
    for path in removed {
      print("removed \(path)")
    }
  }
}
