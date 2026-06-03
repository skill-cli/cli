import Foundation
import Yams

public struct WatchLedger: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var watches: [WatchRecord]

  public init(schemaVersion: Int = 1, watches: [WatchRecord] = []) {
    self.schemaVersion = schemaVersion
    self.watches = watches
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case watches
  }
}

public struct WatchRecord: Codable, Equatable, Sendable {
  public var watchID: String
  public var source: SourcePin
  public var checkoutPath: String?
  public var watchBaseline: String?
  public var currentHead: String?
  public var watchedPaths: [WatchPathState]
  public var events: [WatchEvent]

  public init(
    watchID: String,
    source: SourcePin,
    checkoutPath: String?,
    watchBaseline: String?,
    currentHead: String?,
    watchedPaths: [WatchPathState],
    events: [WatchEvent] = []
  ) {
    self.watchID = watchID
    self.source = source
    self.checkoutPath = checkoutPath
    self.watchBaseline = watchBaseline
    self.currentHead = currentHead
    self.watchedPaths = watchedPaths
    self.events = events
  }

  enum CodingKeys: String, CodingKey {
    case watchID = "watch_id"
    case source
    case checkoutPath = "checkout_path"
    case watchBaseline = "watch_baseline"
    case currentHead = "current_head"
    case watchedPaths = "watched_paths"
    case events
  }
}

public struct WatchPathState: Codable, Equatable, Sendable {
  public var path: String
  public var lastSeen: String?
  public var tracking: TrackingState
  public var reviewCoverage: ReviewCoverage

  public init(
    path: String, lastSeen: String? = nil, tracking: TrackingState = TrackingState(),
    reviewCoverage: ReviewCoverage = ReviewCoverage()
  ) {
    self.path = path
    self.lastSeen = lastSeen
    self.tracking = tracking
    self.reviewCoverage = reviewCoverage
  }

  enum CodingKeys: String, CodingKey {
    case path
    case lastSeen = "last_seen"
    case tracking
    case reviewCoverage = "review_coverage"
  }
}

public struct TrackingState: Codable, Equatable, Sendable {
  public var lastCheckedCommit: String?
  public var lastCheckedAt: String?

  public init(lastCheckedCommit: String? = nil, lastCheckedAt: String? = nil) {
    self.lastCheckedCommit = lastCheckedCommit
    self.lastCheckedAt = lastCheckedAt
  }

  enum CodingKeys: String, CodingKey {
    case lastCheckedCommit = "last_checked_commit"
    case lastCheckedAt = "last_checked_at"
  }
}

public struct ReviewCoverage: Codable, Equatable, Sendable {
  public var reviewedCommit: String?
  public var reviewedAt: String?
  public var status: String?
  public var outcome: String?
  public var openItems: Int?
  public var granularity: String?

  public init(
    reviewedCommit: String? = nil,
    reviewedAt: String? = nil,
    status: String? = nil,
    outcome: String? = nil,
    openItems: Int? = nil,
    granularity: String? = nil
  ) {
    self.reviewedCommit = reviewedCommit
    self.reviewedAt = reviewedAt
    self.status = status
    self.outcome = outcome
    self.openItems = openItems
    self.granularity = granularity
  }

  enum CodingKeys: String, CodingKey {
    case reviewedCommit = "reviewed_commit"
    case reviewedAt = "reviewed_at"
    case status
    case outcome
    case openItems = "open_items"
    case granularity
  }
}

public struct ChangedFile: Codable, Equatable, Sendable {
  public var path: String
  public var status: String
  public var additions: Int?
  public var deletions: Int?

  public init(path: String, status: String, additions: Int? = nil, deletions: Int? = nil) {
    self.path = path
    self.status = status
    self.additions = additions
    self.deletions = deletions
  }
}

public struct WatchEvent: Codable, Equatable, Sendable {
  public var id: String
  public var type: String
  public var path: String?
  public var commit: String?
  public var note: String?
  public var createdAt: String
  public var baseCommit: String?
  public var headCommit: String?
  public var changedFiles: [ChangedFile]?

