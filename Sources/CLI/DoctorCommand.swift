import ArgumentParser
import Core

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor", abstract: "Diagnose skill install state.")

  @Option(name: .long) var scope: CLIScope = .project
  @Option(name: [.short, .customLong("agent")], parsing: .upToNextOption) var agentValues:
    [String] = []
  @Flag(name: .long) var json = false

  mutating func run() throws {
    let agents = try parseAgents(agentValues, all: agentValues.isEmpty)
    let report = try RuntimeService.doctor(
      scope: scope.installScope,
      agents: agents,
      environment: RuntimeEnvironment()
    )
    if json {
      print(try encodeJSON(report))
      return
    }
    print(report.ok ? "skill doctor: ok" : "skill doctor: issues found")
    for check in report.checks {
      print("\(check.status.rawValue)\t\(check.id)\t\(check.message)")
      if let path = check.path {
        print("path\t\(path)")
      }
      if let hint = check.hint {
        print("hint\t\(hint)")
      }
    }
  }
}
