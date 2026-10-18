import AgentsSkills

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
  let oldHash: String?
  let newHash: String?
  let files: [FileChange]

  init(_ result: UpdateResult) {
    name = result.skill
    source = result.sourceIdentity
    changed = result.changed
    oldRevision = result.oldRevision
    newRevision = result.newRevision
    oldHash = result.oldHash
    newHash = result.newHash
    files = result.changes.map(FileChange.init)
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
}

struct FileEntry: Encodable {
  let kind: String
  var base64: String?
  var destination: String?

  init(_ entry: SkillFileEntry) {
    switch entry {
    case .file(let data):
      kind = "file"
      base64 = data.base64EncodedString()
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

  init(root: String, scope: String, report: DoctorReport) {
    self.root = root
    self.scope = scope
    ok = report.ok
    checks = report.checks.map(CheckItem.init)
  }
}

struct CheckItem: Encodable {
  let id: String
  let status: String
  let message: String
  let path: String?

  init(_ check: DoctorCheck) {
    id = check.id
    status = check.status.rawValue
    message = check.message
    path = check.path
  }
}
