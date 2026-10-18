import AgentsCore
import Foundation

struct WatchStatusReport: Encodable {
  let schemaVersion = 1
  let scope: String
  let sources: [WatchSourceReport]

  init(scope: String, statuses: [WatchStatus]) {
    self.scope = scope
    sources = statuses.map { WatchSourceReport($0, includeFiles: false) }
  }
}

struct WatchDiffReport: Encodable {
  let schemaVersion = 1
  let scope: String
  let source: WatchSourceReport

  init(scope: String, status: WatchStatus) {
    self.scope = scope
    source = WatchSourceReport(status, includeFiles: true)
  }
}

struct WatchSourceReport: Encodable {
  let alias: String
  let source: String
  let seen: WatchBaseline
  let current: WatchBaseline
  let commitCount: Int?
  let changes: [WatchChange]

  init(_ status: WatchStatus, includeFiles: Bool) {
    alias = status.alias
    source = status.sourceID
    seen = WatchBaseline(status.seen)
    current = WatchBaseline(status.current)
    commitCount = status.commitCount
    changes = status.changes.map { WatchChange($0, includeFiles: includeFiles) }
  }
}

struct WatchBaseline: Encodable {
  let revision: String?
  let artifacts: [String: String]?

  init(_ seen: WatchSeen) {
    switch seen {
    case .revision(let value):
      revision = value
      artifacts = nil
    case .artifacts(let values):
      revision = nil
      artifacts = values
    }
  }
}

struct WatchChange: Encodable {
  let name: String
  let kind: String
  let change: String
  let oldPath: String?
  let newPath: String?
  let oldDigest: String?
  let newDigest: String?
  let fileCount: Int
  let files: [FileChange]?

  init(_ item: WatchItemChange, includeFiles: Bool) {
    name = item.name
    kind = item.kind.rawValue
    change = item.change.rawValue
    oldPath = item.oldPath
    newPath = item.newPath
    oldDigest = item.oldDigest
    newDigest = item.newDigest
    fileCount = item.fileCount
    files = includeFiles ? item.files.map(FileChange.init) : nil
  }
}
