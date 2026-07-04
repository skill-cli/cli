import ArgumentParser
import Core
import Darwin
import Foundation

struct RootCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "skill",
    abstract: "Native agent skill CLI.",
    discussion: """
      Manage Skills:
        skill add <source>
        skill install
        skill add <source> --watch
        skill add <source> --watch-only
        skill list
        skill doctor
        skill list --watch
        skill status <source> --watch
        skill diff <source> --watch --path <path>
        skill review check|seen|done <source> --watch --path <path>
        skill update <source> --from-watch
        skill update
        skill init [name]

      List Options:
        --scope <project|user>
        -a, --agent <agent>
        --json
        --all

      Examples:
        skill list
        skill list --all
        skill list --scope user
        skill list --agent claude-code
      """,
    version: BuildInfo.version,
    subcommands: [
      Add.self,
      Install.self,
      List.self,
      Doctor.self,
      Remove.self,
      Update.self,
      Status.self,
      Diff.self,
      Review.self,
      Init.self,
    ]
  )

  mutating func run() {
    print("skill \(BuildInfo.version)")
    print("Manage Skills:")
    print("  skill add <source>")
    print("  skill install")
    print("  skill add <source> --watch")
    print("  skill add <source> --watch-only")
    print("  skill list")
    print("  skill doctor")
    print("  skill list --watch")
    print("  skill status <source> --watch")
    print("  skill diff <source> --watch --path <path>")
    print("  skill review check|seen|done <source> --watch --path <path>")
    print("  skill update <source> --from-watch")
    print("  skill update")
    print("  skill init [name]")
  }
}

@main
enum SkillsEntryPoint {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if invalidInstallSourceArgument(in: arguments) != nil {
      let message = """
        Error: skill install does not accept a source. Use 'skill add <source>' to add one.
        Usage: skill install
          See 'skill install --help' for more information.

        """
      FileHandle.standardError.write(Data(message.utf8))
      Darwin.exit(64)
    }
    if let blocked = blockedTopLevelCommand(in: arguments) {
      let message = """
        Error: Unknown command '\(blocked)'
        Usage: skill <subcommand>
          See 'skill --help' for more information.

        """
      FileHandle.standardError.write(Data(message.utf8))
      Darwin.exit(64)
    }
    RootCommand.main()
  }
}

private let registeredTopLevelCommands: Set<String> = [
  "a",
  "add",
  "check",
  "diff",
  "doctor",
  "init",
  "install",
  "list",
  "ls",
  "r",
  "remove",
  "review",
  "rm",
  "status",
  "update",
  "upgrade",
]

func blockedTopLevelCommand(in arguments: [String]) -> String? {
  guard let first = arguments.first else {
    return nil
  }
  if !first.hasPrefix("-"), !registeredTopLevelCommands.contains(first), first != "help" {
    return first
  }
  if first == "help", arguments.count > 1, !registeredTopLevelCommands.contains(arguments[1]) {
    return arguments[1]
  }
  return nil
}

private func invalidInstallSourceArgument(in arguments: [String]) -> String? {
  guard arguments.first == "install", arguments.count > 1 else {
    return nil
  }
  let next = arguments[1]
  return next.hasPrefix("-") ? nil : next
}
