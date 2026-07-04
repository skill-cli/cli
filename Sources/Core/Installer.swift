import Foundation

public struct ResolvedSource: Equatable, Sendable {
  public var parsed: ParsedSource
  public var identity: String
  public var checkoutURL: URL
  public var revision: String?
  public var requestedRef: String?
  public var resolvedVersion: String?
  public var watchID: String?
  public var watchPath: String?
  public var watchInstallCommit: String?

  public init(
    parsed: ParsedSource, identity: String, checkoutURL: URL, revision: String? = nil,
    requestedRef: String? = nil, resolvedVersion: String? = nil, watchID: String? = nil,
    watchPath: String? = nil,
    watchInstallCommit: String? = nil
  ) {
    self.parsed = parsed
    self.identity = identity
    self.checkoutURL = checkoutURL
    self.revision = revision
    self.requestedRef = requestedRef
    self.resolvedVersion = resolvedVersion
    self.watchID = watchID
    self.watchPath = watchPath
    self.watchInstallCommit = watchInstallCommit
  }

  public var sourcePin: SourcePin {
    let kind: String
    switch parsed.type {
    case .local:
      kind = "localFileSystem"
    case .github, .gitlab, .git:
      kind = "remoteSourceControl"
    case .wellKnown:
      kind = "wellKnown"
    }
    return SourcePin(
      identity: identity,
      kind: kind,
      location: lockLocation,
      requirement: parsed.requirement,
      state: pinState
    )
  }

  private var pinState: PinState {
    var state = PinState(revision: revision)
    guard let requirement = parsed.requirement else {
      state.ref = requestedRef
      return state
    }
    switch requirement.kind {
    case "branch":
      state.branch = requirement.value
    case "revision":
      state.revision = revision ?? requirement.value
    case "ref":
      state.ref = requirement.value
    case "exact", "from", "minor", "range":
      state.version = resolvedVersion ?? requestedRef
    default:
      state.ref = requestedRef
    }
    return state
  }

  private var lockLocation: String {
    switch parsed.type {
    case .github, .gitlab, .git:
      if parsed.url.hasPrefix("git@") || parsed.url.hasPrefix("ssh://") {
        return parsed.url
      }
      return SourceParser.ownerRepo(for: parsed) ?? parsed.url
    case .local, .wellKnown:
      return parsed.url
    }
  }
}

public struct InstallRequest: Sendable {
  public var source: ResolvedSource
  public var skills: [Skill]
  public var agents: [AgentID]
  public var scope: InstallScope
  public var mode: InstallMode
  public var environment: RuntimeEnvironment

  public init(
    source: ResolvedSource, skills: [Skill], agents: [AgentID], scope: InstallScope,
    mode: InstallMode, environment: RuntimeEnvironment
  ) {
    self.source = source
    self.skills = skills
    self.agents = agents
    self.scope = scope
    self.mode = mode
    self.environment = environment
  }
}

public struct InstallResult: Codable, Equatable, Sendable {
  public var skill: String
  public var agent: AgentID
  public var scope: InstallScope
  public var mode: InstallMode
  public var path: String
  public var materialization: InstallMaterialization?
  public var sourcePath: String?
  public var linkTarget: String?
  public var fallback: Bool?

  public init(
    skill: String,
    agent: AgentID,
    scope: InstallScope,
    mode: InstallMode,
    path: String,
    materialization: InstallMaterialization? = nil,
    sourcePath: String? = nil,
    linkTarget: String? = nil,
    fallback: Bool? = nil
  ) {
    self.skill = skill
    self.agent = agent
    self.scope = scope
    self.mode = mode
    self.path = path
    self.materialization = materialization
    self.sourcePath = sourcePath
    self.linkTarget = linkTarget
    self.fallback = fallback
  }
}

