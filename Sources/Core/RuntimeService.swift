import Foundation

public struct AddOptions: Sendable {
  public var source: String
  public var agents: [AgentID]
  public var skillNames: [String]
  public var scope: InstallScope
  public var mode: InstallMode
  public var listOnly: Bool
  public var all: Bool
  public var allowMultipleSkills: Bool
  public var fullDepth: Bool
  public var path: String?
  public var sourceRequirement: SourceRequirement?
  public var watch: Bool
  public var watchOnly: Bool
  public var replaceRequirement: Bool
  public var environment: RuntimeEnvironment

  public init(
    source: String,
    agents: [AgentID] = [.codex],
    skillNames: [String] = [],
    scope: InstallScope = .project,
    mode: InstallMode = .symlink,
    listOnly: Bool = false,
    all: Bool = false,
    allowMultipleSkills: Bool? = nil,
    fullDepth: Bool = false,
    path: String? = nil,
    sourceRequirement: SourceRequirement? = nil,
    watch: Bool = false,
    watchOnly: Bool = false,
    replaceRequirement: Bool = false,
    environment: RuntimeEnvironment = RuntimeEnvironment()
  ) {
    self.source = source
    self.agents = agents
    self.skillNames = skillNames
    self.scope = scope
    self.mode = mode
    self.listOnly = listOnly
    self.all = all
    self.allowMultipleSkills = allowMultipleSkills ?? all
    self.fullDepth = fullDepth
    self.path = path
    self.sourceRequirement = sourceRequirement
    self.watch = watch
    self.watchOnly = watchOnly
    self.replaceRequirement = replaceRequirement
    self.environment = environment
  }
}

public struct AddOutcome: Sendable {
  public var source: ResolvedSource
  public var availableSkills: [Skill]
  public var installed: [InstallResult]
  public var watched: [WatchRecord]

  public init(
    source: ResolvedSource,
    availableSkills: [Skill],
    installed: [InstallResult],
    watched: [WatchRecord] = []
  ) {
    self.source = source
    self.availableSkills = availableSkills
    self.installed = installed
    self.watched = watched
  }
}

public struct InstalledSkill: Codable, Equatable, Sendable {
  public var name: String
  public var agent: AgentID
  public var scope: InstallScope
  public var path: String
  public var sourceIdentity: String?
  public var isInstalled: Bool
  public var watchID: String?
  public var reviewedCommit: String?
  public var lastCheckedCommit: String?

  public init(
    name: String, agent: AgentID, scope: InstallScope, path: String,
    sourceIdentity: String? = nil, isInstalled: Bool = true, watchID: String? = nil,
    reviewedCommit: String? = nil, lastCheckedCommit: String? = nil
  ) {
    self.name = name
    self.agent = agent
    self.scope = scope
    self.path = path
    self.sourceIdentity = sourceIdentity
    self.isInstalled = isInstalled
    self.watchID = watchID
    self.reviewedCommit = reviewedCommit
    self.lastCheckedCommit = lastCheckedCommit
  }
}

public struct UpdateResult: Codable, Equatable, Sendable {
  public var skill: String
  public var sourceIdentity: String
  public var changed: Bool
  public var oldHash: String
  public var newHash: String
  public var installed: [InstallResult]

  public init(
    skill: String, sourceIdentity: String, changed: Bool, oldHash: String, newHash: String,
    installed: [InstallResult] = []
  ) {
    self.skill = skill
    self.sourceIdentity = sourceIdentity
    self.changed = changed
    self.oldHash = oldHash
    self.newHash = newHash
    self.installed = installed
  }
}

