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

public enum ResolvedInstallSkipReason: String, Codable, Equatable, Sendable {
  case sourceMissing = "source missing"
  case skillFileMissing = "skill file missing"
}

public struct ResolvedInstallSkip: Codable, Equatable, Sendable {
  public var skill: String
  public var sourceIdentity: String
  public var reason: ResolvedInstallSkipReason
  public var path: String

  public init(
    skill: String, sourceIdentity: String, reason: ResolvedInstallSkipReason, path: String
  ) {
    self.skill = skill
    self.sourceIdentity = sourceIdentity
    self.reason = reason
    self.path = path
  }
}

public struct ResolvedInstallReport: Sendable {
  public var installed: [InstallResult]
  public var skipped: [ResolvedInstallSkip]

  public init(installed: [InstallResult], skipped: [ResolvedInstallSkip] = []) {
    self.installed = installed
    self.skipped = skipped
  }
}

public struct InstalledSkill: Codable, Equatable, Sendable {
  public var name: String
  public var agent: AgentID
  public var scope: InstallScope
  public var path: String
  public var sourceIdentity: String?
  public var isInstalled: Bool
  public var status: InstalledSkillStatus
  public var mode: InstallMode?
  public var materialization: InstallMaterialization?
  public var sourcePath: String?
  public var linkTarget: String?
  public var watchID: String?
  public var reviewedCommit: String?
  public var lastCheckedCommit: String?

  public init(
    name: String, agent: AgentID, scope: InstallScope, path: String,
    sourceIdentity: String? = nil,
    isInstalled: Bool = true,
    status: InstalledSkillStatus? = nil,
    mode: InstallMode? = nil,
    materialization: InstallMaterialization? = nil,
    sourcePath: String? = nil,
    linkTarget: String? = nil,
    watchID: String? = nil,
    reviewedCommit: String? = nil, lastCheckedCommit: String? = nil
  ) {
    self.name = name
    self.agent = agent
    self.scope = scope
    self.path = path
    self.sourceIdentity = sourceIdentity
    self.isInstalled = isInstalled
    self.status = status ?? (isInstalled ? .installed : .missing)
    self.mode = mode
    self.materialization = materialization
    self.sourcePath = sourcePath
    self.linkTarget = linkTarget
    self.watchID = watchID
    self.reviewedCommit = reviewedCommit
    self.lastCheckedCommit = lastCheckedCommit
  }
}

public enum InstalledSkillStatus: String, Codable, Equatable, Sendable {
  case installed
  case missing
  case brokenLink = "broken-link"
  case copyDrift = "copy-drift"
  case sourceMissing = "source-missing"
  case copyFallback = "copy-fallback"
  case editLinked = "edit-linked"
  case installedOnly = "installed-only"
}

public enum DoctorCheckStatus: String, Codable, Equatable, Sendable {
  case ok
  case warning
  case error
}

public struct DoctorCheck: Codable, Equatable, Sendable {
  public var id: String
  public var status: DoctorCheckStatus
  public var message: String
  public var hint: String?
  public var path: String?

  public init(
    id: String,
    status: DoctorCheckStatus,
    message: String,
    hint: String? = nil,
    path: String? = nil
  ) {
    self.id = id
    self.status = status
    self.message = message
    self.hint = hint
    self.path = path
  }
}

public struct DoctorReport: Codable, Equatable, Sendable {
  public var ok: Bool
  public var checks: [DoctorCheck]

