import AgentsCore
import AgentsSkills
import Foundation
import Testing

@testable import CLI

struct ConventionTests {
  @Test(arguments: [false, true])
  func fixtureCleansUpOnReturnAndThrow(_ fail: Bool) throws {
    var root: URL?
    func useFixture() throws {
      let fixture = try CLIFixture()
      root = fixture.root
      try fixture.skill()
      try fixture.commit()
      if fail { throw CoreError.notFound("fixture") }
    }
    if fail {
      #expect(throws: CoreError.notFound("fixture")) { try useFixture() }
    } else {
      try useFixture()
    }
    #expect(!FileManager.default.fileExists(atPath: try #require(root).path))
  }

  @Test func recoveryReportsAndRetriesOnce() throws {
    var attempts = 0
    var notices: [String] = []
    let value = try withRecovery(
      report: { notices.append($0) },
      {
        attempts += 1
        if attempts == 1 { throw CoreError.transactionRecovered("fixture") }
        return 42
      })
    #expect(value == 42 && attempts == 2)
    #expect(notices == ["Recovered interrupted transaction at fixture; retrying once."])
  }

  @Test func repeatedRecoveryAndOtherFailuresPropagate() {
    var attempts = 0
    #expect(throws: CoreError.transactionRecovered("fixture")) {
      try withRecovery(
        report: { _ in },
        {
          attempts += 1
          throw CoreError.transactionRecovered("fixture")
        })
    }
    #expect(attempts == 2)
    attempts = 0
    #expect(throws: CoreError.invalidState("fixture")) {
      try withRecovery(
        report: { _ in Issue.record("Unexpected recovery notice") },
        {
          attempts += 1
          throw CoreError.invalidState("fixture")
        })
    }
    #expect(attempts == 1)
  }

  @Test func typedFileSnapshotsHaveStableEncoding() throws {
    let entries: [SkillFileEntry] = [
      .file(Data([0, 255]), executable: false), .directory, .symbolicLink("../target"),
    ]
    let encoded = try JSONEncoder().encode(entries.map(FileEntry.init))
    let values = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
    #expect(values[0]["kind"] as? String == "file")
    #expect(values[0]["base64"] as? String == "AP8=")
    #expect(values[0]["executable"] as? Bool == false)
    #expect(values[1] as? [String: String] == ["kind": "directory"])
    #expect(values[2] as? [String: String] == ["kind": "symlink", "destination": "../target"])
  }

  @Test func diagnosticsAreSingleLineAndEscapeTerminalControls() {
    #expect(Terminal.line("a\nb\rc\t\u{1B}[31m") == "a\\nb\\rc\t\\x1b[31m")
  }
}
