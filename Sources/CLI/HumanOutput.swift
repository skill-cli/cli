import AgentsCore
import AgentsSkills
import Foundation

struct HumanPaths {
  let scope: InstallScope
  let environment: RuntimeEnvironment

  init(scope: InstallScope = .project, environment: RuntimeEnvironment = RuntimeEnvironment()) {
    self.scope = scope
    self.environment = environment
  }

  func path(_ value: String) -> String {
    guard value.hasPrefix("/") else { return Terminal.line(value) }
    let path = URL(fileURLWithPath: value).standardizedFileURL.path
    if scope == .project, let relative = relative(path, to: environment.projectDirectory) {
      return Terminal.line(relative.isEmpty ? "." : relative)
    }
    return Terminal.line(homePath(path))
  }

  func source(_ value: String) -> String {
    guard value.hasPrefix("local:/") else { return Terminal.line(value) }
    return "local:" + Terminal.line(homePath(String(value.dropFirst(6))))
  }

  private func homePath(_ path: String) -> String {
    guard let relative = relative(path, to: environment.homeDirectory) else { return path }
    return relative.isEmpty ? "~" : "~/" + relative
  }

  private func relative(_ path: String, to root: URL) -> String? {
    let root = root.standardizedFileURL.path
    if path == root { return "" }
    let prefix = root == "/" ? "/" : root + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
  }
}

struct HumanItem {
  enum Change: Int {
    case new, changed, repinned, removed

    var label: String {
      switch self {
      case .new: "+ new"
      case .changed: "~ changed"
      case .repinned: "= repinned"
      case .removed: "- removed"
      }
    }
  }

  let name: String
  let source: String
  let change: Change
  let before: String
  let after: String

  init(
    name: String, source: String,
    existed: Bool, exists: Bool, oldRevision: String?, newRevision: String?,
    sameContent: Bool, otherChanges: Bool = false
  ) {
    self.name = name
    self.source = source
    before = Self.pin(revision: oldRevision)
    after = Self.pin(revision: newRevision)
    if !existed {
      change = .new
    } else if !exists {
      change = .removed
    } else if sameContent && !otherChanges
      && oldRevision != newRevision
    {
      change = .repinned
    } else {
      change = .changed
    }
  }

  static func pin(revision: String?) -> String {
    revision.map { String($0.prefix(7)) } ?? "none"
  }

  static func ordered(_ items: [HumanItem]) -> [HumanItem] {
    items.sorted {
      ($0.change.rawValue, $0.name, $0.source)
        < ($1.change.rawValue, $1.name, $1.source)
    }
  }

  func render(paths: HumanPaths) -> String {
    "\(change.label)  \(Terminal.line(name))  \(paths.source(source))  \(Terminal.line(before)) -> \(Terminal.line(after))\n"
  }
}

/// Presentation-only entry type; JSON keeps the core snapshots unchanged.
enum HumanFileEntry: Equatable {
  case file(Data, executable: Bool? = nil)
  case directory
  case symbolicLink(String)

  init(_ entry: SkillFileEntry) {
    switch entry {
    case .file(let data): self = .file(data)
    case .directory: self = .directory
    case .symbolicLink(let target): self = .symbolicLink(target)
    }
  }

  init(_ entry: WatchFileEntry) {
    switch entry {
    case .file(let data, let executable): self = .file(data, executable: executable)
    case .directory: self = .directory
    case .symbolicLink(let target): self = .symbolicLink(target)
    }
  }
}

extension Terminal {
  static func fileDifference(
    path: String, before: HumanFileEntry?, after: HumanFileEntry?,
    paths: HumanPaths = HumanPaths(), write: (String) -> Void = Terminal.write
  ) {
    guard before != after else { return }
    let path = paths.path(path)
    if case .directory = before { write("directory \(path) removed\n") }
    if case .directory = after { write("directory \(path) added\n") }
    var oldLink: String?
    var newLink: String?
    if case .symbolicLink(let target) = before { oldLink = paths.path(target) }
    if case .symbolicLink(let target) = after { newLink = paths.path(target) }
    if oldLink != nil || newLink != nil {
      write("link \(path): \(oldLink ?? "none") -> \(newLink ?? "none")\n")
    }
    var oldData: Data?
    var newData: Data?
    if case .file(let data, _) = before { oldData = data }
    if case .file(let data, _) = after { newData = data }
    if case .file(_, let oldMode?) = before, case .file(_, let newMode?) = after,
      oldMode != newMode
    {
      write("mode \(path): \(oldMode ? "755" : "644") -> \(newMode ? "755" : "644")\n")
    }
    write(LineDiff.render(before: oldData, after: newData, path: path))
  }
}