public enum RuntimeService {
  public static func add(_ options: AddOptions) throws -> AddOutcome {
    let source =
      options.watch || options.watchOnly
      ? try SourceResolver.resolve(
        options.source, environment: options.environment, requirement: options.sourceRequirement)
      : try resolveSourceOrWatch(
        options.source,
        path: options.path,
        requirement: options.sourceRequirement,
        scope: options.scope,
        environment: options.environment)
    let explicitPath = try options.path.map(PathSafety.sanitizeSubpath)
    if let explicitPath, let sourcePath = source.parsed.subpath, explicitPath != sourcePath {
      throw CoreError.invalidSource("conflicting source paths")
    }
    let effectiveSubpath = explicitPath ?? source.parsed.subpath
    let discoveryRoot =
      try effectiveSubpath.map {
        try PathSafety.resolvedChild(base: source.checkoutURL, subpath: $0)
      } ?? source.checkoutURL
    let discovered = try Discovery.discover(
      in: discoveryRoot,
      options: DiscoveryOptions(
        includeInternal: shouldInstallInternalSkills(options.environment),
        fullDepth: options.fullDepth
      ))
    if let sourceSkill = source.parsed.skillFilter, !options.skillNames.isEmpty,
      !options.skillNames.map(PathSafety.sanitizeName).contains(
        PathSafety.sanitizeName(sourceSkill))
    {
      throw CoreError.invalidSource("conflicting skill selectors")
    }
    let filteredBySource =
      source.parsed.skillFilter.map { Discovery.filter(discovered, names: [$0]) } ?? discovered
    let selected =
      options.skillNames.isEmpty
      ? filteredBySource
      : Discovery.filter(filteredBySource, names: options.skillNames)

    guard !selected.isEmpty else {
      throw CoreError.notFound("no skills found in \(options.source)")
    }

    if options.listOnly {
      return AddOutcome(source: source, availableSkills: selected, installed: [])
    }

    if selected.count > 1, !options.allowMultipleSkills, options.skillNames.isEmpty,
      source.parsed.skillFilter == nil
    {
      throw CoreError.invalidSkill(
        "multiple skills found; pass --skill, --all, or a source skill filter")
    }

    if options.watch || options.watchOnly {
      let watchPaths = try watchPaths(for: selected, source: source)
      let record = try WatchService.upsert(
        source: source,
        paths: watchPaths,
        environment: options.environment,
        replaceRequirement: options.replaceRequirement,
        apply: true
      )
      guard !options.watchOnly else {
        return AddOutcome(
          source: source, availableSkills: selected, installed: [], watched: [record])
      }
      var installed: [InstallResult] = []
      for watchPath in watchPaths {
        let watchedOutcome = try add(
          AddOptions(
            source: record.watchID,
            agents: options.agents,
            skillNames: [],
            scope: options.scope,
            mode: options.mode,
            listOnly: false,
            all: true,
            allowMultipleSkills: true,
            fullDepth: options.fullDepth,
            path: watchPath,
            environment: options.environment
          ))
        installed.append(contentsOf: watchedOutcome.installed)
      }
      return AddOutcome(
        source: source, availableSkills: selected, installed: installed, watched: [record])
    }

    let request = InstallRequest(
      source: source,
      skills: selected,
      agents: options.agents,
      scope: options.scope,
      mode: options.mode,
      environment: options.environment
    )
    return AddOutcome(
      source: source, availableSkills: selected, installed: try Installer.install(request))
  }

  public static func listInstalled(
    scope: InstallScope, agents: [AgentID], environment: RuntimeEnvironment
  ) throws -> [InstalledSkill] {
    let watchLedger = try? WatchLedgerStore.load(environment: environment)
    var installed: [InstalledSkill] = []
    var seenPaths = Set<String>()
    for agent in agents {
      let bases = scanDirectories(for: agent, scope: scope, environment: environment)
      for base in bases {
        guard
          let entries = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else {
          continue
        }
        for entry in entries {
          let seenKey = "\(agent.rawValue)\u{1f}\(entry.standardizedFileURL.path)"
          guard seenPaths.insert(seenKey).inserted else { continue }
          let skillFile = entry.appendingPathComponent("SKILL.md")
          guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
          guard let skill = try Discovery.parseSkill(at: skillFile, includeInternal: true) else {
            continue
          }
          let name = skill.name
          let correlation = correlate(skillName: name, watchLedger: watchLedger)
          installed.append(
            InstalledSkill(
              name: name,
              agent: agent,
              scope: scope,
              path: entry.path,
              watchID: correlation?.watchID,
              reviewedCommit: correlation?.reviewedCommit,
              lastCheckedCommit: correlation?.lastCheckedCommit
            ))
        }
      }
    }
    return installed.sorted { ($0.agent.rawValue, $0.name) < ($1.agent.rawValue, $1.name) }
  }

