import Core
import Foundation

func encodeJSON<T: Encodable>(_ value: T) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(value)
  return String(data: data, encoding: .utf8) ?? "{}"
}

struct InstalledJSON: Encodable {
  var name: String
  var scope: String
  var path: String
  var agents: [String]
  var source: String?
  var installed: Bool
  var watchID: String?
  var reviewedCommit: String?
  var lastCheckedCommit: String?
}

func groupInstalledForJSON(_ installed: [InstalledSkill]) -> [InstalledJSON] {
  var grouped: [String: InstalledJSON] = [:]
  for skill in installed {
    let key = [
      skill.name,
      skill.scope.rawValue,
      skill.path,
      skill.sourceIdentity ?? "",
      skill.isInstalled ? "installed" : "missing",
      skill.watchID ?? "",
    ].joined(separator: "\u{1f}")
    var value =
      grouped[key]
      ?? InstalledJSON(
        name: skill.name,
        scope: cliScopeName(skill.scope),
        path: skill.path,
        agents: [],
        source: skill.sourceIdentity,
        installed: skill.isInstalled,
        watchID: skill.watchID,
        reviewedCommit: skill.reviewedCommit,
        lastCheckedCommit: skill.lastCheckedCommit
      )
    value.agents.append(skill.agent.rawValue)
    value.agents.sort()
    grouped[key] = value
  }
  return grouped.values.sorted { ($0.name, $0.path) < ($1.name, $1.path) }
}

func cliScopeName(_ scope: InstallScope) -> String {
  switch scope {
  case .project:
    return "project"
  case .global:
    return "user"
  }
}

func outputPackets(_ packets: [ReviewPacket], json: Bool, export: String?) throws {
  let output = try encodeJSON(packets)
  if let export {
    try output.write(to: URL(fileURLWithPath: export), atomically: true, encoding: .utf8)
  }
  if json {
    print(output)
    return
  }
  for packet in packets {
    print("watch \(packet.watchID) path \(packet.path)")
    print(
      "base \(packet.baseCommit ?? "unknown") head \(packet.headCommit ?? "unknown") via \(packet.comparedCursor)"
    )
    if let checkoutPath = packet.checkoutPath {
      print("checkout \(checkoutPath)")
    }
    if let diffCommand = packet.diffCommand {
      print("diff \(diffCommand)")
    }
    for file in packet.changedFiles {
      print("\(file.status)\t\(file.path)")
    }
  }
}

func outputWatchStatus(_ record: WatchRecord, history: Bool, json: Bool) throws {
  if json {
    print(try encodeJSON(record))
    return
  }
  print("\(record.watchID) \(record.source.identity)")
  print("baseline \(record.watchBaseline ?? "unknown")")
  print("head \(record.currentHead ?? "unknown")")
  for path in record.watchedPaths {
    print(
      "path \(path.path) checked \(path.tracking.lastCheckedCommit ?? "-") seen \(path.lastSeen ?? "-") reviewed \(path.reviewCoverage.reviewedCommit ?? "-")"
    )
  }
  if history {
    for event in record.events {
      print("event \(event.type) \(event.path ?? "-") \(event.commit ?? "-") \(event.note ?? "")")
    }
  }
}
