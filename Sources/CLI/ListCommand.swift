import ArgumentParser
import Core

struct List: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List managed skills.", aliases: ["ls"])

  @Argument var source: String?
  @Option(name: .long) var scope: CLIScope = .project
  @Option(name: [.short, .customLong("agent")], parsing: .upToNextOption) var agentValues:
    [String] = []
  @Flag(name: .long) var json = false
  @Flag(name: .long) var watch = false
  @Flag(name: .long) var all = false
  @Option(name: [.short, .customLong("skill")], parsing: .upToNextOption) var skillValues:
    [String] = []
  @Flag(name: .long) var fullDepth = false
  @Option(name: .long) var path: String?
  @Option(name: .long) var branch: String?
  @Option(name: .long) var revision: String?
  @Option(name: .long) var exact: String?
  @Option(name: .customLong("from")) var fromVersion: String?
  @Option(name: .customLong("up-to-next-minor-from")) var upToNextMinorFrom: String?
  @Option(name: .long) var to: String?

  mutating func run() throws {
    if let source {
      guard !watch else {
        throw ValidationError("list <source> cannot be combined with --watch")
      }
      guard !all else {
        throw ValidationError("list <source> cannot be combined with --all")
      }
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
          agents: [.codex],
          skillNames: skillValues,
          scope: .project,
          mode: .symlink,
          listOnly: true,
          all: false,
          allowMultipleSkills: true,
          fullDepth: fullDepth,
          path: path,
          sourceRequirement: sourceRequirement,
          watch: false,
          watchOnly: false,
          replaceRequirement: false,
          environment: RuntimeEnvironment()
        ))
      if json {
        print(try encodeJSON(outcome.availableSkills))
        return
      }
      for skill in outcome.availableSkills {
        print("\(skill.name)\t\(skill.description)")
      }
      return
    }
    if watch {
      guard !all else {
        throw ValidationError("list --watch cannot be combined with --all")
      }
      let ledger = try WatchLedgerStore.load(environment: RuntimeEnvironment())
      if json {
        print(try encodeJSON(ledger.watches))
        return
      }
      for watch in ledger.watches {
        print("\(watch.watchID)\t\(watch.source.identity)\t\(watch.currentHead ?? "unknown")")
      }
      return
    }
    let agents = try parseAgents(agentValues, all: agentValues.isEmpty)
    let environment = RuntimeEnvironment()
    let installed: [InstalledSkill]
    if all {
      installed = try RuntimeService.listInstalled(
        scope: scope.installScope, agents: agents, environment: environment)
    } else {
      installed = try RuntimeService.listManaged(
        scope: scope.installScope, agents: agents, environment: environment)
    }
    let filteredInstalled = filterInstalled(installed, names: skillValues)
    if json {
      print(try encodeJSON(groupInstalledForJSON(filteredInstalled)))
      return
    }
    if filteredInstalled.isEmpty {
      if !skillValues.isEmpty {
        print("No matching skills found")
        return
      }
      if scope == .user {
        print("No user skills found")
      } else {
        print("No project skills found")
        print("Try listing user skills with --scope user")
      }
      return
    }
    print(scope == .user ? "User Skills" : "Project Skills")
    for skill in filteredInstalled {
      let status = skill.isInstalled ? "installed" : "missing"
      let source = skill.sourceIdentity.map { "\t\($0)" } ?? ""
      print("\(skill.name)\t\(skill.agent.rawValue)\t\(status)\t\(skill.path)\(source)")
    }
  }
}

private func filterInstalled(_ installed: [InstalledSkill], names: [String]) -> [InstalledSkill] {
  guard !names.isEmpty else { return installed }
  let selected = Set(names.map(PathSafety.sanitizeName))
  return installed.filter { selected.contains(PathSafety.sanitizeName($0.name)) }
}
