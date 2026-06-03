import Foundation

public struct ProcessOutput: Equatable, Sendable {
  public var stdout: String
  public var stderr: String
  public var exitCode: Int32
}

public enum ProcessRunner {
  @discardableResult
  public static func run(_ executable: String, arguments: [String], workingDirectory: URL? = nil)
    throws -> ProcessOutput
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let output = ProcessOutput(
      stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? "",
      stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? "",
      exitCode: process.terminationStatus
    )

    guard output.exitCode == 0 else {
      throw CoreError.commandFailed(
        ([executable] + arguments).joined(separator: " ") + "\n" + output.stderr)
    }
    return output
  }
}

public enum Git {
  public struct CheckoutResult: Equatable, Sendable {
    public var url: URL
    public var selectedRef: String?
    public var selectedVersion: String?

    public init(url: URL, selectedRef: String? = nil, selectedVersion: String? = nil) {
      self.url = url
      self.selectedRef = selectedRef
      self.selectedVersion = selectedVersion
    }
  }

  public static func revision(at repository: URL) -> String? {
    try? ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repository.path, "rev-parse", "HEAD"]
    ).stdout
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func ensureCheckout(
    url: String, ref: String?, cacheDirectory: URL, identity: String
  ) throws -> URL {
    try ensureCheckout(
      url: url,
      requirement: ref.map(SourceRequirement.ref),
      cacheDirectory: cacheDirectory,
      identity: identity
    ).url
  }

  public static func ensureCheckout(
    url: String, requirement: SourceRequirement?, cacheDirectory: URL, identity: String
  ) throws -> CheckoutResult {
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    let checkout = cacheDirectory.appendingPathComponent(PathSafety.sanitizeName(identity))
    if FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
      _ = try? ProcessRunner.run(
        "/usr/bin/env",
        arguments: ["git", "-C", checkout.path, "fetch", "--all", "--tags", "--prune"])
    } else {
      if FileManager.default.fileExists(atPath: checkout.path) {
        try FileManager.default.removeItem(at: checkout)
      }
      try ProcessRunner.run("/usr/bin/env", arguments: ["git", "clone", url, checkout.path])
    }

    let resolved = try resolveRequirement(requirement, in: checkout)
    if let ref = resolved.selectedRef, !ref.isEmpty {
      try ProcessRunner.run(
        "/usr/bin/env", arguments: ["git", "-C", checkout.path, "checkout", ref])
    }
    return CheckoutResult(
      url: checkout,
      selectedRef: resolved.selectedRef,
      selectedVersion: resolved.selectedVersion
    )
  }

  public static func materializeCheckout(
    repository: URL, commit: String, cacheDirectory: URL, identity: String
  ) throws -> URL {
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    let checkout = cacheDirectory.appendingPathComponent(
      PathSafety.sanitizeName("\(identity)-\(String(commit.prefix(12)))"))
    if FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
      let current = revision(at: checkout)
      if current == commit {
        return checkout
      }
      _ = try? ProcessRunner.run(
        "/usr/bin/env",
        arguments: ["git", "-C", checkout.path, "fetch", "--all", "--tags", "--prune"])
    } else {
      if FileManager.default.fileExists(atPath: checkout.path) {
        try FileManager.default.removeItem(at: checkout)
      }
      try ProcessRunner.run(
        "/usr/bin/env", arguments: ["git", "clone", repository.path, checkout.path])
    }
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", checkout.path, "checkout", commit])
    return checkout
  }

  public static func changedFiles(repository: URL, base: String?, head: String, path: String)
    -> [ChangedFile]
  {
    guard let base, !base.isEmpty, base != head else {
      return listFiles(repository: repository, path: path).map {
        ChangedFile(path: $0, status: "A", additions: nil, deletions: nil)
      }
    }

    let safePath = (try? PathSafety.sanitizeSubpath(path)) ?? "."
    let nameStatus =
      (try? ProcessRunner.run(
        "/usr/bin/env",
        arguments: [
          "git", "-C", repository.path, "diff", "--name-status", base, head, "--", safePath,
        ]
      ).stdout) ?? ""
    let numstat =
      (try? ProcessRunner.run(
        "/usr/bin/env",
        arguments: ["git", "-C", repository.path, "diff", "--numstat", base, head, "--", safePath]
      ).stdout) ?? ""

    var stats: [String: (Int?, Int?)] = [:]
    for line in numstat.split(separator: "\n").map(String.init) {
      let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard parts.count >= 3 else { continue }
      stats[parts[2]] = (Int(parts[0]), Int(parts[1]))
    }

    return nameStatus.split(separator: "\n").compactMap { raw in
      let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard parts.count >= 2 else { return nil }
      let filePath = parts.last ?? parts[1]
      let stat = stats[filePath]
      return ChangedFile(path: filePath, status: parts[0], additions: stat?.0, deletions: stat?.1)
    }
  }

  private static func listFiles(repository: URL, path: String) -> [String] {
    let safePath = (try? PathSafety.sanitizeSubpath(path)) ?? "."
    if let output = try? ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repository.path, "ls-files", safePath]
    ).stdout,
      !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return output.split(separator: "\n").map(String.init)
    }
    let root = (try? PathSafety.resolvedChild(base: repository, subpath: safePath)) ?? repository
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey])
    else {
      return []
    }
    var files: [String] = []
    for case let url as URL in enumerator {
      if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        files.append(url.path.replacingOccurrences(of: repository.path + "/", with: ""))
      }
    }
    return files.sorted()
  }

  private static func resolveRequirement(
    _ requirement: SourceRequirement?, in checkout: URL
  ) throws -> (selectedRef: String?, selectedVersion: String?) {
    guard let requirement else {
      return (nil, nil)
    }
    switch requirement.kind {
    case "branch":
      return (remoteBranchRef(requirement.value, in: checkout) ?? requirement.value, nil)
    case "revision", "ref":
      return (requirement.value, nil)
    case "exact":
      let version = try parsedVersion(requirement.value, label: "exact")
      guard let match = tags(in: checkout).first(where: { $0.version == version }) else {
        throw CoreError.notFound("tag for exact version \(requirement.value)")
      }
      return (match.tag, match.version.description)
    case "from":
      let lower = try parsedVersion(requirement.value, label: "from")
      let upper = SemanticVersion(major: lower.major + 1, minor: 0, patch: 0)
      let match = try highestTag(in: checkout, lowerBound: lower, upperBound: upper)
      return (match.tag, match.version.description)
    case "minor":
      let lower = try parsedVersion(requirement.value, label: "minor")
      let upper = SemanticVersion(major: lower.major, minor: lower.minor + 1, patch: 0)
      let match = try highestTag(in: checkout, lowerBound: lower, upperBound: upper)
      return (match.tag, match.version.description)
    case "range":
      let lower = try parsedVersion(requirement.value, label: "from")
      guard let upperRaw = requirement.upperBound else {
        throw CoreError.invalidSource("range requirement missing upper bound")
      }
      let upper = try parsedVersion(upperRaw, label: "to")
      let match = try highestTag(in: checkout, lowerBound: lower, upperBound: upper)
      return (match.tag, match.version.description)
    default:
      throw CoreError.invalidSource("unsupported source requirement '\(requirement.kind)'")
    }
  }

  private static func parsedVersion(_ raw: String, label: String) throws -> SemanticVersion {
    guard let version = SemanticVersion(raw) else {
      throw CoreError.invalidSource("invalid \(label) version '\(raw)'")
    }
    return version
  }

  private static func remoteBranchRef(_ branch: String, in checkout: URL) -> String? {
    let remoteRef = "refs/remotes/origin/\(branch)"
    let output = try? ProcessRunner.run(
      "/usr/bin/env",
      arguments: ["git", "-C", checkout.path, "rev-parse", "--verify", remoteRef])
    return output == nil ? nil : "origin/\(branch)"
  }

  private static func highestTag(
    in checkout: URL, lowerBound: SemanticVersion, upperBound: SemanticVersion
  ) throws -> (tag: String, version: SemanticVersion) {
    guard lowerBound < upperBound else {
      throw CoreError.invalidSource("version upper bound must be greater than lower bound")
    }
    let candidates = tags(in: checkout)
      .filter { $0.version >= lowerBound && $0.version < upperBound }
      .sorted { lhs, rhs in
        if lhs.version == rhs.version {
          return lhs.tag < rhs.tag
        }
        return lhs.version < rhs.version
      }
    guard let match = candidates.last else {
      throw CoreError.notFound("tag in range \(lowerBound)..<\(upperBound)")
    }
    return match
  }

  private static func tags(in checkout: URL) -> [(tag: String, version: SemanticVersion)] {
    let output =
      (try? ProcessRunner.run(
        "/usr/bin/env", arguments: ["git", "-C", checkout.path, "tag", "--list"]
      ).stdout) ?? ""
    return output.split(separator: "\n").compactMap { raw in
      let tag = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
      guard let version = SemanticVersion(tag) else { return nil }
      return (tag, version)
    }
  }
}

