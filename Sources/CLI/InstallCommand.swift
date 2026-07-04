import ArgumentParser
import Core

struct Install: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Install skills from resolved state.")

  @Option(name: .long) var scope: CLIScope = .project

  mutating func run() throws {
    let installScope = scope.installScope
    let report = try RuntimeService.installResolvedReport(
      scope: installScope, environment: RuntimeEnvironment())
    let installed = report.installed
    if installed.isEmpty {
      if report.skipped.isEmpty {
        print("No \(cliScopeName(installScope)) skills found in resolved state")
      }
    } else {
      for result in installed {
        print("installed \(result.skill) for \(result.agent.rawValue) at \(result.path)")
      }
    }
    for skipped in report.skipped {
      print(
        "skipped \(skipped.skill) from \(skipped.sourceIdentity): "
          + "\(skipped.reason.rawValue) at \(skipped.path)")
    }
  }
}