  public init(
    id: String = UUID().uuidString,
    type: String,
    path: String? = nil,
    commit: String? = nil,
    note: String? = nil,
    createdAt: String = ISO8601DateFormatter().string(from: Date()),
    baseCommit: String? = nil,
    headCommit: String? = nil,
    changedFiles: [ChangedFile]? = nil
  ) {
    self.id = id
    self.type = type
    self.path = path
    self.commit = commit
    self.note = note
    self.createdAt = createdAt
    self.baseCommit = baseCommit
    self.headCommit = headCommit
    self.changedFiles = changedFiles
  }

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case path
    case commit
    case note
    case createdAt = "created_at"
    case baseCommit = "base_commit"
    case headCommit = "head_commit"
    case changedFiles = "changed_files"
  }
}

public struct ReviewPacket: Codable, Equatable, Sendable {
  public var watchID: String
  public var sourceIdentity: String
  public var path: String
  public var baseCommit: String?
  public var headCommit: String?
  public var comparedCursor: String
  public var checkoutPath: String?
  public var changedFiles: [ChangedFile]
  public var diffCommand: String?

  public init(
    watchID: String,
    sourceIdentity: String,
    path: String,
    baseCommit: String?,
    headCommit: String?,
    comparedCursor: String,
    checkoutPath: String?,
    changedFiles: [ChangedFile],
    diffCommand: String?
  ) {
    self.watchID = watchID
    self.sourceIdentity = sourceIdentity
    self.path = path
    self.baseCommit = baseCommit
    self.headCommit = headCommit
    self.comparedCursor = comparedCursor
    self.checkoutPath = checkoutPath
    self.changedFiles = changedFiles
    self.diffCommand = diffCommand
  }

  enum CodingKeys: String, CodingKey {
    case watchID = "watch_id"
    case sourceIdentity = "source_identity"
    case path
    case baseCommit = "base_commit"
    case headCommit = "head_commit"
    case comparedCursor = "compared_cursor"
    case checkoutPath = "checkout_path"
    case changedFiles = "changed_files"
    case diffCommand = "diff_command"
  }
}

public enum WatchLedgerStore {
  public static func stateURL(environment: RuntimeEnvironment) -> URL {
    environment.projectDirectory.appendingPathComponent(".agent/skills-state.json")
  }

  public static func ledgerURL(environment: RuntimeEnvironment) -> URL {
    stateURL(environment: environment)
  }

  public static func load(environment: RuntimeEnvironment) throws -> WatchLedger {
    let url = stateURL(environment: environment)
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(WatchLedger.self, from: data)
    }

    let legacyURL = legacyLedgerURL(environment: environment)
    guard FileManager.default.fileExists(atPath: legacyURL.path) else { return WatchLedger() }
    let text = try String(contentsOf: legacyURL, encoding: .utf8)
    return try YAMLDecoder().decode(WatchLedger.self, from: text)
  }

  public static func save(_ ledger: WatchLedger, environment: RuntimeEnvironment) throws {
    let url = stateURL(environment: environment)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(ledger)
    var text = String(data: data, encoding: .utf8) ?? "{}"
    if !text.hasSuffix("\n") {
      text.append("\n")
    }
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func legacyLedgerURL(environment: RuntimeEnvironment) -> URL {
    environment.projectDirectory.appendingPathComponent(".agent/watched-skills.yaml")
  }
}

public enum WatchService {
  public static func add(
    source: ResolvedSource,
    path: String,
    requestedID: String? = nil,
    environment: RuntimeEnvironment,
    apply: Bool
  ) throws -> WatchRecord {
    try upsert(
      source: source,
      paths: [path],
      requestedID: requestedID,
      environment: environment,
      replaceRequirement: false,
      apply: apply
    )
  }