  public init(checks: [DoctorCheck]) {
    self.checks = checks
    self.ok = !checks.contains { $0.status == .error }
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
    if options.mode == .edit, options.watch || options.watchOnly {
      throw CoreError.invalidSource("--mode edit cannot be combined with --watch or --watch-only")
    }
    if options.mode == .edit {
      try validateEditableInput(options)
    }
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
    if options.mode == .edit {
      try validateEditableSource(source)
    }
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
    var managedByPath: [String: InstalledSkill] = [:]
    if let managed = try? listManaged(scope: scope, agents: agents, environment: environment) {
      for skill in managed {
        let key = "\(skill.agent.rawValue)\u{1f}\(URL(fileURLWithPath: skill.path).standardizedFileURL.path)"
        if managedByPath[key] == nil {
          managedByPath[key] = skill
        }
      }
    }
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
          if let managed = managedByPath[seenKey] {
            installed.append(managed)
            continue
          }
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
              status: .installedOnly,
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
          let inspection = inspectInstallation(
            source: source,
            pinnedSkill: pinnedSkill,
            installation: installation,
            destination: destination,
            environment: environment
          )
          listed.append(
            InstalledSkill(
              name: pinnedSkill.name,
              agent: installation.agent,
              scope: installation.scope,
              path: destination.path,
              sourceIdentity: source.identity,
              isInstalled: inspection.isInstalled,
              status: inspection.status,
              mode: installation.mode,
              materialization: inspection.materialization,
              sourcePath: inspection.sourcePath,
              linkTarget: inspection.linkTarget,
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

  public static func doctor(
    scope: InstallScope, agents: [AgentID], environment: RuntimeEnvironment
  ) throws -> DoctorReport {
    var checks: [DoctorCheck] = []
    let lockURL = InstallLockStore.lockURL(scope: scope, environment: environment)
    let lockExists = FileManager.default.fileExists(atPath: lockURL.path)
    checks.append(
      DoctorCheck(
        id: "resolved-file",
        status: lockExists ? .ok : .warning,
        message: lockExists
          ? "resolved state found for \(scope.rawValue) scope"
          : "no resolved state found for \(scope.rawValue) scope",
        hint: lockExists ? nil : "Run skill add <source> before restoring managed installs.",
        path: lockURL.path
      ))

    let managed = try listManaged(scope: scope, agents: agents, environment: environment)
    if managed.isEmpty {
      checks.append(
        DoctorCheck(
          id: "managed-installs",
          status: .warning,
          message: "no managed skill installations found",
          hint: "Use skill list --all to inspect unmanaged installed skills."))
    }

    for skill in managed {
      let status = doctorStatus(for: skill.status)
      checks.append(
        DoctorCheck(
          id: "skill.\(skill.agent.rawValue).\(PathSafety.sanitizeName(skill.name))",
          status: status,
          message: "\(skill.name) for \(skill.agent.rawValue): \(skill.status.rawValue)",
          hint: doctorHint(for: skill.status),
          path: skill.path
        ))
    }

    let managedKeys = Set(
      managed.map { "\($0.agent.rawValue)\u{1f}\(PathSafety.sanitizeName($0.name))" })
    let installedOnly = try listInstalled(scope: scope, agents: agents, environment: environment)
      .filter {
        !managedKeys.contains("\($0.agent.rawValue)\u{1f}\(PathSafety.sanitizeName($0.name))")
      }
    for skill in installedOnly {
      checks.append(
        DoctorCheck(
          id: "installed-only.\(skill.agent.rawValue).\(PathSafety.sanitizeName(skill.name))",
          status: .warning,
          message: "\(skill.name) for \(skill.agent.rawValue): installed-only",
          hint: "This skill is present on disk but not tracked in resolved state.",
          path: skill.path
        ))
    }

    return DoctorReport(checks: checks)
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
    try installResolvedReport(scope: scope, environment: environment).installed
  }

  public static func installResolvedReport(
    scope: InstallScope = .project, environment: RuntimeEnvironment
  ) throws -> ResolvedInstallReport {
    let lock = try InstallLockStore.load(scope: scope, environment: environment)
    var results: [InstallResult] = []
    var skipped: [ResolvedInstallSkip] = []

    for sourcePin in lock.pins {
      let source = try resolvedSource(from: sourcePin, scope: scope, environment: environment)
      for pinnedSkill in sourcePin.skills {
        guard pinnedSkill.installations.contains(where: { $0.scope == scope }) else {
          continue
        }
        let skillFile = source.checkoutURL.appendingPathComponent(pinnedSkill.path)
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
          let sourcePath = source.checkoutURL.path
          let sourceMissing =
            sourcePin.kind == "localFileSystem"
            && !FileManager.default.fileExists(atPath: sourcePath)
          skipped.append(
            ResolvedInstallSkip(
              skill: pinnedSkill.name,
              sourceIdentity: sourcePin.identity,
              reason: sourceMissing ? .sourceMissing : .skillFileMissing,
              path: sourceMissing ? sourcePath : skillFile.path))
          continue
        }
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

    return ResolvedInstallReport(installed: results, skipped: skipped)
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
        let needsEditRestore = editInstallationsNeedRestore(
          source: sourcePin,
          pinnedSkill: pinnedSkill,
          scope: scope,
          environment: environment
        )

        if apply, changed || needsEditRestore {
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
    if mode == .edit {
      throw CoreError.invalidSource("--mode edit cannot be used with update --from-watch")
    }
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

  private struct InstallationInspection {
    var isInstalled: Bool
    var status: InstalledSkillStatus
    var materialization: InstallMaterialization?
    var sourcePath: String?
    var linkTarget: String?
  }

  private static func validateEditableSource(_ source: ResolvedSource) throws {
    guard source.parsed.type == .local, source.parsed.requirement == nil, source.watchID == nil
    else {
      throw CoreError.invalidSource("--mode edit requires an unpinned local source")
    }
  }

  private static func validateEditableInput(_ options: AddOptions) throws {
    if options.sourceRequirement != nil {
      throw CoreError.invalidSource("--mode edit requires an unpinned local source")
    }
    let parsed = try SourceParser.parse(
      options.source, currentDirectory: options.environment.projectDirectory)
    guard parsed.type == .local, parsed.requirement == nil else {
      throw CoreError.invalidSource("--mode edit requires an unpinned local source")
    }
  }

  private static func inspectInstallation(
    source: SourcePin,
    pinnedSkill: PinnedSkill,
    installation: InstallationPin,
    destination: URL,
    environment: RuntimeEnvironment
  ) -> InstallationInspection {
    let sourcePath = sourceDirectoryPath(
      source: source, pinnedSkill: pinnedSkill, installation: installation)
    let linkTarget = resolvedSymlinkDestination(destination)?.path ?? installation.linkTarget
    let materialization = installation.materialization ?? inferredMaterialization(
      installation: installation, destination: destination)
    let isInstalled = installedSkillExists(at: destination)
    let status = installationStatus(
      source: source,
      pinnedSkill: pinnedSkill,
      installation: installation,
      destination: destination,
      isInstalled: isInstalled,
      materialization: materialization,
      sourcePath: sourcePath,
      linkTarget: linkTarget,
      environment: environment
    )
    return InstallationInspection(
      isInstalled: isInstalled,
      status: status,
      materialization: materialization,
      sourcePath: sourcePath,
      linkTarget: linkTarget
    )
  }

  private static func inferredMaterialization(
    installation: InstallationPin, destination: URL
  ) -> InstallMaterialization? {
    if installation.mode == .edit {
      return .editInstalled
    }
    if installation.mode == .copy {
      return .copyInstalled
    }
    if installation.fallback == true {
      return .copyFallback
    }
    return pathIsSymlink(destination) ? .linkInstalled : .copyInstalled
  }

  private static func installationStatus(
    source: SourcePin,
    pinnedSkill: PinnedSkill,
    installation: InstallationPin,
    destination: URL,
    isInstalled: Bool,
    materialization: InstallMaterialization?,
    sourcePath: String?,
    linkTarget: String?,
    environment: RuntimeEnvironment
  ) -> InstalledSkillStatus {
    if installation.mode == .edit {
      guard let sourcePath,
        FileManager.default.fileExists(atPath: URL(fileURLWithPath: sourcePath).path)
      else {
        return .sourceMissing
      }
      guard isInstalled else {
        return pathIsSymlink(destination) ? .brokenLink : .missing
      }
      guard pathIsSymlink(destination) else {
        return .copyDrift
      }
      if editLinkIsHealthy(
        sourcePath: sourcePath,
        linkTarget: linkTarget,
        destination: destination,
        installation: installation,
        environment: environment
      ) {
        return .editLinked
      }
      return .brokenLink
    }

    guard isInstalled else {
      return pathIsSymlink(destination) ? .brokenLink : .missing
    }
    if materialization == .copyFallback || installation.fallback == true {
      return .copyFallback
    }
    if let sourcePath, !FileManager.default.fileExists(atPath: sourcePath) {
      return .sourceMissing
    }
    if copyDrifted(
      source: source,
      pinnedSkill: pinnedSkill,
      destination: destination,
      sourcePath: sourcePath
    ) {
      return .copyDrift
    }
    return .installed
  }

  private static func copyDrifted(
    source: SourcePin, pinnedSkill: PinnedSkill, destination: URL, sourcePath: String?
  ) -> Bool {
    if let sourcePath, FileManager.default.fileExists(atPath: sourcePath),
      let hash = try? FileHash.folderHash(URL(fileURLWithPath: sourcePath)),
      hash != pinnedSkill.contentHash
    {
      return true
    }
    if source.kind == "localFileSystem", sourcePath == nil,
      let inferred = sourceDirectoryPath(
        source: source, pinnedSkill: pinnedSkill, installation: nil),
      FileManager.default.fileExists(atPath: inferred),
      let hash = try? FileHash.folderHash(URL(fileURLWithPath: inferred)),
      hash != pinnedSkill.contentHash
    {
      return true
    }
    if let installedHash = try? FileHash.folderHash(destination),
      installedHash != pinnedSkill.contentHash
    {
      return true
    }
    return false
  }

  private static func editInstallationsNeedRestore(
    source: SourcePin,
    pinnedSkill: PinnedSkill,
    scope: InstallScope,
    environment: RuntimeEnvironment
  ) -> Bool {
    pinnedSkill.installations.contains { installation in
      guard installation.scope == scope, installation.mode == .edit else {
        return false
      }
      let destination = installationURL(for: installation, environment: environment)
      let inspection = inspectInstallation(
        source: source,
        pinnedSkill: pinnedSkill,
        installation: installation,
        destination: destination,
        environment: environment
      )
      return inspection.status != .editLinked
    }
  }

  private static func editLinkIsHealthy(
    sourcePath: String,
    linkTarget: String?,
    destination: URL,
    installation: InstallationPin,
    environment: RuntimeEnvironment
  ) -> Bool {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard let linkTarget else {
      return false
    }
    let targetURL = URL(fileURLWithPath: linkTarget)
    let canonical = AgentRegistry.canonicalSkillsDirectory(
      scope: installation.scope, environment: environment
    ).appendingPathComponent(destination.lastPathComponent)
    if sameInstallLocation(destination, canonical) {
      return sameResolvedLocation(targetURL, sourceURL)
    }
    return sameInstallLocation(targetURL, canonical)
      && sameResolvedLocation(canonical, sourceURL)
  }

  private static func sourceDirectoryPath(
    source: SourcePin, pinnedSkill: PinnedSkill, installation: InstallationPin?
  ) -> String? {
    if let sourcePath = installation?.sourcePath {
      return sourcePath
    }
    guard source.kind == "localFileSystem" else {
      return nil
    }
    let relativeSkillDirectory = skillDirectoryPath(from: pinnedSkill.path)
    return URL(fileURLWithPath: source.location)
      .appendingPathComponent(relativeSkillDirectory)
      .standardizedFileURL
      .path
  }

  private static func pathIsSymlink(_ path: URL) -> Bool {
    (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
  }

  private static func resolvedSymlinkDestination(_ path: URL) -> URL? {
    guard pathIsSymlink(path),
      let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path.path)
    else {
      return nil
    }
    let rawPath =
      target.hasPrefix("/")
      ? target
      : path.deletingLastPathComponent().path + "/" + target
    return URL(fileURLWithPath: lexicalStandardizedPath(rawPath))
  }

  private static func sameResolvedLocation(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL.path
      == rhs.resolvingSymlinksInPath().standardizedFileURL.path
  }

  private static func sameInstallLocation(_ lhs: URL, _ rhs: URL) -> Bool {
    normalizedInstallLocation(lhs) == normalizedInstallLocation(rhs)
  }

  private static func normalizedInstallLocation(_ url: URL) -> String {
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
    return lexicalStandardizedPath(parent + "/" + url.lastPathComponent)
  }

  private static func lexicalStandardizedPath(_ path: String) -> String {
    let isAbsolute = path.hasPrefix("/")
    var components: [String] = []
    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
      switch component {
      case ".":
        continue
      case "..":
        if let last = components.last, last != ".." {
          components.removeLast()
        } else if !isAbsolute {
          components.append("..")
        }
      default:
        components.append(String(component))
      }
    }
    let normalized = components.joined(separator: "/")
    if isAbsolute {
      return "/" + normalized
    }
    return normalized.isEmpty ? "." : normalized
  }

  private static func doctorStatus(for status: InstalledSkillStatus) -> DoctorCheckStatus {
    switch status {
    case .installed, .editLinked:
      return .ok
    case .copyFallback, .copyDrift, .installedOnly:
      return .warning
    case .missing, .brokenLink, .sourceMissing:
      return .error
    }
  }

  private static func doctorHint(for status: InstalledSkillStatus) -> String? {
    switch status {
    case .installed, .editLinked:
      return nil
    case .missing:
      return "Run skill install to restore from resolved state."
    case .brokenLink:
      return "Re-run skill add or skill install to recreate the link."
    case .copyDrift:
      return "Run skill update --apply to refresh the installed copy."
    case .sourceMissing:
      return "Restore the local source path or remove the resolved entry."
    case .copyFallback:
      return "The requested link install fell back to a copy; reinstall on a filesystem that supports symlinks if live linking is required."
    case .installedOnly:
      return "Use skill add to manage this skill or remove it manually if it is stale."
    }
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
