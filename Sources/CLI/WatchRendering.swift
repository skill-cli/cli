import AgentsCore
import Foundation

extension Terminal {
  static func watchStatus(
    _ statuses: [WatchStatus], paths: HumanPaths = HumanPaths(),
    write: (String) -> Void = Terminal.write
  ) {
    if statuses.isEmpty { write("No watched sources.\n") }
    for status in statuses {
      let summary: String
      switch (status.seen, status.current) {
      case (.revision(let seen), .revision(let current)) where seen != current:
        let count = status.commitCount ?? 0
        summary =
          "\(count) \(count == 1 ? "commit" : "commits") since \(seen.prefix(7)) (now \(current.prefix(7)))"
      case (_, .artifacts) where !status.changes.isEmpty:
        let count = status.changes.count
        summary = "\(count) \(count == 1 ? "artifact" : "artifacts") changed"
      default:
        summary = "up to date"
      }
      write("\(paths.source(status.sourceID))  \(line(summary))\n")
      for item in displayOrder(status.changes) {
        let kind = item.kind == .skill ? "" : " (\(item.kind.rawValue))"
        let count = item.fileCount
        let files = item.change == .changed ? "   \(count) \(count == 1 ? "file" : "files")" : ""
        write("  \(watchChangeLabel(item.change))\(line(item.name))\(kind)\(files)\n")
      }
    }
  }

  static func watchDifferences(_ status: WatchStatus, paths: HumanPaths = HumanPaths()) {
    if status.changes.isEmpty { write("up to date\n") }
    for item in displayOrder(status.changes) {
      let kind = item.kind == .skill ? "" : " (\(item.kind.rawValue))"
      let before: String? =
        if case .revision(let value) = status.seen, item.change != .new { value } else { nil }
      let after: String? =
        if case .revision(let value) = status.current, item.change != .removed { value } else {
          nil
        }
      write(
        "\(watchChangeLabel(item.change).trimmingCharacters(in: .whitespaces))  \(line(item.name))\(kind)  \(paths.source(status.sourceID))  \(HumanItem.pin(revision: before)) -> \(HumanItem.pin(revision: after))\n"
      )
      for file in item.files {
        fileDifference(
          path: item.kind == .skill ? item.name + "/" + file.path : file.path,
          before: file.before.map(HumanFileEntry.init),
          after: file.after.map(HumanFileEntry.init), paths: paths)
      }
    }
  }

  /// New, changed, then removed items; by name, with skills before instructions and artifacts.
  static func displayOrder(_ changes: [WatchItemChange]) -> [WatchItemChange] {
    func rank(_ change: WatchChangeKind) -> Int {
      switch change {
      case .new: 0
      case .changed: 1
      case .removed: 2
      }
    }
    func rank(_ kind: WatchItemKind) -> Int {
      switch kind {
      case .skill: 0
      case .instructions: 1
      case .artifact: 2
      }
    }
    return changes.sorted {
      (rank($0.change), $0.name, rank($0.kind)) < (rank($1.change), $1.name, rank($1.kind))
    }
  }

  private static func watchChangeLabel(_ change: WatchChangeKind) -> String {
    switch change {
    case .new: "+ new      "
    case .changed: "~ changed  "
    case .removed: "- removed  "
    }
  }

}