  public static func upsert(
    source: ResolvedSource,
    paths: [String],
    requestedID: String? = nil,
    environment: RuntimeEnvironment,
    replaceRequirement: Bool = false,
    apply: Bool
  ) throws -> WatchRecord {
    let safePaths = try unique(paths.map(PathSafety.sanitizeSubpath))
    var ledger = try WatchLedgerStore.load(environment: environment)
    let baseID =
      requestedID
      ?? PathSafety.sanitizeName(source.identity.replacingOccurrences(of: "/", with: "-"))
    let existingIndex = ledger.watches.firstIndex {
      $0.watchID == baseID || $0.source.identity == source.identity
    }

    if let existingIndex {
      var record = ledger.watches[existingIndex]
      let existingRequirement = effectiveRequirement(for: record.source)
      let incomingRequirement = effectiveRequirement(for: source.sourcePin)
      if existingRequirement != incomingRequirement {
        guard replaceRequirement else {
          throw CoreError.invalidSource(
            "source requirement changed for watch '\(record.watchID)'; pass --replace-requirement"
          )
        }
        record.source = source.sourcePin
        record.checkoutPath = source.checkoutURL.path
        record.watchBaseline = source.revision
        record.currentHead = source.revision
        let mergedPaths = unique(record.watchedPaths.map(\.path) + safePaths)
        record.watchedPaths = mergedPaths.map { WatchPathState(path: $0) }
        record.events.append(
          WatchEvent(type: "source_requirement_replaced", commit: source.revision))
      } else {
        record.source = source.sourcePin
        record.checkoutPath = source.checkoutURL.path
        record.currentHead = source.revision ?? record.currentHead
        for safePath in safePaths
        where !record.watchedPaths.contains(where: { $0.path == safePath }) {
          record.watchedPaths.append(WatchPathState(path: safePath))
          record.events.append(
            WatchEvent(type: "path_added", path: safePath, commit: record.currentHead))
        }
        if safePaths.isEmpty {
          record.events.append(WatchEvent(type: "watch_updated", commit: record.currentHead))
        }
      }
      if apply {
        ledger.watches[existingIndex] = record
        try WatchLedgerStore.save(ledger, environment: environment)
      }
      return record
    }

    let watchID = uniqueWatchID(baseID, existing: ledger.watches.map(\.watchID))
    let record = WatchRecord(
      watchID: watchID,
      source: source.sourcePin,
      checkoutPath: source.checkoutURL.path,
      watchBaseline: source.revision,
      currentHead: source.revision,
      watchedPaths: safePaths.map { WatchPathState(path: $0) },
      events: safePaths.map { WatchEvent(type: "watch_added", path: $0, commit: source.revision) }
    )

    if apply {
      ledger.watches.append(record)
      try WatchLedgerStore.save(ledger, environment: environment)
    }

    return record
  }

  public static func remove(watchID: String, environment: RuntimeEnvironment, apply: Bool) throws {
    var ledger = try WatchLedgerStore.load(environment: environment)
    let record = try record(matching: watchID, in: ledger)
    guard ledger.watches.contains(where: { $0.watchID == record.watchID }) else {
      throw CoreError.notFound("watch '\(watchID)'")
    }
    if apply {
      ledger.watches.removeAll { $0.watchID == record.watchID }
      try WatchLedgerStore.save(ledger, environment: environment)
    }
  }

  public static func addPath(
    watchID: String, path: String, environment: RuntimeEnvironment, apply: Bool
  ) throws -> WatchRecord {
    let safePath = try PathSafety.sanitizeSubpath(path)
    var ledger = try WatchLedgerStore.load(environment: environment)
    let matched = try record(matching: watchID, in: ledger)
    guard let index = ledger.watches.firstIndex(where: { $0.watchID == matched.watchID }) else {
      throw CoreError.notFound("watch '\(watchID)'")
    }
    var record = ledger.watches[index]
    if !record.watchedPaths.contains(where: { $0.path == safePath }) {
      record.watchedPaths.append(WatchPathState(path: safePath))
      record.events.append(
        WatchEvent(type: "path_added", path: safePath, commit: record.currentHead))
    }
    if apply {
      ledger.watches[index] = record
      try WatchLedgerStore.save(ledger, environment: environment)
    }
    return record
  }