public enum Installer {
  public static func install(_ request: InstallRequest) throws -> [InstallResult] {
    if request.mode == .edit {
      guard request.source.parsed.type == .local, request.source.parsed.requirement == nil,
        request.source.watchID == nil
      else {
        throw CoreError.invalidSource("--mode edit requires an unpinned local source")
      }
    }
    var results: [InstallResult] = []
    for skill in request.skills {
      let installName = PathSafety.sanitizeName(skill.name)
      let contentHash = try FileHash.folderHash(URL(fileURLWithPath: skill.path))
      var installations: [InstallationPin] = []
      let sourceURL = URL(fileURLWithPath: skill.path)
      let agents = unique(request.agents)
      let canonical = AgentRegistry.canonicalSkillsDirectory(
        scope: request.scope, environment: request.environment
      ).appendingPathComponent(installName)
      let needsCanonical =
        request.mode == .symlink
        || request.mode == .edit
        || (request.mode == .copy
          && agents.contains {
          AgentRegistry.usesCanonicalSkillsDirectory(
            for: $0, scope: request.scope, environment: request.environment)
          })

      if needsCanonical {
        if request.mode == .edit {
          try editLinkDirectory(target: sourceURL, destination: canonical)
        } else {
          try installDirectory(source: sourceURL, destination: canonical, mode: .copy)
        }
      }

      for agent in agents {
        let base = AgentRegistry.installSkillsDirectory(
          for: agent, scope: request.scope, environment: request.environment)
        let destination = base.appendingPathComponent(installName)

        if sameStandardizedLocation(canonical, destination), needsCanonical {
          // Universal agents use canonical storage directly.
          try removeStaleNativeProjection(
            installName: installName, agent: agent, scope: request.scope,
            environment: request.environment)
        } else if request.mode != .edit && sameResolvedLocation(canonical, destination),
          needsCanonical
        {
          // The agent's native skill directory already resolves to canonical storage.
        } else if request.mode == .copy {
          try installDirectory(source: sourceURL, destination: destination, mode: .copy)
        } else if request.mode == .edit {
          try editProjectionDirectory(target: canonical, destination: destination)
        } else {
          try linkDirectory(
            target: canonical, destination: destination, fallbackCopySource: canonical)
        }

        let materialization = materializationForInstalledPath(
          mode: request.mode,
          destination: destination,
          canonical: canonical,
          sourceURL: sourceURL,
          needsCanonical: needsCanonical
        )

        let relativePath = relative(destination.path, to: request.environment.projectDirectory.path)
        let installation = InstallationPin(
          scope: request.scope,
          agent: agent,
          mode: request.mode,
          path: request.scope == .project ? relativePath : destination.path,
          materialization: materialization.kind,
          sourcePath: sourceURL.path,
          linkTarget: materialization.linkTarget,
          fallback: materialization.fallback
        )
        installations.append(installation)
        results.append(
          InstallResult(
            skill: skill.name, agent: agent, scope: request.scope, mode: request.mode,
            path: destination.path,
            materialization: materialization.kind,
            sourcePath: sourceURL.path,
            linkTarget: materialization.linkTarget,
            fallback: materialization.fallback))
      }

      let pinnedSkill = PinnedSkill(
        identity: installName,
        name: skill.name,
        path: relative(
          URL(fileURLWithPath: skill.skillFile).path, to: request.source.checkoutURL.path),
        contentHash: contentHash,
        installations: installations
      )
      try InstallLockStore.merge(
        pinnedSkill: pinnedSkill,
        into: request.source.sourcePin,
        scope: request.scope,
        environment: request.environment
      )
    }

    return results
  }

  public static func remove(
    skillNames: [String], agents: [AgentID], scope: InstallScope, environment: RuntimeEnvironment
  ) throws -> [String] {
    var removed: [String] = []
    let names = skillNames.map(PathSafety.sanitizeName)
    let lockBefore = try InstallLockStore.load(scope: scope, environment: environment)
    for agent in unique(agents) {
      for base in AgentRegistry.removalDirectories(
        for: agent, scope: scope, environment: environment)
      {
        let targets: [URL]
        if names.isEmpty {
          targets =
            (try? FileManager.default.contentsOfDirectory(
              at: base, includingPropertiesForKeys: nil))
            ?? []
        } else {
          targets = names.map { base.appendingPathComponent($0) }
        }
        for target in targets where FileManager.default.fileExists(atPath: target.path) {
          guard PathSafety.isContained(target, in: base) else {
            throw CoreError.unsafePath("refusing to remove outside \(base.path): \(target.path)")
          }
          if shouldPreserveCanonical(
            target: target,
            scope: scope,
            removedAgents: agents,
            lock: lockBefore,
            environment: environment
          ) {
            continue
          }
          try FileManager.default.removeItem(at: target)
          removed.append(target.path)
        }
      }
    }
    try InstallLockStore.remove(
      skillNames: skillNames, agents: agents, scope: scope, environment: environment)
    let lockAfter = try InstallLockStore.load(scope: scope, environment: environment)
    try removeUnusedCanonicalStorage(
      removedSkillNames: canonicalCleanupNames(
        requestedNames: names,
        removedPaths: removed,
        removedAgents: agents,
        scope: scope,
        lockBefore: lockBefore
      ),
      scope: scope,
      lock: lockAfter,
      environment: environment,
      removed: &removed
    )
    return removed
  }

