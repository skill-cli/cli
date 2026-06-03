import ArgumentParser
import Core

struct Status: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status", abstract: "Show managed source status.")

  @Argument var source: String
  @Flag(name: .long) var watch = false
  @Flag(name: .long) var history = false
  @Flag(name: .long) var json = false

  mutating func run() throws {
    guard watch else {
      throw ValidationError("status currently requires --watch")
    }
    let record = try refreshWatchMatching(source, environment: RuntimeEnvironment())
    try outputWatchStatus(record, history: history, json: json)
  }
}

struct Diff: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "diff", abstract: "Print a watch-scoped review diff.")

  @Argument var source: String
  @Flag(name: .long) var watch = false
  @Option(name: .long) var path: String?
  @Flag(name: .long) var all = false
  @Flag(name: .long) var json = false
  @Option(name: .long) var export: String?

  mutating func run() throws {
    guard watch else {
      throw ValidationError("diff currently requires --watch")
    }
    let environment = RuntimeEnvironment()
    let record = try refreshWatchMatching(source, environment: environment)
    let packets = try WatchService.diff(
      watchID: record.watchID, path: path, all: all, environment: environment)
    try outputPackets(packets, json: json, export: export)
  }
}

struct Review: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "review",
    abstract: "Move watch review cursors.",
    subcommands: [ReviewCheck.self, ReviewSeen.self, ReviewDone.self])
}

struct ReviewCheck: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check", abstract: "Print and record a checked watch handoff.")

  @Argument var source: String
  @Flag(name: .long) var watch = false
  @Option(name: .long) var path: String?
  @Flag(name: .long) var all = false
  @Flag(name: .long) var json = false
  @Option(name: .long) var export: String?

  mutating func run() throws {
    guard watch else {
      throw ValidationError("review check currently requires --watch")
    }
    let environment = RuntimeEnvironment()
    let record = try refreshWatchMatching(source, environment: environment)
    let packets = try WatchService.check(
      watchID: record.watchID, path: path, all: all, environment: environment, apply: true)
    try outputPackets(packets, json: json, export: export)
  }
}

struct ReviewSeen: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "seen", abstract: "Mark a watched path seen without review coverage.")

  @Argument var source: String
  @Flag(name: .long) var watch = false
  @Option(name: .long) var path: String?
  @Flag(name: .long) var all = false
  @Option(name: .long) var commit: String?
  @Option(name: .long) var note: String?

  mutating func run() throws {
    guard watch else {
      throw ValidationError("review seen currently requires --watch")
    }
    let environment = RuntimeEnvironment()
    let refreshed = try refreshWatchMatching(source, environment: environment)
    let record = try WatchService.seen(
      watchID: refreshed.watchID, path: path, all: all, commit: commit, note: note,
      environment: environment, apply: true)
    print("marked seen \(record.watchID)")
  }
}

struct ReviewDone: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "done", abstract: "Record external review closeout for a watched path.")

  @Argument var source: String
  @Flag(name: .long) var watch = false
  @Option(name: .long) var path: String?
  @Flag(name: .long) var all = false
  @Option(name: .long) var commit: String?
  @Option(name: .long) var note: String?
  @Option(name: .long) var status: String?
  @Option(name: .long) var outcome: String?
  @Option(name: .long) var openItems: Int?
  @Option(name: .long) var granularity: String?

  mutating func run() throws {
    guard watch else {
      throw ValidationError("review done currently requires --watch")
    }
    let environment = RuntimeEnvironment()
    let refreshed = try refreshWatchMatching(source, environment: environment)
    let record = try WatchService.done(
      watchID: refreshed.watchID, path: path, all: all, commit: commit, note: note, status: status,
      outcome: outcome, openItems: openItems, granularity: granularity,
      environment: environment, apply: true)
    print("recorded done \(record.watchID)")
  }
}

private func refreshWatchMatching(_ source: String, environment: RuntimeEnvironment) throws
  -> WatchRecord
{
  let matched = try WatchService.record(matching: source, environment: environment)
  return try WatchService.refreshWatchedHead(
    watchID: matched.watchID, environment: environment, apply: true
  )
  .first ?? matched
}