  public static func listManaged(
    scope: InstallScope, agents: [AgentID], environment: RuntimeEnvironment
  ) throws -> [InstalledSkill] {
    let lock = try InstallLockStore.load(scope: scope, environment: environment)
    let watchLedger = try? WatchLedgerStore.load(environment: environment)
    let requestedAgents = Set(agents)
    var listed: [InstalledSkill] = []
    var seen = Set<String>()

    for source in lock.pins {
      for pinnedSkill in source.skills {
        let correlation = correlate(skillName: pinnedSkill.name, watchLedger: watchLedger)
        for installation in pinnedSkill.installations
        where installation.scope == scope && requestedAgents.contains(installation.agent) {
          let destination = installationURL(for: installation, environment: environment)
          let key = [
            pinnedSkill.identity,
            installation.scope.rawValue,
            installation.agent.rawValue,
            destination.standardizedFileURL.path,
          ].joined(separator: "\u{1f}")
          guard seen.insert(key).inserted else { continue }
          listed.append(
            InstalledSkill(
              name: pinnedSkill.name,
              agent: installation.agent,
              scope: installation.scope,
              path: destination.path,
              sourceIdentity: source.identity,
              isInstalled: installedSkillExists(at: destination),
              watchID: correlation?.watchID,
              reviewedCommit: correlation?.reviewedCommit,
              lastCheckedCommit: correlation?.lastCheckedCommit
            ))
        }
      }
    }

    return listed.sorted {
      ($0.agent.rawValue, $0.name, $0.path) < ($1.agent.rawValue, $1.name, $1.path)
    }
  }

  public static func remove(
    skillNames: [String], scope: InstallScope, agents: [AgentID], environment: RuntimeEnvironment
  ) throws -> [String] {
    if !skillNames.isEmpty {
      let installed = try listInstalled(scope: scope, agents: agents, environment: environment)
      let available = Set(installed.map { PathSafety.sanitizeName($0.name) })
      let missing = skillNames.filter { !available.contains(PathSafety.sanitizeName($0)) }
      if let first = missing.first {
        throw CoreError.notFound("skill '\(first)'")
      }
    }
    return try Installer.remove(
      skillNames: skillNames, agents: agents, scope: scope, environment: environment)
  }

  public static func installProjectResolved(environment: RuntimeEnvironment) throws
    -> [InstallResult]
  {
    try installResolved(scope: .project, environment: environment)
  }

  public static func installResolved(
    scope: InstallScope = .project, environment: RuntimeEnvironment
  ) throws -> [InstallResult] {
    let lock = try InstallLockStore.load(scope: scope, environment: environment)
    var results: [InstallResult] = []

    for sourcePin in lock.pins {
      let source = try resolvedSource(from: sourcePin, scope: scope, environment: environment)
      for pinnedSkill in sourcePin.skills {
        let skillFile = source.checkoutURL.appendingPathComponent(pinnedSkill.path)
        let parsedSkill = try Discovery.parseSkill(at: skillFile, includeInternal: true)
        let skill =
          parsedSkill
          ?? Skill(
            name: pinnedSkill.name,
            description: "Restored from lock",
            path: skillFile.deletingLastPathComponent().path,
            skillFile: skillFile.path
          )

        results.append(
          contentsOf: try installRestoredSkill(
            source: source,
            skill: skill,
            installations: pinnedSkill.installations,
            scope: scope,
            environment: environment))
      }
    }

    return results
  }

  public static func updateInstalled(
    skillNames: [String] = [], scope: InstallScope, environment: RuntimeEnvironment, apply: Bool
  ) throws -> [UpdateResult] {
    let lock = try InstallLockStore.load(scope: scope, environment: environment)
    let selectedNames = Set(skillNames.map(PathSafety.sanitizeName))
    var results: [UpdateResult] = []

    for sourcePin in lock.pins {
      let source = try resolvedSource(from: sourcePin, scope: scope, environment: environment)
      for pinnedSkill in sourcePin.skills {
        guard
          selectedNames.isEmpty || selectedNames.contains(pinnedSkill.identity)
            || selectedNames.contains(PathSafety.sanitizeName(pinnedSkill.name))
        else {
          continue
        }
        let skillFile = source.checkoutURL.appendingPathComponent(pinnedSkill.path)
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
          results.append(
            UpdateResult(
              skill: pinnedSkill.name,
              sourceIdentity: sourcePin.identity,
              changed: false,
              oldHash: pinnedSkill.contentHash,
              newHash: pinnedSkill.contentHash,
              installed: []
            ))
          continue
        }
        let skill =
          try Discovery.parseSkill(at: skillFile, includeInternal: true)
          ?? Skill(
            name: pinnedSkill.name,
            description: "Updated from lock",
            path: skillFile.deletingLastPathComponent().path,
            skillFile: skillFile.path
          )
        let newHash = try FileHash.folderHash(URL(fileURLWithPath: skill.path))
        let changed = newHash != pinnedSkill.contentHash
        var installed: [InstallResult] = []

        if changed, apply {
          installed.append(
            contentsOf: try installRestoredSkill(
              source: source,
              skill: skill,
              installations: pinnedSkill.installations,
              scope: scope,
              environment: environment))
        }

        results.append(
          UpdateResult(
            skill: pinnedSkill.name,
            sourceIdentity: sourcePin.identity,
            changed: changed,
            oldHash: pinnedSkill.contentHash,
            newHash: newHash,
            installed: installed
          ))
      }
    }

