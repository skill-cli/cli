import ArgumentParser
import Darwin
import Foundation

enum BuildInfo {
  static let version = "0.3.1"
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
      Doctor.self, Watch.self,
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
      try validateCommandPath(arguments)
      let options = arguments.prefix { $0 != "--" }
      if options.contains("--version"), options.contains(where: { !$0.hasPrefix("-") }) {
        throw ValidationError("--version is only available on 'skill'")
      }
      command = try SkillCLI.parseAsRoot(arguments)
    } catch {
      let code = SkillCLI.exitCode(for: error)
      if code == .success {
        print(SkillCLI.fullMessage(for: error))
        return
      }
      Terminal.error(
        SkillCLI.message(for: error), remedy: "Run 'skill --help' for usage.")
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
      Terminal.error(
        String(describing: error), remedy: Terminal.failureRemedy(error, command: command))
      Darwin.exit(1)
    }
  }

  private static func validateCommandPath(_ arguments: [String]) throws {
    var parent: any ParsableCommand.Type = SkillCLI.self
    var isHelp = false
    var tokens = arguments.makeIterator()
    while let name = tokens.next() {
      if name == "--" { return }
      if name != "-", name.hasPrefix("-") {
        if name == "--help" || name == "-h" { continue }
        if !name.contains("="), try takesValue(name, command: parent) {
          if tokens.next() == "--" { return }
        }
        continue
      }
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

  // `_dumpHelp()` is outside ArgumentParser's stability guarantee: revalidate the
  // unknown-command tests in ExecutableTests on every parser upgrade, including patches.
  private static func takesValue(_ name: String, command: any ParsableCommand.Type) throws -> Bool {
    let help = try JSONDecoder().decode(CommandHelp.self, from: Data(command._dumpHelp().utf8))
    if help.command.arguments.contains(where: { argument in
      argument.kind == "option"
        && argument.names?.contains {
          ($0.kind == "long" ? "--" : "-") + $0.name == name
        } == true
    }) {
      return true
    }
    if let defaultCommand = command.configuration.defaultSubcommand {
      return try takesValue(name, command: defaultCommand)
    }
    return false
  }
}

private struct CommandHelp: Decodable {
  let command: Definition

  struct Definition: Decodable {
    let arguments: [Argument]
  }

  struct Argument: Decodable {
    let kind: String
    let names: [Name]?
  }

  struct Name: Decodable {
    let kind: String
    let name: String
  }
}
