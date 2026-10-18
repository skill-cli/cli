import AgentsCore
import AgentsSkills
import Foundation

extension Terminal {
  static func skillFileDifferences(
    _ result: UpdateResult, previous: SkillOutputInventory, paths: HumanPaths,
    write: (String) -> Void = Terminal.write
  ) {
    let installs = previous.installations.filter { $0.name == result.skill }
    var roots = Set(installs.map { physicalSkillPath($0.path) })
    // New targets and unavailable inventories can lack an installation path.
    // Only infer unambiguous roots, retaining physical paths otherwise.
    for change in result.changes.sorted(by: { $0.path.count < $1.path.count }) {
      if !roots.contains(where: { change.path == $0 || change.path.hasPrefix($0 + "/") }),
        let root = installationRoot(change.path, skill: result.skill, paths: paths)
      {
        roots.insert(root)
      }
    }
    var files: [SkillDisplayChange] = []
    for change in result.changes {
      let root = roots.filter { change.path == $0 || change.path.hasPrefix($0 + "/") }
        .max { $0.count < $1.count }
      let recipients = installs.filter { physicalSkillPath($0.path) == root }.map(\.agent)
      if change.path == root,
        isCacheLinkChange(change, result: result, previous: previous, paths: paths)
      {
        continue
      }
      let relative = root.map { String(change.path.dropFirst($0.count)) }
      let path = relative.map { result.skill + $0 } ?? paths.path(change.path)
      let before = displayEntry(change.before, at: change.path, isRoot: change.path == root)
      let after = displayEntry(change.after, at: change.path, isRoot: change.path == root)
      if let index = files.firstIndex(where: {
        $0.path == path && $0.before == before && $0.after == after
      }) {
        files[index].agents.formUnion(recipients)
        files[index].installations.insert(root ?? change.path)
      } else {
        files.append(
          SkillDisplayChange(
            path: path, before: before, after: after,
            agents: Set(recipients), installations: [root ?? change.path]))
      }
    }
    for file in files.sorted(by: { $0.path < $1.path }) {
      if files.filter({ $0.path == file.path }).count > 1
        || (!file.agents.isEmpty && file.agents != previous.agents(for: result.skill))
      {
        let label =
          file.agents.isEmpty
          ? file.installations.sorted().map(paths.path).joined(separator: ", ")
          : recipients(Array(file.agents))
        write("\(line(file.path)) (\(label))\n")
      }
      fileDifference(
        path: file.path, before: file.before.map(HumanFileEntry.init),
        after: file.after.map(HumanFileEntry.init), paths: paths, write: write)
    }
  }

  static func updatedSkills(
    _ results: [UpdateResult], previous: SkillOutputInventory,
    write: (String) -> Void = Terminal.write
  ) {
    for result in results.sorted(by: { $0.skill < $1.skill }) where result.changed {
      let before = previous.agents(for: result.skill)
      let after = Set(result.installed.map(\.agent))
      let removed = before.subtracting(after)
      if !removed.isEmpty {
        write("Removed \(line(result.skill)) for \(recipients(Array(removed))).\n")
      }
      if !after.isEmpty {
        write("Updated \(line(result.skill)) for \(recipients(Array(after))).\n")
      }
    }
  }

  static func removedSkills(_ names: [String], previous: SkillOutputInventory) {
    for name in names.sorted() {
      let agents = previous.agents(for: name)
      if !agents.isEmpty {
        write("Removed \(line(name)) for \(recipients(Array(agents))).\n")
      }
    }
  }

  private static func physicalSkillPath(_ path: String) -> String {
    let url = URL(fileURLWithPath: path)
    return url.deletingLastPathComponent().resolvingSymlinksInPath()
      .appendingPathComponent(url.lastPathComponent).standardizedFileURL.path
  }

