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

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public init?(_ raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let body =
      trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
    let core = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
    let parts = core.split(separator: ".").map(String.init)
    guard parts.count == 3,
      let major = Int(parts[0]),
      let minor = Int(parts[1]),
      let patch = Int(parts[2])
    else {
      return nil
    }
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public var description: String {
    "\(major).\(minor).\(patch)"
  }

  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    if lhs.major != rhs.major {
      return lhs.major < rhs.major
    }
    if lhs.minor != rhs.minor {
      return lhs.minor < rhs.minor
    }
    return lhs.patch < rhs.patch
  }
}