  private static func installDirectory(source: URL, destination: URL, mode: InstallMode) throws {
    if sameResolvedLocation(source, destination) {
      return
    }
    guard PathSafety.isContained(destination, in: destination.deletingLastPathComponent()) else {
      throw CoreError.unsafePath("destination escapes install base: \(destination.path)")
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) || isSymlink(destination) {
      try FileManager.default.removeItem(at: destination)
    }

    switch mode {
    case .copy:
      try copyDirectory(source: source, destination: destination)
    case .symlink:
      do {
        let relativeTarget = relative(source.path, to: destination.deletingLastPathComponent().path)
        try FileManager.default.createSymbolicLink(
          atPath: destination.path, withDestinationPath: relativeTarget)
      } catch {
        try copyDirectory(source: source, destination: destination)
      }
    case .edit:
      try editLinkDirectory(target: source, destination: destination)
    }
  }

  private static func linkDirectory(target: URL, destination: URL, fallbackCopySource: URL) throws {
    if sameResolvedLocation(target, destination) {
      return
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) || isSymlink(destination) {
      try FileManager.default.removeItem(at: destination)
    }
    do {
      try FileManager.default.createSymbolicLink(
        atPath: destination.path,
        withDestinationPath: relative(target.path, to: destination.deletingLastPathComponent().path)
      )
    } catch {
      try copyDirectory(source: fallbackCopySource, destination: destination)
    }
  }

  private static func editLinkDirectory(target: URL, destination: URL) throws {
    if sameResolvedLocation(target, destination) {
      return
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) || isSymlink(destination) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.createSymbolicLink(
      atPath: destination.path,
      withDestinationPath: relative(target.path, to: destination.deletingLastPathComponent().path)
    )
  }

  private static func materializationForInstalledPath(
    mode: InstallMode,
    destination: URL,
    canonical: URL,
    sourceURL: URL,
    needsCanonical: Bool
  ) -> (kind: InstallMaterialization, linkTarget: String?, fallback: Bool) {
    switch mode {
    case .copy:
      return (.copyInstalled, nil, false)
    case .edit:
      if needsCanonical && sameStandardizedLocation(canonical, destination) {
        return (.editInstalled, sourceURL.path, false)
      }
      return (.editInstalled, canonical.path, false)
    case .symlink:
      if needsCanonical && sameResolvedLocation(canonical, destination) {
        return (.copyInstalled, nil, false)
      }
      if isSymlink(destination) {
        return (.linkInstalled, canonical.path, false)
      }
      return (.copyFallback, canonical.path, true)
    }
  }

  private static func editProjectionDirectory(target: URL, destination: URL) throws {
    if sameStandardizedLocation(target, destination) {
      return
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) || isSymlink(destination) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.createSymbolicLink(
      atPath: destination.path,
      withDestinationPath: relative(target.path, to: destination.deletingLastPathComponent().path)
    )
  }