  public static func removePath(
    watchID: String, path: String, environment: RuntimeEnvironment, apply: Bool
  ) throws -> WatchRecord {
    let safePath = try PathSafety.sanitizeSubpath(path)
    var ledger = try WatchLedgerStore.load(environment: environment)
    let matched = try record(matching: watchID, in: ledger)
    guard let index = ledger.watches.firstIndex(where: { $0.watchID == matched.watchID }) else {
      throw CoreError.notFound("watch '\(watchID)'")
    }
    var record = ledger.watches[index]
    guard record.watchedPaths.contains(where: { $0.path == safePath }) else {
      throw CoreError.notFound("path '\(safePath)' in watch '\(watchID)'")
    }
    record.watchedPaths.removeAll { $0.path == safePath }
    record.events.append(
      WatchEvent(type: "path_removed", path: safePath, commit: record.currentHead))
    if apply {
      ledger.watches[index] = record
      try WatchLedgerStore.save(ledger, environment: environment)
    }
    return record
  }

  public static func refreshWatchedHead(
    watchID: String? = nil, environment: RuntimeEnvironment, apply: Bool
  )
    throws -> [WatchRecord]
  {
    var ledger = try WatchLedgerStore.load(environment: environment)
    let indices = ledger.watches.indices.filter {
      watchID == nil || ledger.watches[$0].watchID == watchID
    }
    guard !indices.isEmpty || watchID == nil else {
      throw CoreError.notFound("watch '\(watchID ?? "")'")
    }

    var results: [WatchRecord] = []
    for index in indices {
      var record = ledger.watches[index]
      if record.source.kind == "remoteSourceControl" {
        let cacheDirectory =
          record.checkoutPath
          .map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
          ?? environment.projectDirectory.appendingPathComponent(".agent/cache/sources")
        if apply {
          let result: Git.CheckoutResult
          if let requirement = record.source.requirement {
            result = try Git.ensureCheckout(
              url: try remoteCloneURL(for: record.source),
              requirement: requirement,
              cacheDirectory: cacheDirectory,
              identity: record.source.identity
            )
          } else {
            let checkout = try Git.ensureCheckout(
              url: try remoteCloneURL(for: record.source),
              ref: record.source.state.ref ?? record.source.state.branch,
              cacheDirectory: cacheDirectory,
              identity: record.source.identity
            )
            result = Git.CheckoutResult(url: checkout)
          }
          record.checkoutPath = result.url.path
          record.currentHead = Git.revision(at: result.url) ?? record.currentHead
          record.source.state.revision = record.currentHead
          if let version = result.selectedVersion {
            record.source.state.version = version
          }
        }
      } else if let checkoutPath = record.checkoutPath {
        let checkout = URL(fileURLWithPath: checkoutPath)
        record.currentHead = Git.revision(at: checkout) ?? record.currentHead
      }
      if apply {
        record.events.append(WatchEvent(type: "watched_head_refreshed", commit: record.currentHead))
      }
      results.append(record)
      if apply {
        ledger.watches[index] = record
      }
    }
    if apply {
      try WatchLedgerStore.save(ledger, environment: environment)
    }
    return results
  }

  public static func diff(
    watchID: String, path: String?, all: Bool = false, environment: RuntimeEnvironment
  ) throws -> [ReviewPacket] {
    let ledger = try WatchLedgerStore.load(environment: environment)
    let record = try record(matching: watchID, in: ledger)
    let states = try selectedPaths(record: record, path: path, all: all, requireChecked: false)
    return states.map { packet(record: record, pathState: $0) }
  }

