import Testing

@testable import Core

@Suite("Semantic Versions")
struct SemanticVersionTests {
  @Test func preservesPrereleaseAndBuildIdentifiers() throws {
    let version = try #require(SemanticVersion(" v0.1.0-alpha.4+build.01 "))
    #expect(version.description == "0.1.0-alpha.4+build.01")
    #expect(version.prerelease == ["alpha", "4"])
    #expect(version.buildMetadata == ["build", "01"])
    #expect(version != SemanticVersion("0.1.0-alpha.1"))
    #expect(version != SemanticVersion("0.1.0"))
    #expect(version == SemanticVersion("0.1.0-alpha.4+other"))
  }

  @Test func ordersPrereleasesBySemanticPrecedence() throws {
    let ordered = try [
      "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
      "1.0.0-beta.2", "1.0.0-beta.10", "1.0.0-rc.1", "1.0.0",
    ].map { try #require(SemanticVersion($0)) }
    for (lower, upper) in zip(ordered, ordered.dropFirst()) {
      #expect(lower < upper)
    }
    #expect(ordered.reversed().sorted() == ordered)
    #expect(
      try #require(SemanticVersion("1.0.0-999999999999999999999999"))
        < #require(SemanticVersion("1.0.0-1000000000000000000000000")))
    #expect(SemanticVersion("1.0.0+first") == SemanticVersion("1.0.0+second"))
  }

  @Test(arguments: [
    ("1.0.0", "1.0.0", "2.0.0", true),
    ("1.5.0", "1.0.0", "2.0.0", true),
    ("0.9.9", "1.0.0", "2.0.0", false),
    ("2.0.0", "1.0.0", "2.0.0", false),
    ("2.0.1", "1.0.0", "2.0.0", false),
    ("1.0.0-alpha.1", "1.0.0", "2.0.0", false),
    ("1.5.0-beta.1", "1.0.0", "2.0.0", false),
    ("2.0.0-alpha.1", "1.0.0", "2.0.0", false),
    ("1.0.5", "1.0.0", "1.1.0", true),
    ("1.1.0-alpha.1", "1.0.0", "1.1.0", false),
  ])
  func stableRangeMembership(
    candidate: String, lower: String, upper: String, expected: Bool
  ) throws {
    let version = try #require(SemanticVersion(candidate))
    let lowerBound = try #require(SemanticVersion(lower))
    let upperBound = try #require(SemanticVersion(upper))
    #expect(version.isInRange(from: lowerBound, to: upperBound) == expected)
  }

  @Test(arguments: [
    ("0.1.0-alpha.0", "1.0.0", false),
    ("0.1.0-alpha.1", "1.0.0", true),
    ("0.1.0-alpha.4", "0.1.0", true),
    ("0.1.0-alpha.4", "1.0.0", true),
    ("0.1.0", "1.0.0", true),
    ("0.1.1", "1.0.0", true),
    ("0.1.1-alpha.1", "1.0.0", false),
    ("0.2.0-alpha.1", "1.0.0", false),
    ("1.0.0-alpha.1", "1.0.0", false),
    ("1.0.0", "1.0.0", false),
  ])
  func prereleaseLowerBoundMembership(candidate: String, upper: String, expected: Bool) throws {
    let version = try #require(SemanticVersion(candidate))
    let lowerBound = try #require(SemanticVersion("0.1.0-alpha.1"))
    let upperBound = try #require(SemanticVersion(upper))
    #expect(version.isInRange(from: lowerBound, to: upperBound) == expected)
  }

  @Test(arguments: [
    ("0.9.0", false),
    ("1.0.0", true),
    ("1.5.0", true),
    ("1.5.0-beta.1", false),
    ("2.0.0-alpha.1", true),
    ("2.0.0-beta.1", true),
    ("2.0.0-beta.3", false),
    ("2.0.0-beta.4", false),
    ("2.0.0", false),
  ])
  func prereleaseUpperBoundMembership(candidate: String, expected: Bool) throws {
    let version = try #require(SemanticVersion(candidate))
    let lowerBound = try #require(SemanticVersion("1.0.0"))
    let upperBound = try #require(SemanticVersion("2.0.0-beta.3"))
    #expect(version.isInRange(from: lowerBound, to: upperBound) == expected)
  }

  @Test(arguments: [
    ("1.0.0+candidate", "1.0.0+lower", "2.0.0+upper", true),
    ("1.5.0+candidate", "1.0.0", "2.0.0", true),
    ("2.0.0+candidate", "1.0.0", "2.0.0+upper", false),
    ("1.5.0-beta.1+candidate", "1.0.0+lower", "2.0.0+upper", false),
    ("1.0.0-alpha.1+candidate", "1.0.0-alpha.1+lower", "1.0.0", true),
    ("2.0.0-beta.1+candidate", "1.0.0", "2.0.0-beta.3+upper", true),
    ("2.0.0-beta.3+candidate", "1.0.0", "2.0.0-beta.3+upper", false),
  ])
  func buildMetadataDoesNotChangeRangeMembership(
    candidate: String, lower: String, upper: String, expected: Bool
  ) throws {
    let version = try #require(SemanticVersion(candidate))
    let lowerBound = try #require(SemanticVersion(lower))
    let upperBound = try #require(SemanticVersion(upper))
    #expect(version.isInRange(from: lowerBound, to: upperBound) == expected)
  }

  @Test(arguments: [
    "", "1.2", "1..2.3", "-1.2.3", "01.2.3", "1.2.03", "1.2.3-",
    "1.2.3-alpha..1", "1.2.3-alpha.01", "1.2.3-alpha_1", "1.2.3-α",
    "1.2.3+", "1.2.3+build..1", "1.2.3+build+other",
  ])
  func rejectsMalformedVersions(_ raw: String) {
    #expect(SemanticVersion(raw) == nil)
  }
}