  private static func copyDirectory(source: URL, destination: URL) throws {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let entries = try FileManager.default.contentsOfDirectory(
      at: source, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [])
    for entry in entries {
      if shouldExclude(entry) {
        continue
      }
      let target = destination.appendingPathComponent(entry.lastPathComponent)
      let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
      if values.isDirectory == true {
        try copyDirectory(source: entry, destination: target)
      } else {
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: entry, to: target)
      }
    }
  }

  private static func shouldExclude(_ url: URL) -> Bool {
    [".git", "__pycache__", "__pypackages__", "metadata.json"].contains(url.lastPathComponent)
  }

  private static func isSymlink(_ path: URL) -> Bool {
    (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
  }

  private static func unique(_ agents: [AgentID]) -> [AgentID] {
    var seen = Set<AgentID>()
    return agents.filter { seen.insert($0).inserted }
  }

  private static func shouldPreserveCanonical(
    target: URL,
    scope: InstallScope,
    removedAgents: [AgentID],
    lock: LockFile,
    environment: RuntimeEnvironment
  ) -> Bool {
    let canonicalBase = AgentRegistry.canonicalSkillsDirectory(
      scope: scope, environment: environment)
    guard PathSafety.isContained(target, in: canonicalBase) else { return false }
    let skillID = target.lastPathComponent
    let removed = Set(removedAgents)
    return lock.pins.contains { source in
      source.skills.contains { skill in
        skill.identity == skillID
          && skill.installations.contains {
            $0.scope == scope && !removed.contains($0.agent)
          }
      }
    }
  }

  private static func canonicalCleanupNames(
    requestedNames: [String],
    removedPaths: [String],
    removedAgents: [AgentID],
    scope: InstallScope,
    lockBefore: LockFile
  ) -> [String] {
    if !requestedNames.isEmpty {
      return requestedNames
    }
    var names = Set(removedPaths.map { URL(fileURLWithPath: $0).lastPathComponent })
    let removed = Set(removedAgents)
    for source in lockBefore.pins {
      for skill in source.skills
      where skill.installations.contains(where: { $0.scope == scope && removed.contains($0.agent) })
      {
        names.insert(skill.identity)
      }
    }
    return Array(names)
  }

  private static func removeUnusedCanonicalStorage(
    removedSkillNames: [String],
    scope: InstallScope,
    lock: LockFile,
    environment: RuntimeEnvironment,
    removed: inout [String]
  ) throws {
    let canonicalBase = AgentRegistry.canonicalSkillsDirectory(
      scope: scope, environment: environment)
    for skillID in Set(removedSkillNames) {
      let stillReferenced = lock.pins.contains { source in
        source.skills.contains { skill in
          skill.identity == skillID
            && skill.installations.contains { $0.scope == scope }
        }
      }
      guard !stillReferenced else { continue }
      let canonical = canonicalBase.appendingPathComponent(skillID)
      if FileManager.default.fileExists(atPath: canonical.path) || isSymlink(canonical) {
        try FileManager.default.removeItem(at: canonical)
        removed.append(canonical.path)
      }
    }
  }

  private static func removeStaleNativeProjection(
    installName: String,
    agent: AgentID,
    scope: InstallScope,
    environment: RuntimeEnvironment
  ) throws {
    guard scope == .global else { return }
    let native = AgentRegistry.skillsDirectory(
      for: agent, scope: scope, environment: environment
    ).appendingPathComponent(installName)
    let canonical = AgentRegistry.canonicalSkillsDirectory(
      scope: scope, environment: environment
    ).appendingPathComponent(installName)
    guard native.standardizedFileURL.path != canonical.standardizedFileURL.path else { return }
    if FileManager.default.fileExists(atPath: native.path) || isSymlink(native) {
      try FileManager.default.removeItem(at: native)
    }
  }

  private static func sameResolvedLocation(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL.path
      == rhs.resolvingSymlinksInPath().standardizedFileURL.path
  }

  private static func sameStandardizedLocation(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
  }

  private static func relative(_ path: String, to base: String) -> String {
    let pathURL = URL(fileURLWithPath: path).standardizedFileURL
    let baseURL = URL(fileURLWithPath: base).standardizedFileURL
    let pathComponents = pathURL.pathComponents
    let baseComponents = baseURL.pathComponents
    var index = 0
    while index < pathComponents.count, index < baseComponents.count,
      pathComponents[index] == baseComponents[index]
    {
      index += 1
    }
    let up = Array(repeating: "..", count: max(0, baseComponents.count - index))
    let down = pathComponents.dropFirst(index)
    let components = up + down
    return components.isEmpty ? "." : components.joined(separator: "/")
  }
}