public enum SourceResolver {
  public static func resolve(
    _ input: String, environment: RuntimeEnvironment,
    requirement override: SourceRequirement? = nil,
    refresh: Bool = false,
    scope: InstallScope = .project
  ) throws -> ResolvedSource {
    var parsed = try SourceParser.parse(input, currentDirectory: environment.projectDirectory)
    if let override {
      if let existing = parsed.requirement, existing != override {
        throw CoreError.invalidSource("conflicting source requirements")
      }
      parsed.requirement = override
      parsed.ref = override.checkoutRef
    }
    let identity = SourceParser.identity(for: parsed)

    switch parsed.type {
    case .local:
      guard let localPath = parsed.localPath else {
        throw CoreError.invalidSource("local source has no path")
      }
      let checkout = URL(fileURLWithPath: localPath).standardizedFileURL
      guard FileManager.default.fileExists(atPath: checkout.path) else {
        throw CoreError.invalidSource("Local path does not exist: \(checkout.path)")
      }
      if let requirement = parsed.requirement {
        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path)
        else {
          throw CoreError.invalidSource("local source requirements require a git repository")
        }
        let cache = AgentRegistry.sourceCacheDirectory(scope: scope, environment: environment)
        let result = try Git.ensureCheckout(
          url: checkout.path,
          requirement: requirement,
          cacheDirectory: cache,
          identity: identity
        )
        var gitParsed = parsed
        gitParsed.type = .git
        gitParsed.url = checkout.path
        gitParsed.localPath = nil
        return ResolvedSource(
          parsed: gitParsed,
          identity: identity,
          checkoutURL: result.url,
          revision: Git.revision(at: result.url),
          requestedRef: result.selectedRef,
          resolvedVersion: result.selectedVersion
        )
      }
      return ResolvedSource(
        parsed: parsed,
        identity: identity,
        checkoutURL: checkout,
        revision: Git.revision(at: checkout),
        requestedRef: parsed.ref
      )
    case .github, .gitlab, .git:
      let cache = AgentRegistry.sourceCacheDirectory(scope: scope, environment: environment)
      let result = try Git.ensureCheckout(
        url: parsed.url,
        requirement: parsed.requirement,
        cacheDirectory: cache,
        identity: identity
      )
      return ResolvedSource(
        parsed: parsed,
        identity: identity,
        checkoutURL: result.url,
        revision: Git.revision(at: result.url),
        requestedRef: result.selectedRef ?? parsed.ref,
        resolvedVersion: result.selectedVersion
      )
    case .wellKnown:
      let provider = WellKnownProvider()
      let skills = try provider.fetchAllSkills(from: parsed.url)
      let checkout = AgentRegistry.wellKnownCacheDirectory(scope: scope, environment: environment)
        .appendingPathComponent(PathSafety.sanitizeName(provider.sourceIdentifier(for: parsed.url)))
      try provider.materialize(skills, into: checkout)
      return ResolvedSource(
        parsed: parsed,
        identity: "wellknown/\(provider.sourceIdentifier(for: parsed.url))",
        checkoutURL: checkout,
        revision: skills.compactMap(\.digest).sorted().joined(separator: ",").nilIfEmpty,
        requestedRef: nil
      )
    }
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