  public static func check(
    watchID: String, path: String?, all: Bool = false, environment: RuntimeEnvironment, apply: Bool
  ) throws -> [ReviewPacket] {
    var ledger = try WatchLedgerStore.load(environment: environment)
    let matched = try record(matching: watchID, in: ledger)
    guard let index = ledger.watches.firstIndex(where: { $0.watchID == matched.watchID }) else {
      throw CoreError.notFound("watch '\(watchID)'")
    }
    var record = ledger.watches[index]
    let selected = try selectedPaths(record: record, path: path, all: all, requireChecked: false)
    let packets = selected.map { packet(record: record, pathState: $0) }

    for packet in packets {
      if let pathIndex = record.watchedPaths.firstIndex(where: { $0.path == packet.path }) {
        record.watchedPaths[pathIndex].tracking.lastCheckedCommit = packet.headCommit
        record.watchedPaths[pathIndex].tracking.lastCheckedAt = now()
      }
      record.events.append(
        WatchEvent(
          type: "checked",
          path: packet.path,
          commit: packet.headCommit,
          baseCommit: packet.baseCommit,
          headCommit: packet.headCommit,
          changedFiles: packet.changedFiles
        ))
    }

    if apply {
      ledger.watches[index] = record
      try WatchLedgerStore.save(ledger, environment: environment)
    }

    return packets
  }

  public static func seen(
    watchID: String, path: String?, all: Bool = false, commit: String? = nil, note: String? = nil,
    environment: RuntimeEnvironment, apply: Bool
  ) throws -> WatchRecord {
    try updateCursor(
      watchID: watchID,
      path: path,
      all: all,
      commit: commit,
      note: note,
      status: nil,
      outcome: nil,
      openItems: nil,
      granularity: nil,
      eventType: "seen",
      requireChecked: false,
      environment: environment,
      apply: apply
    )
  }

  public static func done(
    watchID: String, path: String?, all: Bool = false, commit: String? = nil, note: String? = nil,
    status: String? = nil, outcome: String? = nil, openItems: Int? = nil,
    granularity: String? = nil,
    environment: RuntimeEnvironment, apply: Bool
  ) throws -> WatchRecord {
    try updateCursor(
      watchID: watchID,
      path: path,
      all: all,
      commit: commit,
      note: note,
      status: status,
      outcome: outcome,
      openItems: openItems,
      granularity: granularity,
      eventType: "done",
      requireChecked: all,
      environment: environment,
      apply: apply
    )
  }

  private static func updateCursor(
    watchID: String,
    path: String?,
    all: Bool,
    commit: String?,
    note: String?,
    status: String?,
    outcome: String?,
    openItems: Int?,
    granularity: String?,
    eventType: String,
    requireChecked: Bool,
    environment: RuntimeEnvironment,
    apply: Bool
  ) throws -> WatchRecord {
    var ledger = try WatchLedgerStore.load(environment: environment)
    let matched = try record(matching: watchID, in: ledger)
    guard let index = ledger.watches.firstIndex(where: { $0.watchID == matched.watchID }) else {
      throw CoreError.notFound("watch '\(watchID)'")
    }
    var record = ledger.watches[index]
    let selected = try selectedPaths(
      record: record, path: path, all: all, requireChecked: requireChecked)
    for state in selected {
      guard let pathIndex = record.watchedPaths.firstIndex(where: { $0.path == state.path }) else {
        continue
      }
      let targetCommit: String?
      if eventType == "done" {
        targetCommit = commit ?? state.tracking.lastCheckedCommit
        guard targetCommit != nil else {
          throw CoreError.notFound(
            "path '\(state.path)' has no checked commit; pass --commit or run review check --watch first"
          )
        }
      } else {
        targetCommit =
          commit ?? state.tracking.lastCheckedCommit ?? record.currentHead ?? record.watchBaseline
      }
      if eventType == "seen" {
        record.watchedPaths[pathIndex].lastSeen = targetCommit
      } else {
        record.watchedPaths[pathIndex].lastSeen = targetCommit
        record.watchedPaths[pathIndex].reviewCoverage.reviewedCommit = targetCommit
        record.watchedPaths[pathIndex].reviewCoverage.reviewedAt = now()
        record.watchedPaths[pathIndex].reviewCoverage.status = status
        record.watchedPaths[pathIndex].reviewCoverage.outcome = outcome
        record.watchedPaths[pathIndex].reviewCoverage.openItems = openItems
        record.watchedPaths[pathIndex].reviewCoverage.granularity = granularity
      }
      record.events.append(
        WatchEvent(type: eventType, path: state.path, commit: targetCommit, note: note))
    }
    if apply {
      ledger.watches[index] = record
      try WatchLedgerStore.save(ledger, environment: environment)
    }
    return record
  }

