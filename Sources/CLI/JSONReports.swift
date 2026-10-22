import AgentsCore
import AgentsSkills
import Foundation

// These DTOs own the CLI schema independently of core's Codable representations.
struct InstalledListReport: Encodable {
  let schemaVersion = 1
  let kind = "installed"
  let scope: String
  let skills: [InstalledItem]

  init(scope: String, skills: [InstalledSkill]) {
    self.scope = scope
    self.skills = skills.map(InstalledItem.init)
  }
}

struct InstalledItem: Encodable {
  let name: String
  let agent: String
  let path: String
  let source: String?
  let installed: Bool
  let status: String
  let mode: String?

  init(_ skill: InstalledSkill) {
    name = skill.name
    agent = skill.agent.rawValue
    path = skill.path
    source = skill.sourceIdentity
    installed = skill.isInstalled
    status = skill.status.rawValue
    mode = skill.mode?.rawValue
  }
}

struct SourceListReport: Encodable {
  let schemaVersion = 1
  let kind = "source"
  let scope: String
  let source: String
  let skills: [AvailableItem]

  init(scope: String, outcome: AddOutcome) {
    self.scope = scope
    source = outcome.sourceID
    skills = outcome.availableSkills.sorted { $0.name < $1.name }.map(AvailableItem.init)
  }
}

struct AvailableItem: Encodable {
  let name: String
  let description: String
  let path: String
  let skillFile: String
  let plugin: String?

  init(_ skill: Skill) {
    name = skill.name
    description = skill.description
    path = skill.path
    skillFile = skill.skillFile
    plugin = skill.pluginName
  }
}

struct UpdateReport: Encodable {
  let schemaVersion = 1
  let scope: String
  let changed: Bool
  let skills: [UpdateItem]

  init(scope: String, results: [UpdateResult]) {
    self.scope = scope
    changed = results.contains(where: \.changed)
    skills = results.map(UpdateItem.init)
  }
}

struct UpdateItem: Encodable {
  let name: String
  let source: String
  let changed: Bool
  let oldRevision: String?
  let newRevision: String?
  let oldVersion: String?
  let newVersion: String?
  let oldHash: String?
  let newHash: String?
  let lockMissing: Bool
  let membership: [MembershipChange]
  let files: [FileChange]

  init(_ result: UpdateResult) {
    name = result.skill
    source = result.sourceIdentity
    changed = result.changed
    oldRevision = result.oldRevision
    newRevision = result.newRevision
    oldVersion = result.oldVersion
    newVersion = result.newVersion
    oldHash = result.oldHash
    newHash = result.newHash
    lockMissing = result.lockMissing
    membership = result.membership.map(MembershipChange.init)
    files = result.changes.map(FileChange.init)
  }
}

struct MembershipChange: Encodable {
  let agent: String
  let path: String
  let before: MembershipState
  let after: MembershipState

  init(_ change: SkillMembershipChange) {
    agent = change.agent.rawValue
    path = change.path
    before = MembershipState(change.before)
    after = MembershipState(change.after)
  }
}

struct MembershipState: Encodable {
  let kind: String
  var mode: String?

  init(_ membership: SkillMembership) {
    switch membership {
    case .absent:
      kind = "absent"
    case .installed(let mode):
      kind = "installed"
      self.mode = mode.rawValue
    }
  }
}

struct FileChange: Encodable {
  let path: String
  let before: FileEntry?
  let after: FileEntry?

  init(_ change: SkillFileChange) {
    path = change.path
    before = change.before.map(FileEntry.init)
    after = change.after.map(FileEntry.init)
  }

  init(_ change: WatchFileChange) {
    path = change.path
    before = change.before.map(FileEntry.init)
    after = change.after.map(FileEntry.init)
  }
}

struct FileEntry: Encodable {
  let kind: String
  var base64: String?
  var destination: String?
  var executable: Bool?

  init(_ entry: SkillFileEntry) {
    switch entry {
    case .file(let data, let executable):
      kind = "file"
      base64 = data.base64EncodedString()
      self.executable = executable
    case .directory:
      kind = "directory"
    case .symbolicLink(let target):
      kind = "symlink"
      destination = target
    }
  }

  init(_ entry: WatchFileEntry) {
    switch entry {
    case .file(let data, let executable):
      kind = "file"
      base64 = data.base64EncodedString()
      self.executable = executable
    case .directory:
      kind = "directory"
    case .symbolicLink(let target):
      kind = "symlink"
      destination = target
    }
  }
}

struct DoctorOutput: Encodable {
  let schemaVersion = 1
  let ok: Bool
  let roots: [DoctorRoot]

  init(roots: [DoctorRoot]) {
    self.roots = roots
    ok = roots.allSatisfy(\.ok)
  }
}

struct DoctorRoot: Encodable {
  let root: String
  let scope: String
  let ok: Bool
  let checks: [CheckItem]

  init(root: String, scope: String, report: DoctorReport, environment: RuntimeEnvironment) {
    self.root = root
    self.scope = scope
    checks = report.checks.map { CheckItem($0, environment: environment) }
    ok = !checks.contains { $0.status == "error" }
  }
}

struct CheckItem: Encodable {
  let kind: String
  let id: String
  let status: String
  let message: String
  let path: String?

  init(_ check: DoctorCheck, environment: RuntimeEnvironment) {
    kind = "skills"
    id = check.id
    status = check.id == "pending-recovery" ? "error" : check.status.rawValue
    message =
      check.id == "pending-recovery"
      ? Self.pendingRecoveryMessage(path: check.path, environment: environment) : check.message
    path = check.path
  }

  private static func pendingRecoveryMessage(path: String?, environment: RuntimeEnvironment)
    -> String
  {
    let state = path.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    let action: String
    switch state {
    case StateStore(scope: .user, environment: environment).directory.path:
      action = "'skill install --scope user'"
    case StateStore(scope: .project, environment: environment).directory.path:
      action = "'skill install' in '\(environment.projectDirectory.path)'"
    default:
      action = "a command that changes the affected state directory"
    }
    return "Transaction recovery is pending; run \(action) to finish recovery."
  }
}

struct InstallReport: Encodable {
  let schemaVersion = 1
  let scope: String
  let skills: [RestoredSkill]

  init(scope: String, skills: [InstallResult]) {
    self.scope = scope
    self.skills = skills.map(RestoredSkill.init)
  }
}

struct RestoredSkill: Encodable {
  let name: String
  let agent: String
  let mode: String
  let path: String

  init(_ result: InstallResult) {
    name = result.skill
    agent = result.agent.rawValue
    mode = result.mode.rawValue
    path = result.path
  }
}
