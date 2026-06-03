import ArgumentParser
import Core

struct Install: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Install skills from resolved state.")

  @Option(name: .long) var scope: CLIScope = .project

  mutating func run() throws {
    let installScope = scope.installScope
    let installed = try RuntimeService.installResolved(
      scope: installScope, environment: RuntimeEnvironment())
    if installed.isEmpty {
      print("No \(cliScopeName(installScope)) skills found in resolved state")
    } else {
      for result in installed {
        print("installed \(result.skill) for \(result.agent.rawValue) at \(result.path)")
      }
    }
  }
}