  private static func installationRoot(_ path: String, skill: String, paths: HumanPaths) -> String?
  {
    let base =
      (paths.scope == .project
      ? paths.environment.projectDirectory : paths.environment.homeDirectory)
      .resolvingSymlinksInPath().path
    var url = URL(fileURLWithPath: path)
    var candidates: [String] = []
    while url.path != "/" && url.path != base {
      if url.lastPathComponent == skill
        && url.deletingLastPathComponent().lastPathComponent == "skills"
      {
        candidates.append(url.path)
      }
      url.deleteLastPathComponent()
    }
    return candidates.count == 1 ? candidates[0] : nil
  }

  private static func displayEntry(_ entry: SkillFileEntry?, at path: String, isRoot: Bool)
    -> SkillFileEntry?
  {
    guard isRoot, case .symbolicLink(let destination) = entry else { return entry }
    // Installation links can use different relative spellings for the same target.
    let target = URL(
      fileURLWithPath: destination,
      relativeTo: URL(fileURLWithPath: path).deletingLastPathComponent()
    )
    .standardizedFileURL.path
    return .symbolicLink(target)
  }

  private static func physicalPath(_ url: URL) -> String {
    var parent = url.standardizedFileURL
    var suffix: [String] = []
    // Preview destinations can be absent; resolve their existing ancestry.
    while parent.path != "/" && !FileManager.default.fileExists(atPath: parent.path) {
      suffix.append(parent.lastPathComponent)
      parent.deleteLastPathComponent()
    }
    return suffix.reversed().reduce(parent.resolvingSymlinksInPath()) {
      $0.appendingPathComponent($1)
    }.path
  }

  private static func isCacheLinkChange(
    _ change: SkillFileChange, result: UpdateResult, previous: SkillOutputInventory,
    paths: HumanPaths
  ) -> Bool {
    if previous.modes[result.skill]?.values.contains(.edit) == true { return false }
    if change.after != nil && result.newHash == nil && result.newRevision == nil { return false }
    let cache = physicalPath(
      StateStore(scope: paths.scope, environment: paths.environment).cacheDirectory)
    func cached(_ entry: SkillFileEntry?) -> Bool {
      guard let entry else { return true }
      guard case .symbolicLink(let destination) = entry else { return false }
      let target = URL(
        fileURLWithPath: destination,
        relativeTo: URL(fileURLWithPath: change.path).deletingLastPathComponent()
      )
      return physicalPath(target).hasPrefix(cache + "/")
    }
    return cached(change.before) && cached(change.after)
  }
}

private struct SkillDisplayChange {
  let path: String
  let before: SkillFileEntry?
  let after: SkillFileEntry?
  var agents: Set<AgentID>
  var installations: Set<String>
}

struct SkillOutputInventory {
  var installations: [InstalledSkill] = []
  var modes: [String: [String: InstallMode]] = [:]

  func agents(for name: String) -> Set<AgentID> {
    Set((modes[name] ?? [:]).keys.compactMap(AgentID.init(rawValue:)))
  }

  static func read(scope: InstallScope, agents: [AgentID]? = nil) -> Self {
    // Mutation owns recovery; withRecovery captures this snapshot again on retry.
    if let installations = try? SkillOperations.listManaged(scope: scope, agents: agents) {
      var result = Self(installations: installations)
      for install in installations {
        result.modes[install.name, default: [:]][install.agent.rawValue] = install.mode
      }
      return result
    }
    // Inventory hashes installed content, so unrelated unreadable content can fail
    // it even when a named update or removal succeeds. Locked recipients remain
    // useful for presentation; read them without triggering state recovery.
    let url = StateStore(scope: scope).resolvedURL
    guard let metadata = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
      metadata.isRegularFile == true, metadata.isSymbolicLink != true,
      let data = try? Data(contentsOf: url),
      let lock = try? JSONDecoder().decode(ResolvedState.self, from: data)
    else { return Self() }
    return Self(
      modes: lock.skills.mapValues { skill in
        skill.installs.filter { raw, _ in
          guard let agent = AgentID(rawValue: raw) else { return false }
          return agents?.contains(agent) ?? true
        }
      })
  }
}
