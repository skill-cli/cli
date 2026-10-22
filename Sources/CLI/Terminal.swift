import AgentsCore
import AgentsSkills
import ArgumentParser
import Foundation

func withRecovery<T>(
  report: (String) -> Void = Terminal.notice,
  _ operation: () throws -> T
) throws -> T {
  do {
    return try operation()
  } catch CoreError.transactionRecovered(let path) {
    report("Recovered interrupted transaction at \(HumanPaths().path(path)); retrying once.")
    return try operation()
  }
}

enum Terminal {
  // Write directly so beforeApply output reaches stdout before core replaces files.
  static func write(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }

  static func notice(_ text: String) {
    FileHandle.standardError.write(Data("\(line(text))\n".utf8))
  }

  static func error(_ message: String, remedy: String) {
    FileHandle.standardError.write(Data(formatError(message, remedy: remedy).utf8))
  }

  static func formatError(_ message: String, remedy: String) -> String {
    func punctuate(_ text: String) -> String {
      var text = text
      if let last = text.lastIndex(where: { !" \t\r".contains($0) }),
        !".!?。！？".contains(text[last])
      {
        text.insert(".", at: text.index(after: last))
      }
      return text
    }
    var lines = message.components(separatedBy: "\n")
    while let last = lines.last, last.allSatisfy({ " \t\r".contains($0) }) {
      lines.removeLast()
    }
    if !lines.isEmpty { lines[lines.count - 1] = punctuate(lines[lines.count - 1]) }
    let error = lines.enumerated().map { index, text in
      (index == 0 ? "Error: " : "  ") + line(text)
    }.joined(separator: "\n")
    var remedy = remedy.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n"))
    if let first = remedy.first { remedy = first.uppercased() + remedy.dropFirst() }
    return (error.isEmpty ? "Error:" : error) + "\n  " + line(punctuate(remedy)) + "\n"
  }

  static func line(_ text: String) -> String {
    text.unicodeScalars.map { scalar in
      switch scalar {
      case "\t": return "\t"
      case "\n": return "\\n"
      case "\r": return "\\r"
      default:
        guard CharacterSet.controlCharacters.contains(scalar) else { return String(scalar) }
        let hex = String(scalar.value, radix: 16)
        return scalar.value <= 0xff
          ? "\\x" + String(repeating: "0", count: 2 - hex.count) + hex
          : "\\u{" + hex + "}"
      }
    }.joined()
  }

  static func failureRemedy(_ error: Error, command: any ParsableCommand) -> String {
    let action: String
    switch error {
    case CoreError.transactionRecovered:
      action = "retry the command after other writers finish"
    case CoreError.notFound(let message) where message.hasPrefix("source is not subscribed:"):
      action = "run 'skill watch' to list subscriptions"
    case CoreError.invalidSource("expected a local path or repository URL")
    where command is DiffWatch || command is SeenWatch || command is RemoveWatch:
      action = "run 'skill watch' to list subscriptions"
    case CoreError.invalidSource("invalid watch revision"):
      action = "provide a Git revision that resolves to a commit in the watched source"
    case CoreError.invalidSource("well-known subscriptions do not accept Git revisions"):
      action = "omit --revision to mark the current index seen"
    case let error as GitError:
      switch error.operation {
      case .resolveRevision:
        action = "provide a Git revision that resolves to a commit in the watched source"
      default:
        action = "check Git access and the source location"
      }
    case CoreError.invalidSource, CoreError.notFound:
      action = "check the source, names, and paths"
    case CoreError.unsafePath:
      action = "use a path within the source directory"
    case CoreError.invalidSkill:
      action = "check SKILL.md and existing installations with 'skill doctor'"
    case CoreError.invalidState:
      action = "check the scope's agents.json, agents.resolved, and recovery journal"
    case CoreError.commandFailed:
      action = "check the command arguments and filesystem permissions"
    default:
      action = "check the command arguments and filesystem permissions"
    }
    return action
  }

  static func json(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
  }

  static func available(_ skills: [Skill]) {
    if skills.isEmpty { write("No skills found in source.\n") }
    for skill in skills.sorted(by: { $0.name < $1.name }) {
      write("\(line(skill.name))  \(line(skill.description))\n")
    }
  }

  static func installed(_ results: [InstallResult]) {
    for name in Set(results.map(\.skill)).sorted() {
      let installs = results.filter { $0.skill == name }
      let modes = Set(installs.map { $0.mode.rawValue }).sorted()
      let recipients = installs.sorted { $0.agent.rawValue < $1.agent.rawValue }.map {
        $0.agent.rawValue + (modes.count > 1 ? " (\($0.mode.rawValue))" : "")
      }.joined(separator: ", ")
      let mode = modes.count == 1 ? " (\(modes[0]))" : ""
      write("Installed \(line(name)) for \(recipients)\(mode).\n")
    }
  }

  static func skillItems(_ results: [UpdateResult]) -> [HumanItem] {
    results.filter(\.changed).map { result in
      return HumanItem(
        name: result.skill, source: result.sourceIdentity,
        existed: result.membership.contains { $0.before != .absent },
        exists: result.membership.contains { $0.after != .absent },
        oldRevision: result.oldRevision, newRevision: result.newRevision,
        oldVersion: result.oldVersion, newVersion: result.newVersion,
        sameContent: result.oldHash != nil && result.oldHash == result.newHash,
        otherChanges: result.membership.contains { $0.before != $0.after }
          || result.changes.contains {
            if case .symbolicLink = $0.before, case .symbolicLink = $0.after { return false }
            return true
          })
    }
  }

  static func differences(
    _ results: [UpdateResult], paths: HumanPaths = HumanPaths()
  ) {
    let items = HumanItem.ordered(skillItems(results))
    if results.contains(where: \.lockMissing) {
      write("Lock missing: prior skill membership is unrecorded.\n")
    }
    if items.isEmpty { write("No skill changes.\n") }
    for item in items {
      write(item.render(paths: paths))
      for result in results where result.skill == item.name && result.sourceIdentity == item.source
      {
        skillMembership(result.membership, paths: paths)
        skillFileDifferences(result, paths: paths)
      }
    }
  }

  static func recipients(_ agents: [AgentID]) -> String {
    agents.isEmpty ? "none" : agents.map(\.rawValue).sorted().joined(separator: ", ")
  }

}
