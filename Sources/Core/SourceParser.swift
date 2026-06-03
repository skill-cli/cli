import Foundation

public enum SourceType: String, Codable, Equatable, Sendable {
  case local
  case github
  case gitlab
  case git
  case wellKnown = "well-known"
}

public struct ParsedSource: Codable, Equatable, Sendable {
  public var type: SourceType
  public var url: String
  public var localPath: String?
  public var ref: String?
  public var requirement: SourceRequirement?
  public var subpath: String?
  public var skillFilter: String?

  public init(
    type: SourceType,
    url: String,
    localPath: String? = nil,
    ref: String? = nil,
    requirement: SourceRequirement? = nil,
    subpath: String? = nil,
    skillFilter: String? = nil
  ) {
    self.type = type
    self.url = url
    self.localPath = localPath
    self.ref = ref
    self.requirement = requirement
    self.subpath = subpath
    self.skillFilter = skillFilter
  }
}

public enum SourceParser {
  private static let aliases = [
    "coinbase/agentWallet": "coinbase/agentic-wallet-skills"
  ]

  public static func parse(
    _ rawInput: String,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> ParsedSource {
    var input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else {
      throw CoreError.invalidSource("empty source")
    }

    let typed = try parseTypedSelectors(input)
    input = typed.inputWithoutSelectors

    if isLocalPath(input) {
      let resolved = URL(fileURLWithPath: input, relativeTo: currentDirectory).standardizedFileURL
        .path
      return try applyTypedSelectors(
        to: ParsedSource(type: .local, url: resolved, localPath: resolved),
        typed: typed)
    }

    let fragment = parseFragmentRef(input)
    input = fragment.inputWithoutFragment

    if let alias = aliases[input] {
      input = alias
    }

    if let stripped = input.removingPrefix("github:") {
      let parsed = try parse(
        appendFragment(stripped, ref: fragment.ref, skillFilter: fragment.skillFilter),
        currentDirectory: currentDirectory)
      return try applyTypedSelectors(to: parsed, typed: typed)
    }

    if let stripped = input.removingPrefix("gitlab:") {
      let parsed = try parse(
        appendFragment(
          "https://gitlab.com/\(stripped)", ref: fragment.ref, skillFilter: fragment.skillFilter),
        currentDirectory: currentDirectory)
      return try applyTypedSelectors(to: parsed, typed: typed)
    }

    if let github = try parseGitHubURL(
      input, fragmentRef: fragment.ref, fragmentSkillFilter: fragment.skillFilter)
    {
      return try applyTypedSelectors(to: github, typed: typed)
    }

    if let gitlab = try parseGitLabURL(input, fragmentRef: fragment.ref) {
      return try applyTypedSelectors(to: gitlab, typed: typed)
    }

    if let shorthand = try parseGitHubShorthand(
      input, fragmentRef: fragment.ref, fragmentSkillFilter: fragment.skillFilter)
    {
      return try applyTypedSelectors(to: shorthand, typed: typed)
    }

    if isWellKnownURL(input) {
      return try applyTypedSelectors(to: ParsedSource(type: .wellKnown, url: input), typed: typed)
    }

    return try applyTypedSelectors(
      to: ParsedSource(
        type: .git, url: input, ref: fragment.ref, requirement: fragment.requirement),
      typed: typed)
  }

  public static func ownerRepo(for parsed: ParsedSource) -> String? {
    guard parsed.type != .local else { return nil }

    if parsed.url.hasPrefix("git@"), let colon = parsed.url.firstIndex(of: ":") {
      return String(parsed.url[parsed.url.index(after: colon)...]).removingSuffix(".git")
        .nilIfMissingSlash
    }

    if parsed.url.hasPrefix("ssh://"), let url = URL(string: parsed.url) {
      return String(url.path.dropFirst()).removingSuffix(".git").nilIfMissingSlash
    }

    guard let url = URL(string: parsed.url), url.scheme == "http" || url.scheme == "https" else {
      return nil
    }
    return String(url.path.dropFirst()).removingSuffix(".git").nilIfMissingSlash
  }

  public static func identity(for parsed: ParsedSource) -> String {
    if let ownerRepo = ownerRepo(for: parsed) {
      return ownerRepo.lowercased()
    }
    if parsed.type == .local {
      return URL(fileURLWithPath: parsed.localPath ?? parsed.url).lastPathComponent.lowercased()
    }
    if let url = URL(string: parsed.url) {
      let path = String(url.path.dropFirst()).removingSuffix(".git")
      return ([url.host, path].compactMap { $0 }.joined(separator: "/")).lowercased()
    }
    return parsed.url.lowercased()
  }

  private static func isLocalPath(_ input: String) -> Bool {
    input == "." || input == ".." || input.hasPrefix("./") || input.hasPrefix("../")
      || input.hasPrefix("/")
      || input.range(of: #"^[A-Za-z]:[/\\]"#, options: .regularExpression) != nil
  }

  private static func parseGitHubURL(
    _ input: String, fragmentRef: String?, fragmentSkillFilter: String?
  ) throws -> ParsedSource? {
    guard let url = URL(string: input), url.host == "github.com" else { return nil }
    let components = url.path.split(separator: "/", omittingEmptySubsequences: true).map(
      String.init)
    guard components.count >= 2 else { return nil }
    let owner = components[0]
    let repo = components[1].removingSuffix(".git")
    var ref = fragmentRef
    var subpath: String?

    if components.count >= 4, components[2] == "tree" {
      ref = components[3]
      if components.count > 4 {
        subpath = try PathSafety.sanitizeSubpath(components.dropFirst(4).joined(separator: "/"))
      }
    }

    return ParsedSource(
      type: .github,
      url: "https://github.com/\(owner)/\(repo).git",
      ref: ref,
      requirement: ref.map(SourceRequirement.ref),
      subpath: subpath,
      skillFilter: fragmentSkillFilter
    )
  }

  private static func parseGitLabURL(_ input: String, fragmentRef: String?) throws -> ParsedSource?
  {
    guard let url = URL(string: input), let host = url.host, host != "github.com" else {
      return nil
    }
    let components = url.path.split(separator: "/", omittingEmptySubsequences: true).map(
      String.init)
    guard components.count >= 2 else { return nil }

    if let marker = components.firstIndex(of: "-"), components.count > marker + 2,
      components[marker + 1] == "tree"
    {
      let repoPath = components[..<marker].joined(separator: "/").removingSuffix(".git")
      let ref = components[marker + 2]
      let subpath =
        components.count > marker + 3
        ? try PathSafety.sanitizeSubpath(components.dropFirst(marker + 3).joined(separator: "/"))
        : nil
      return ParsedSource(
        type: .gitlab,
        url: "\(url.scheme ?? "https")://\(hostWithPort(url))/\(repoPath).git",
        ref: ref.isEmpty ? fragmentRef : ref,
        requirement: (ref.isEmpty ? fragmentRef : ref).map(SourceRequirement.ref),
        subpath: subpath
      )
    }

    guard host == "gitlab.com" else { return nil }
    let repoPath = components.joined(separator: "/").removingSuffix(".git")
    guard repoPath.contains("/") else { return nil }
    return ParsedSource(
      type: .gitlab,
      url: "\(url.scheme ?? "https")://\(hostWithPort(url))/\(repoPath).git",
      ref: fragmentRef,
      requirement: fragmentRef.map(SourceRequirement.ref)
    )
  }

  private static func hostWithPort(_ url: URL) -> String {
    guard let host = url.host else { return "" }
    if let port = url.port {
      return "\(host):\(port)"
    }
    return host
  }

  private static func parseGitHubShorthand(
    _ input: String, fragmentRef: String?, fragmentSkillFilter: String?
  ) throws -> ParsedSource? {
    guard !input.hasPrefix("."), !input.hasPrefix("/") else { return nil }

    if let atIndex = input.firstIndex(of: "@") {
      let repoPart = String(input[..<atIndex])
      let skill = String(input[input.index(after: atIndex)...])
      let parts = repoPart.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
      if parts.count == 2, !repoPart.contains(":") {
        if skill.contains(":"), let label = skill.split(separator: ":", maxSplits: 1).first,
          !typedSelectorLabels.contains(String(label))
        {
          throw CoreError.invalidSource("unknown typed source selector '\(label)'")
        }
        return ParsedSource(
          type: .github,
          url: "https://github.com/\(parts[0])/\(parts[1]).git",
          ref: fragmentRef,
          requirement: fragmentRef.map(SourceRequirement.ref),
          skillFilter: fragmentSkillFilter ?? skill
        )
      }
    }

    guard !input.contains(":") else { return nil }

    let parts = input.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard parts.count >= 2 else { return nil }
    let subpath =
      parts.count > 2
      ? try PathSafety.sanitizeSubpath(parts.dropFirst(2).joined(separator: "/")) : nil
    return ParsedSource(
      type: .github,
      url: "https://github.com/\(parts[0])/\(parts[1]).git",
      ref: fragmentRef,
      requirement: fragmentRef.map(SourceRequirement.ref),
      subpath: subpath,
      skillFilter: fragmentSkillFilter
    )
  }

  private static func isWellKnownURL(_ input: String) -> Bool {
    guard let url = URL(string: input), url.scheme == "http" || url.scheme == "https" else {
      return false
    }
    let excludedHosts = ["github.com", "gitlab.com", "raw.githubusercontent.com", "huggingface.co"]
    if let host = url.host, excludedHosts.contains(host) {
      return false
    }
    return !input.hasSuffix(".git")
  }

  private static func parseFragmentRef(_ input: String) -> (
    inputWithoutFragment: String, ref: String?, skillFilter: String?,
    requirement: SourceRequirement?
  ) {
    guard let hashIndex = input.firstIndex(of: "#") else {
      return (input, nil, nil, nil)
    }

    let without = String(input[..<hashIndex])
    let fragment = String(input[input.index(after: hashIndex)...])
    guard !fragment.isEmpty, looksLikeGitSource(without) else {
      return (input, nil, nil, nil)
    }

    if let atIndex = fragment.firstIndex(of: "@") {
      let ref = String(fragment[..<atIndex]).removingPercentEncoding ?? String(fragment[..<atIndex])
      let skill =
        String(fragment[fragment.index(after: atIndex)...]).removingPercentEncoding
        ?? String(fragment[fragment.index(after: atIndex)...])
      let value = ref.isEmpty ? nil : ref
      return (without, value, skill.isEmpty ? nil : skill, value.map(SourceRequirement.ref))
    }

    let value = fragment.removingPercentEncoding ?? fragment
    return (without, value, nil, SourceRequirement.ref(value))
  }

  private static let requirementSelectorLabels = Set([
    "branch", "revision", "exact", "from", "minor", "ref",
  ])
  private static let valueSelectorLabels = Set(["path", "skill"])
  private static let typedSelectorLabels = requirementSelectorLabels.union(valueSelectorLabels)

  private static func parseTypedSelectors(_ input: String) throws -> (
    inputWithoutSelectors: String,
    requirement: SourceRequirement?,
    subpath: String?,
    skillFilter: String?
  ) {
    guard let selectorStart = firstTypedSelectorStart(in: input) else {
      return (input, nil, nil, nil)
    }
    let base = String(input[..<selectorStart])
    let selectorText = String(input[selectorStart...])
    var requirement: SourceRequirement?
    var subpath: String?
    var skillFilter: String?

    let segments = selectorText.split(separator: "@", omittingEmptySubsequences: true).map(
      String.init)
    guard !segments.isEmpty else {
      return (input, nil, nil, nil)
    }
    for segment in segments {
      let parts = segment.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        .map(String.init)
      guard parts.count == 2 else {
        throw CoreError.invalidSource("invalid typed source selector '@\(segment)'")
      }
      let label = parts[0]
      let value = parts[1].removingPercentEncoding ?? parts[1]
      guard typedSelectorLabels.contains(label) else {
        throw CoreError.invalidSource("unknown typed source selector '\(label)'")
      }
      guard !value.isEmpty else {
        throw CoreError.invalidSource("empty typed source selector '\(label)'")
      }
      if requirementSelectorLabels.contains(label) {
        guard requirement == nil else {
          throw CoreError.invalidSource("multiple source requirement selectors")
        }
        requirement = try requirementSelector(label: label, value: value)
      } else if label == "path" {
        guard subpath == nil, skillFilter == nil else {
          throw CoreError.invalidSource("multiple source selection selectors")
        }
        subpath = try PathSafety.sanitizeSubpath(value)
      } else if label == "skill" {
        guard subpath == nil, skillFilter == nil else {
          throw CoreError.invalidSource("multiple source selection selectors")
        }
        skillFilter = value
      }
    }
    return (base, requirement, subpath, skillFilter)
  }

  private static func firstTypedSelectorStart(in input: String) -> String.Index? {
    var index = input.startIndex
    while let at = input[index...].firstIndex(of: "@") {
      let after = input.index(after: at)
      let rest = input[after...]
      if let colon = rest.firstIndex(of: ":") {
        let label = String(rest[..<colon])
        if typedSelectorLabels.contains(label) {
          return at
        }
      }
      index = after
    }
    return nil
  }

  private static func requirementSelector(label: String, value: String) throws -> SourceRequirement
  {
    switch label {
    case "branch":
      return .branch(value)
    case "revision":
      return .revision(value)
    case "exact":
      return .exact(value)
    case "from":
      return .upToNextMajor(from: value)
    case "minor":
      return .upToNextMinor(from: value)
    case "ref":
      return .ref(value)
    default:
      throw CoreError.invalidSource("unknown typed source selector '\(label)'")
    }
  }

  private static func applyTypedSelectors(
    to parsed: ParsedSource,
    typed: (
      inputWithoutSelectors: String, requirement: SourceRequirement?, subpath: String?,
      skillFilter: String?
    )
  ) throws -> ParsedSource {
    var result = parsed
    if let requirement = typed.requirement {
      if let existing = result.requirement, existing != requirement {
        throw CoreError.invalidSource("conflicting source requirements")
      }
      result.requirement = requirement
      result.ref = requirement.checkoutRef
    }
    if let subpath = typed.subpath {
      if let existing = result.subpath, existing != subpath {
        throw CoreError.invalidSource("conflicting source paths")
      }
      result.subpath = subpath
    }
    if let skillFilter = typed.skillFilter {
      if let existing = result.skillFilter, existing != skillFilter {
        throw CoreError.invalidSource("conflicting skill selectors")
      }
      result.skillFilter = skillFilter
    }
    return result
  }

  private static func looksLikeGitSource(_ input: String) -> Bool {
    if input.hasPrefix("github:") || input.hasPrefix("gitlab:") || input.hasPrefix("git@") {
      return true
    }
    if input.range(of: #"^ssh://.+\.git($|[/?])"#, options: [.regularExpression, .caseInsensitive])
      != nil
    {
      return true
    }
    if input.range(
      of: #"^https?://.+\.git($|[/?])"#, options: [.regularExpression, .caseInsensitive]) != nil
    {
      return true
    }
    if let url = URL(string: input), url.scheme == "http" || url.scheme == "https" {
      let path = url.path
      if url.host == "github.com" {
        return path.range(
          of: #"^/[^/]+/[^/]+(\.git)?(/tree/[^/]+(/.*)?)?/?$"#, options: .regularExpression) != nil
      }
      if url.host == "gitlab.com" {
        return path.split(separator: "/").count >= 2
      }
    }
    return !input.contains(":") && !input.hasPrefix(".") && !input.hasPrefix("/")
      && input.range(of: #"^([^/]+)/([^/]+)(/(.+)|@(.+))?$"#, options: .regularExpression) != nil
  }

  private static func appendFragment(_ input: String, ref: String?, skillFilter: String?) -> String
  {
    guard let ref else { return input }
    return "\(input)#\(ref)\(skillFilter.map { "@\($0)" } ?? "")"
  }
}

extension String {
  fileprivate func removingPrefix(_ prefix: String) -> String? {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
  }

  fileprivate func removingSuffix(_ suffix: String) -> String {
    hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
  }

  fileprivate var nilIfMissingSlash: String? {
    contains("/") ? self : nil
  }
}
