import Foundation

public struct SourceRequirement: Codable, Equatable, Sendable {
  public var kind: String
  public var value: String
  public var upperBound: String?

  public init(kind: String, value: String, upperBound: String? = nil) {
    self.kind = kind
    self.value = value
    self.upperBound = upperBound
  }

  public static func branch(_ value: String) -> SourceRequirement {
    SourceRequirement(kind: "branch", value: value)
  }

  public static func revision(_ value: String) -> SourceRequirement {
    SourceRequirement(kind: "revision", value: value)
  }

  public static func exact(_ value: String) -> SourceRequirement {
    SourceRequirement(kind: "exact", value: value)
  }

  public static func upToNextMajor(from value: String) -> SourceRequirement {
    SourceRequirement(kind: "from", value: value)
  }

  public static func upToNextMinor(from value: String) -> SourceRequirement {
    SourceRequirement(kind: "minor", value: value)
  }

  public static func range(from value: String, to upperBound: String) -> SourceRequirement {
    SourceRequirement(kind: "range", value: value, upperBound: upperBound)
  }

  public static func ref(_ value: String) -> SourceRequirement {
    SourceRequirement(kind: "ref", value: value)
  }

  public var checkoutRef: String? {
    switch kind {
    case "branch", "revision", "ref":
      return value
    default:
      return nil
    }
  }

  public var isVersionRequirement: Bool {
    switch kind {
    case "exact", "from", "minor", "range":
      return true
    default:
      return false
    }
  }
}

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
  public var major: Int
  public var minor: Int
  public var patch: Int
  public var prerelease: [String]
  public var buildMetadata: [String]

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = []
    self.buildMetadata = []
  }

  public init?(_ raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let body =
      trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
    let metadataParts = body.split(
      separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    let versionParts = metadataParts[0].split(
      separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let parts = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts.allSatisfy({ Self.isNumeric(String($0)) && ($0.count == 1 || !$0.hasPrefix("0")) }),
      let major = Int(parts[0]),
      let minor = Int(parts[1]),
      let patch = Int(parts[2])
    else {
      return nil
    }
    let prerelease =
      versionParts.count == 2
      ? versionParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      : []
    let buildMetadata =
      metadataParts.count == 2
      ? metadataParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      : []
    guard
      prerelease.allSatisfy({
        Self.isIdentifier($0) && (!Self.isNumeric($0) || $0.count == 1 || !$0.hasPrefix("0"))
      }), buildMetadata.allSatisfy(Self.isIdentifier)
    else {
      return nil
    }
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
    self.buildMetadata = buildMetadata
  }

  public var description: String {
    let suffix = prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: ".")
    let metadata = buildMetadata.isEmpty ? "" : "+" + buildMetadata.joined(separator: ".")
    return "\(major).\(minor).\(patch)" + suffix + metadata
  }

  // Build metadata does not affect SemVer precedence.
  public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
      && lhs.prerelease == rhs.prerelease
  }

  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    if lhs.major != rhs.major {
      return lhs.major < rhs.major
    }
    if lhs.minor != rhs.minor {
      return lhs.minor < rhs.minor
    }
    if lhs.patch != rhs.patch {
      return lhs.patch < rhs.patch
    }
    if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
      return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
    }
    for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
      if left == right { continue }
      let leftNumeric = isNumeric(left)
      let rightNumeric = isNumeric(right)
      if leftNumeric && rightNumeric && left.count != right.count {
        return left.count < right.count
      }
      if leftNumeric != rightNumeric {
        return leftNumeric
      }
      return left < right
    }
    return lhs.prerelease.count < rhs.prerelease.count
  }

  private static func isNumeric(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
  }

  private static func isIdentifier(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy {
        $0 == 45 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
      }
  }
}