    return results
  }

  public static func updateFromWatch(
    _ target: String,
    path: String? = nil,
    all: Bool = false,
    agents: [AgentID]? = nil,
    scope: InstallScope = .project,
    mode: InstallMode = .symlink,
    environment: RuntimeEnvironment,
    apply: Bool
  ) throws -> [InstallResult] {
    let record = try WatchService.record(matching: target, environment: environment)
    let packets = try WatchService.diff(
      watchID: record.watchID, path: path, all: all, environment: environment)
    guard apply else {
      return []
    }

    var results: [InstallResult] = []
    for packet in packets {
      let targets =
        agents.map { explicitAgents in
          explicitAgents.map { agent in
            InstallationPin(scope: scope, agent: agent, mode: mode, path: "")
          }
        }
        ?? lockedInstallTargets(
          sourceIdentity: record.source.identity,
          watchedPath: packet.path,
          environment: environment
        )
      let effectiveTargets =
        targets.isEmpty
        ? [InstallationPin(scope: scope, agent: .codex, mode: mode, path: "")]
        : targets
      for target in effectiveTargets {
        let outcome = try add(
          AddOptions(
            source: record.watchID,
            agents: [target.agent],
            skillNames: [],
            scope: target.scope,
            mode: target.mode,
            listOnly: false,
            all: true,
            allowMultipleSkills: true,
            path: packet.path,
            environment: environment
          ))
        results.append(contentsOf: outcome.installed)
      }
    }
    return results
  }

  public static func initializeSkill(named name: String?, directory: URL) throws -> URL {
    let safeName = name.map(PathSafety.sanitizeName)
    let skillDirectory = safeName.map { directory.appendingPathComponent($0) } ?? directory
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
    guard !FileManager.default.fileExists(atPath: skillFile.path) else {
      throw CoreError.invalidSkill("SKILL.md already exists at \(skillFile.path)")
    }
    let title = safeName ?? skillDirectory.lastPathComponent
    let contents = """
      ---
      name: \(title)
      description: A brief description of what this skill does
      ---

      # \(title)

      Instructions for the agent to follow when this skill is activated.

      ## When to use

      Describe when this skill should be used.

      ## Instructions

      1. First step
      2. Second step
      3. Additional steps as needed
      """
    try contents.write(to: skillFile, atomically: true, encoding: .utf8)
    return skillDirectory
  }

  public static func resolveSourceOrWatch(
    _ input: String, path: String? = nil, requirement: SourceRequirement? = nil,
    scope: InstallScope = .project,
    environment: RuntimeEnvironment
  ) throws -> ResolvedSource {
    if let ledger = try? WatchLedgerStore.load(environment: environment),
      let record = try? WatchService.record(matching: input, in: ledger),
      let checkoutPath = record.checkoutPath
    {
      if requirement != nil {
        throw CoreError.invalidSource("source requirement flags cannot be used with a watch source")
      }
      let requestedPath = try path.map(PathSafety.sanitizeSubpath)
      let selectedPath =
        try requestedPath.map { requested in
          guard let state = record.watchedPaths.first(where: { $0.path == requested }) else {
            throw CoreError.notFound("path '\(requested)' in watch '\(record.watchID)'")
          }
          return state
        } ?? (record.watchedPaths.count == 1 ? record.watchedPaths[0] : nil)
      let targetCommit =
        selectedPath?.reviewCoverage.reviewedCommit ?? record.watchBaseline
        ?? record.source.state.revision
      let checkout = URL(fileURLWithPath: checkoutPath)
      let installCheckout: URL
      if let targetCommit, Git.revision(at: checkout) != targetCommit,
        FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path)
      {
        installCheckout = try Git.materializeCheckout(
          repository: checkout,
          commit: targetCommit,
          cacheDirectory: environment.projectDirectory.appendingPathComponent(
            ".agent/cache/watch-installs"),
          identity: record.watchID
        )
      } else {
        installCheckout = checkout
      }
      let parsed = try parsedSource(from: record.source, subpath: selectedPath?.path)
      return ResolvedSource(
        parsed: parsed,
        identity: record.source.identity,
        checkoutURL: installCheckout,
        revision: targetCommit ?? record.source.state.revision,
        requestedRef: record.source.state.ref ?? record.source.state.branch,
        resolvedVersion: record.source.state.version,
        watchID: record.watchID,
        watchPath: selectedPath?.path,
        watchInstallCommit: targetCommit
      )
    }
    return try SourceResolver.resolve(
      input, environment: environment, requirement: requirement, scope: scope)
  }

  private static func parsedSource(from pin: SourcePin, subpath: String?) throws -> ParsedSource {
    switch pin.kind {
    case "localFileSystem":
      return ParsedSource(
        type: .local, url: pin.location, localPath: pin.location,
        ref: pin.requirement?.checkoutRef ?? pin.state.ref ?? pin.state.branch,
        requirement: pin.requirement,
        subpath: subpath)
    case "remoteSourceControl":
      var parsed = try SourceParser.parse(pin.location)
      parsed.ref = pin.requirement?.checkoutRef ?? pin.state.ref ?? pin.state.branch
      parsed.requirement = pin.requirement
      parsed.subpath = subpath ?? parsed.subpath
      return parsed
    default:
      return ParsedSource(
        type: .git, url: pin.location,
        ref: pin.requirement?.checkoutRef ?? pin.state.ref ?? pin.state.branch,
        requirement: pin.requirement,
        subpath: subpath)
    }
  }

  private static func watchPaths(for skills: [Skill], source: ResolvedSource) throws -> [String] {
    var paths: [String] = []
    for skill in skills {
      let path = PathSafety.relativePath(skill.path, to: source.checkoutURL.path)
      if !paths.contains(path) {
        paths.append(try PathSafety.sanitizeSubpath(path))
      }
    }
    return paths
  }

  private static func lockedInstallTargets(
    sourceIdentity: String,
    watchedPath: String,
    environment: RuntimeEnvironment
  ) -> [InstallationPin] {
    var targets: [InstallationPin] = []
    for scope in [InstallScope.project, .global] {
      guard let lock = try? InstallLockStore.load(scope: scope, environment: environment) else {
        continue
      }
      for source in lock.pins where source.identity == sourceIdentity {
        for skill in source.skills where skillDirectoryPath(from: skill.path) == watchedPath {
          targets.append(contentsOf: skill.installations)
        }
      }
    }
    var seen = Set<String>()
    return targets.filter { target in
      seen.insert(
        "\(target.scope.rawValue)\u{1f}\(target.agent.rawValue)\u{1f}\(target.mode.rawValue)"
      )
      .inserted
    }
  }

  private static func skillDirectoryPath(from skillFilePath: String) -> String {
    if skillFilePath == "SKILL.md" {
      return "."
    }
    if skillFilePath.hasSuffix("/SKILL.md") {
      return String(skillFilePath.dropLast("/SKILL.md".count))
    }
    return skillFilePath
  }

  private static func correlate(skillName: String, watchLedger: WatchLedger?) -> (
    watchID: String, reviewedCommit: String?, lastCheckedCommit: String?
  )? {
    guard let watchLedger else { return nil }
    let normalized = PathSafety.sanitizeName(skillName)
    for watch in watchLedger.watches {
      for path in watch.watchedPaths {
        let pathName = PathSafety.sanitizeName(URL(fileURLWithPath: path.path).lastPathComponent)
        if pathName == normalized || watch.watchID == normalized {
          return (
            watch.watchID, path.reviewCoverage.reviewedCommit, path.tracking.lastCheckedCommit
          )
        }
      }
    }
    return nil
  }

  private static func scanDirectories(
    for agent: AgentID, scope: InstallScope, environment: RuntimeEnvironment
  ) -> [URL] {
    if scope == .project {
      return AgentRegistry.projectScanDirectories(for: agent, environment: environment)
    }
    var seen = Set<String>()
    return
      ([AgentRegistry.skillsDirectory(for: agent, scope: scope, environment: environment)]
      + AgentRegistry.nativeGlobalScanDirectories(for: agent, environment: environment))
      .filter { seen.insert($0.standardizedFileURL.path).inserted }
  }

  private static func installationURL(
    for installation: InstallationPin, environment: RuntimeEnvironment
  ) -> URL {
    if installation.path.hasPrefix("/") {
      return URL(fileURLWithPath: installation.path).standardizedFileURL
    }
    switch installation.scope {
    case .project:
      return environment.projectDirectory.appendingPathComponent(installation.path)
        .standardizedFileURL
    case .global:
      return environment.homeDirectory.appendingPathComponent(installation.path)
        .standardizedFileURL
    }
  }

  private static func installRestoredSkill(
    source: ResolvedSource,
    skill: Skill,
    installations: [InstallationPin],
    scope: InstallScope,
    environment: RuntimeEnvironment
  ) throws -> [InstallResult] {
    var grouped: [(mode: InstallMode, agents: [AgentID])] = []
    for installation in installations where installation.scope == scope {
      if let index = grouped.firstIndex(where: { $0.mode == installation.mode }) {
        grouped[index].agents.append(installation.agent)
      } else {
        grouped.append((mode: installation.mode, agents: [installation.agent]))
      }
    }

    var results: [InstallResult] = []
    for group in grouped {
      let request = InstallRequest(
        source: source,
        skills: [skill],
        agents: group.agents,
        scope: scope,
        mode: group.mode,
        environment: environment
      )
      results.append(contentsOf: try Installer.install(request))
    }
    return results
  }

  private static func installedSkillExists(at directory: URL) -> Bool {
    let skillFile = directory.appendingPathComponent("SKILL.md")
    guard FileManager.default.fileExists(atPath: skillFile.path) else { return false }
    return (try? Discovery.parseSkill(at: skillFile, includeInternal: true)) != nil
  }

  private static func shouldInstallInternalSkills(_ environment: RuntimeEnvironment) -> Bool {
    let value = environment.environment["INSTALL_INTERNAL_SKILLS"]?.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value == "1" || value == "true"
  }

  private static func resolvedSource(
    from pin: SourcePin, scope: InstallScope, environment: RuntimeEnvironment
  ) throws -> ResolvedSource {
    switch pin.kind {
    case "localFileSystem":
      let parsed = ParsedSource(
        type: .local, url: pin.location, localPath: pin.location,
        ref: pin.requirement?.checkoutRef ?? pin.state.ref ?? pin.state.branch,
        requirement: pin.requirement)
      return ResolvedSource(
        parsed: parsed,
        identity: pin.identity,
        checkoutURL: URL(fileURLWithPath: pin.location),
        revision: Git.revision(at: URL(fileURLWithPath: pin.location)) ?? pin.state.revision,
        requestedRef: pin.requirement?.checkoutRef ?? pin.state.ref ?? pin.state.branch,
        resolvedVersion: pin.state.version
      )
    case "remoteSourceControl":
      var parsed = try SourceParser.parse(
        pin.location, currentDirectory: environment.projectDirectory)
      parsed.requirement = pin.requirement
      parsed.ref = pin.requirement?.checkoutRef ?? pin.state.ref ?? pin.state.branch
      let result: Git.CheckoutResult
      if let requirement = pin.requirement {
        result = try Git.ensureCheckout(
          url: parsed.url,
          requirement: requirement,
          cacheDirectory: AgentRegistry.sourceCacheDirectory(
            scope: scope, environment: environment),
          identity: pin.identity
        )
      } else {
        let checkout = try Git.ensureCheckout(
          url: parsed.url,
          ref: pin.state.ref ?? pin.state.branch ?? pin.state.revision,
          cacheDirectory: AgentRegistry.sourceCacheDirectory(
            scope: scope, environment: environment),
          identity: pin.identity
        )
        result = Git.CheckoutResult(
          url: checkout,
          selectedRef: pin.state.ref ?? pin.state.branch,
          selectedVersion: pin.state.version
        )
      }
      return ResolvedSource(
        parsed: parsed,
        identity: pin.identity,
        checkoutURL: result.url,
        revision: Git.revision(at: result.url) ?? pin.state.revision,
        requestedRef: result.selectedRef ?? pin.state.ref ?? pin.state.branch,
        resolvedVersion: result.selectedVersion ?? pin.state.version
      )
    default:
      throw CoreError.unsupported("cannot restore source kind \(pin.kind)")
    }
  }
}
