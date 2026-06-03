import Foundation
import Testing
import Yams

@testable import Core

@Suite("Manifest Field Model")
struct ManifestFieldModelTests {
  @Test func mapsSkillSourceManifestFieldsToInstallAndWatchState() throws {
    let fixture = """
      schema_version: 1
      install_target: "${CODEX_HOME:-$HOME/.codex}/skills"
      sources:
        - id: "sketch-hq-skills"
          kind: "github"
          repo: "sketch-hq/skills"
          ref: "main"
          checkout: "../references/sources/github/sketch-hq/skills"
          install: true
          update_policy: "notify"
          locked_commit: "5d0fb33b5e53b0bf84de03a2579536f7073ce668"
          last_checked_commit: "5d0fb33b5e53b0bf84de03a2579536f7073ce668"
          skills:
            - name: "sketch-implement-design"
              path: "skills/sketch-implement-design"
              install: true
      """
    let manifest = try YAMLDecoder().decode(SkillSourcesManifestFixture.self, from: fixture)
    let source = try #require(manifest.sources.first)
    #expect(source.id == "sketch-hq-skills")
    #expect(source.repo == "sketch-hq/skills")
    #expect(source.ref == "main")
    #expect(source.checkout == "../references/sources/github/sketch-hq/skills")
    #expect(source.install == true)
    #expect(source.skills.map(\.path) == ["skills/sketch-implement-design"])

    let watch = WatchRecord(
      watchID: source.id,
      source: SourcePin(
        identity: source.repo,
        kind: "remoteSourceControl",
        location: source.repo,
        state: PinState(revision: source.lockedCommit, branch: source.ref)),
      checkoutPath: source.checkout,
      watchBaseline: source.lockedCommit,
      currentHead: nil,
      watchedPaths: source.skills.map {
        WatchPathState(
          path: $0.path,
          tracking: TrackingState(lastCheckedCommit: source.lastCheckedCommit))
      })

    #expect(watch.watchBaseline == source.lockedCommit)
    #expect(watch.currentHead == nil)
    #expect(watch.watchedPaths[0].tracking.lastCheckedCommit == source.lastCheckedCommit)
    #expect(source.skills[0].install == true)
  }

  @Test func separatesWatchStateFromExternalRoutingReceipts() throws {
    let fixture = """
      schema_version: 1
      sources:
        - id: snarktank-ralph-prd
          repo: snarktank/ralph
          feed: https://github.com/snarktank/ralph/commits/main.atom
          branch: main
          last_seen: 6c53cb0b831ebe8739c6a003e22af14902d8b0b5
          tracking:
            last_checked_commit: 6c53cb0b831ebe8739c6a003e22af14902d8b0b5
            last_checked_at: 2026-05-10
          review_coverage:
            status: reviewed
            reviewed_commit: 6c53cb0b831ebe8739c6a003e22af14902d8b0b5
            reviewed_at: 2026-05-24
            granularity: source
            outcome: accepted
            open_items: 0
          type: skill-source
          policy: compare-prd-generator-skill-boundary
          targets:
            - root
          watch_paths:
            - skills/prd/SKILL.md
            - skills/ralph/SKILL.md
          review_segments:
            - id: prd-generator-skill
              label: PRD generator skill
              source_type: skill-source
              policy: compare-product-planning-prd-boundary
              paths:
                - skills/prd/SKILL.md
              targets:
                - root
              review_coverage:
                status: integrated
                reviewed_commit: 6c53cb0b831ebe8739c6a003e22af14902d8b0b5
                reviewed_at: 2026-05-10
                granularity: path
                outcome: integrated
                open_items: 0
      """
    let manifest = try YAMLDecoder().decode(WatchManifestFixture.self, from: fixture)
    let source = try #require(manifest.sources.first)
    #expect(source.watchPaths.count == 2)
    #expect(source.reviewSegments.count == 1)
    #expect(source.policy == "compare-prd-generator-skill-boundary")
    #expect(source.targets == ["root"])

    let watch = WatchRecord(
      watchID: source.id,
      source: SourcePin(
        identity: source.repo,
        kind: "remoteSourceControl",
        location: source.repo,
        state: PinState(branch: source.branch)),
      checkoutPath: nil,
      watchBaseline: source.reviewCoverage.reviewedCommit,
      currentHead: nil,
      watchedPaths: source.watchPaths.map {
        WatchPathState(
          path: $0,
          lastSeen: source.lastSeen,
          tracking: source.tracking,
          reviewCoverage: source.reviewCoverage)
      })

    #expect(watch.watchedPaths.allSatisfy { $0.lastSeen == source.lastSeen })
    #expect(watch.watchedPaths.allSatisfy { $0.reviewCoverage.status == "reviewed" })
    #expect(watch.watchedPaths.allSatisfy { $0.reviewCoverage.openItems == 0 })
    #expect(source.type == "skill-source")
    #expect(source.reviewSegments[0].policy == "compare-product-planning-prd-boundary")
  }

}

private struct SkillSourcesManifestFixture: Decodable {
  var sources: [Source]

  struct Source: Decodable {
    var id: String
    var kind: String
    var repo: String
    var ref: String
    var checkout: String
    var install: Bool
    var updatePolicy: String
    var lockedCommit: String
    var lastCheckedCommit: String
    var skills: [InstallEntry]

    enum CodingKeys: String, CodingKey {
      case id
      case kind
      case repo
      case ref
      case checkout
      case install
      case updatePolicy = "update_policy"
      case lockedCommit = "locked_commit"
      case lastCheckedCommit = "last_checked_commit"
      case skills
    }
  }

  struct InstallEntry: Decodable {
    var name: String
    var path: String
    var install: Bool
  }
}

private struct WatchManifestFixture: Decodable {
  var sources: [Source]

  struct Source: Decodable {
    var id: String
    var repo: String
    var branch: String
    var lastSeen: String
    var tracking: TrackingState
    var reviewCoverage: ReviewCoverage
    var type: String
    var policy: String
    var targets: [String]
    var watchPaths: [String]
    var reviewSegments: [ReviewSegment]

    enum CodingKeys: String, CodingKey {
      case id
      case repo
      case branch
      case lastSeen = "last_seen"
      case tracking
      case reviewCoverage = "review_coverage"
      case type
      case policy
      case targets
      case watchPaths = "watch_paths"
      case reviewSegments = "review_segments"
    }
  }

  struct ReviewSegment: Decodable {
    var id: String
    var label: String
    var sourceType: String
    var policy: String
    var paths: [String]
    var targets: [String]
    var reviewCoverage: ReviewCoverage

    enum CodingKeys: String, CodingKey {
      case id
      case label
      case sourceType = "source_type"
      case policy
      case paths
      case targets
      case reviewCoverage = "review_coverage"
    }
  }
}
