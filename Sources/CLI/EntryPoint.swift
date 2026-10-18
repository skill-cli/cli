import ArgumentParser
import Darwin
import Foundation

enum BuildInfo {
  static let version = "0.3.0"
}

struct SkillCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "skill",
    abstract: "Manage agent skills from declared sources.",
    discussion: """
      Examples:
        skill add github.com/owner/skills pdf-forms
        skill list
        skill install
        skill update               Preview what re-resolving would change
        skill update --apply       Write the updates and the new lock
      """,
    subcommands: [
      Add.self, ListSkills.self, Remove.self, UpdateSkills.self, Initialize.self, Install.self,
      Doctor.self,
    ]
  )

  @Flag(help: "Show the version.") var version = false

  func run() throws {
    if version { throw CleanExit.message("skill \(BuildInfo.version)") }
    throw CleanExit.helpRequest(self)
  }
}

@main
enum EntryPoint {
  static func main() {
    var command: any ParsableCommand
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      let options = arguments.prefix { $0 != "--" }
      if options.contains("--version"), options.contains(where: { !$0.hasPrefix("-") }) {
        throw ValidationError("--version is only available on 'skill'")
      }
      try validateHelpPath(arguments)
      command = try SkillCLI.parseAsRoot(arguments)
    } catch {
      let code = SkillCLI.exitCode(for: error)
      if code == .success {
        print(SkillCLI.fullMessage(for: error))
        return
      }
      Terminal.error("\(SkillCLI.message(for: error)); run 'skill --help' for usage.")
      Darwin.exit(64)
    }
    do {
      try command.run()
    } catch {
      // Help requests from a command group are successful parser exits.
      if SkillCLI.exitCode(for: error) == .success {
        print(SkillCLI.fullMessage(for: error))
        return
      }
      if let code = error as? ExitCode {
        Darwin.exit(code.rawValue)
      }
      Terminal.error(Terminal.failureMessage(error))
      Darwin.exit(1)
    }
  }

  private static func validateHelpPath(_ arguments: [String]) throws {
    var parent: any ParsableCommand.Type = SkillCLI.self
    var isHelp = false
    for name in arguments {
      if name.hasPrefix("-") { return }
      if name == "help", !isHelp, !parent.configuration.subcommands.isEmpty {
        isHelp = true
        continue
      }
      guard
        let child = parent.configuration.subcommands.first(where: {
          $0.configuration.commandName == name
        })
      else {
        if !isHelp && parent.configuration.subcommands.isEmpty { return }
        throw ValidationError("Unknown command '\(name)'")
      }
      parent = child
    }
  }
}
