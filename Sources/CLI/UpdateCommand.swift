import ArgumentParser
import Core

struct Update: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Check or update installed skills.",
    aliases: ["upgrade", "check"])

  @Argument var skills: [String] = []
  @Option(name: .long) var scope: CLIScope = .project
  @Flag(name: .long) var apply = false
  @Flag(name: .long) var fromWatch = false
  @Option(name: [.short, .customLong("agent")], parsing: .upToNextOption) var agentValues:
    [String] = []
  @Option(name: .long) var path: String?
  @Flag(name: .long) var all = false
  @Option(name: .long) var mode: CLIMode = .link

  mutating func run() throws {
    if fromWatch {
      guard let target = skills.first else {
        throw ValidationError("pass a watched source for --from-watch")
      }
      let agents = agentValues.isEmpty ? nil : try parseAgents(agentValues, all: false)
      let installed = try RuntimeService.updateFromWatch(
        target,
        path: path,
        all: all,
        agents: agents,
        scope: scope.installScope,
        mode: mode.installMode,
        environment: RuntimeEnvironment(),
        apply: apply
      )
      if !apply {
        print("would update \(target) from watch")
      }
      for result in installed {
        print("updated \(result.skill) from watch for \(result.agent.rawValue) at \(result.path)")
      }
      return
    }
    let results = try RuntimeService.updateInstalled(
      skillNames: skills, scope: scope.installScope, environment: RuntimeEnvironment(),
      apply: apply)
    for result in results {
      if result.changed {
        print("\(apply ? "updated" : "would update") \(result.skill) from \(result.sourceIdentity)")
      } else {
        print("current \(result.skill)")
      }
    }
  }
}