  public static func record(matching target: String, environment: RuntimeEnvironment) throws
    -> WatchRecord
  {
    try record(matching: target, in: try WatchLedgerStore.load(environment: environment))
  }

  public static func record(matching target: String, in ledger: WatchLedger) throws -> WatchRecord {
    guard let record = ledger.watches.first(where: { watchMatches($0, target: target) }) else {
      throw CoreError.notFound("watch '\(target)'")
    }
    return record
  }

  private static func selectedPaths(
    record: WatchRecord, path: String?, all: Bool, requireChecked: Bool
  ) throws -> [WatchPathState] {
    if all {
      let paths =
        requireChecked
        ? record.watchedPaths.filter { $0.tracking.lastCheckedCommit != nil } : record.watchedPaths
      guard !paths.isEmpty else {
        throw CoreError.notFound("no watched paths match --all")
      }
      return paths
    }
    let safe = try PathSafety.sanitizeSubpath(path ?? record.watchedPaths.first?.path ?? ".")
    guard let state = record.watchedPaths.first(where: { $0.path == safe }) else {
      throw CoreError.notFound("path '\(safe)' in watch '\(record.watchID)'")
    }
    if requireChecked, state.tracking.lastCheckedCommit == nil {
      throw CoreError.notFound("path '\(safe)' has no checked record")
    }
    return [state]
  }

  private static func packet(record: WatchRecord, pathState: WatchPathState) -> ReviewPacket {
    let base = pathState.lastSeen ?? record.watchBaseline
    let head = record.currentHead ?? record.source.state.revision ?? record.watchBaseline
    let checkout = record.checkoutPath.map(URL.init(fileURLWithPath:))
    let changes =
      checkout.flatMap {
        Git.changedFiles(repository: $0, base: base, head: head ?? "", path: pathState.path)
      } ?? []
    let diffCommand: String?
    if let checkoutPath = record.checkoutPath, let head {
      diffCommand = "git -C \(checkoutPath) diff \(base ?? "") \(head) -- \(pathState.path)"
    } else {
      diffCommand = nil
    }
    return ReviewPacket(
      watchID: record.watchID,
      sourceIdentity: record.source.identity,
      path: pathState.path,
      baseCommit: base,
      headCommit: head,
      comparedCursor: pathState.lastSeen == nil ? "watch_baseline" : "last_seen",
      checkoutPath: checkout?.appendingPathComponent(pathState.path == "." ? "" : pathState.path)
        .path,
      changedFiles: changes,
      diffCommand: diffCommand
    )
  }

  private static func uniqueWatchID(_ base: String, existing: [String]) -> String {
    guard existing.contains(base) else { return base }
    var index = 2
    while existing.contains("\(base)-\(index)") {
      index += 1
    }
    return "\(base)-\(index)"
  }

  private static func now() -> String {
    ISO8601DateFormatter().string(from: Date())
  }

  private static func effectiveRequirement(for source: SourcePin) -> SourceRequirement? {
    if let requirement = source.requirement {
      return requirement
    }
    if let branch = source.state.branch {
      return .branch(branch)
    }
    if let ref = source.state.ref {
      return .ref(ref)
    }
    return nil
  }

  private static func watchMatches(_ record: WatchRecord, target: String) -> Bool {
    if record.watchID == target || record.source.identity == target.lowercased() {
      return true
    }
    let sanitized = PathSafety.sanitizeName(target.replacingOccurrences(of: "/", with: "-"))
    if record.watchID == sanitized {
      return true
    }
    if let parsed = try? SourceParser.parse(target),
      SourceParser.identity(for: parsed) == record.source.identity
    {
      return true
    }
    return false
  }

  private static func unique(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.filter { seen.insert($0).inserted }
  }

  private static func remoteCloneURL(for source: SourcePin) throws -> String {
    if source.location.hasPrefix("/") || source.location.hasPrefix("./")
      || source.location.hasPrefix("../")
    {
      return source.location
    }
    let parsed = try SourceParser.parse(source.location)
    return parsed.url
  }
}
