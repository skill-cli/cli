import AgentsCore
import AgentsSkills
import ArgumentParser
import Foundation

struct Install: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Restore skills using exact pins and recipients from the lock.")

  @OptionGroup var location: ScopeOptions

  func run() throws {
    let report = try withRecovery {
      try SkillOperations.installResolvedReport(scope: location.scope)
    }
    if report.installed.isEmpty {
      Terminal.write("No locked skills to restore.\n")
    } else {
      Terminal.installed(report.installed)
    }
  }
}

struct UpdateOptions: ParsableArguments {
  @OptionGroup var location: ScopeOptions
  @Flag(help: "Show differences, then replace installations and update the lock.") var apply = false
  @Flag(help: "Print the versioned JSON preview; cannot be used with --apply.") var json = false

  func validate() throws {
    if json && apply { throw ValidationError("--json is for previews; remove --apply or --json") }
  }

  func run(names: [String] = []) throws {
    let results = try withRecovery {
      try SkillOperations.updateInstalled(
        scope: location.scope, skillNames: names, apply: apply,
        beforeApply: { Terminal.differences($0) })
    }
    if json {
      try Terminal.json(UpdateReport(scope: location.scope.rawValue, results: results))
    } else if apply {
      Terminal.write("Applied skill update.\n")
    } else {
      Terminal.differences(results)
      if results.contains(where: \.changed) {
        Terminal.write("Preview only. Run again with --apply to write these changes.\n")
      }
    }
  }
}

struct UpdateSkills: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Preview or apply updates to selected or all declared skills.")
  @Argument(help: "Limit the update to these skill names.") var names: [String] = []
  @OptionGroup var options: UpdateOptions

  func run() throws { try options.run(names: names) }
}

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Compare skill installations with the lock and report problems.")
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: AgentOptions
  @Option(
    name: .long, parsing: .upToNextOption,
    help: "Audit these project directories read-only. Repeat for several.")
  var root: [String] = []
  @Flag(help: "Print the versioned JSON report.") var json = false

  func validate() throws {
    if !root.isEmpty && location.scope == .user {
      throw ValidationError("--root audits projects; use --scope project or omit --root")
    }
  }

  func run() throws {
    let environment = RuntimeEnvironment()
    let directories = root.isEmpty ? [environment.projectDirectory.path] : root
    var reports: [DoctorRoot] = []
    for directory in directories {
      let project = URL(fileURLWithPath: directory, relativeTo: environment.projectDirectory)
        .standardizedFileURL
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        throw CoreError.notFound("project directory \(project.path); provide an existing --root")
      }
      let report = try withRecovery {
        try SkillOperations.doctor(
          scope: location.scope, agents: agents.recipients,
          environment: RuntimeEnvironment(
            projectDirectory: project, homeDirectory: environment.homeDirectory,
            environment: environment.environment))
      }
      reports.append(
        DoctorRoot(
          root: location.scope == .user ? environment.homeDirectory.path : project.path,
          scope: location.scope.rawValue, report: report))
    }
    let report = DoctorOutput(roots: reports)
    if json {
      try Terminal.json(report)
    } else {
      for root in reports {
        Terminal.write("\(Terminal.line(root.root)) (\(root.scope))\n")
        if root.checks.isEmpty { Terminal.write("  No problems found.\n") }
        for check in root.checks {
          Terminal.write("  \(check.status): \(Terminal.line(check.message))\n")
        }
      }
    }
    if !report.ok { throw ExitCode.failure }
  }
}
