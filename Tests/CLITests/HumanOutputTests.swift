import AgentsCore
import Foundation
import Testing

@testable import CLI

struct HumanOutputTests {
  private func diff(_ before: String?, _ after: String?) -> String {
    LineDiff.render(
      before: before.map { Data($0.utf8) }, after: after.map { Data($0.utf8) }, path: "rules.md")
  }

  @Test func insertionAndDeletion() {
    #expect(
      diff("a\nb\n", "a\nnew\nb\n")
        == "--- a/rules.md\n+++ b/rules.md\n@@ -1,2 +1,3 @@\n a\n+new\n b\n")
    #expect(
      diff("a\nold\nb\n", "a\nb\n")
        == "--- a/rules.md\n+++ b/rules.md\n@@ -1,3 +1,2 @@\n a\n-old\n b\n")
    #expect(diff(nil, "new\n") == "--- /dev/null\n+++ b/rules.md\n@@ -0,0 +1 @@\n+new\n")
    #expect(diff("old\n", nil) == "--- a/rules.md\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n")
  }

  @Test func contextMergingAndHunkOffsets() {
    let original = (1...20).map { "line \($0)\n" }.joined()
    let merged = original.replacingOccurrences(of: "line 4\n", with: "four\n")
      .replacingOccurrences(of: "line 11\n", with: "eleven\n")
    let separate = original.replacingOccurrences(of: "line 4\n", with: "four\n")
      .replacingOccurrences(of: "line 12\n", with: "twelve\n")
    #expect(diff(original, merged).components(separatedBy: "@@ -").count == 2)
    let result = diff(original, separate)
    #expect(result.contains("@@ -1,7 +1,7 @@"))
    #expect(result.contains("@@ -9,7 +9,7 @@"))
    #expect(!result.contains("line 8\n") && !result.contains("line 16\n"))
    let inserted = original.replacingOccurrences(of: "line 4\n", with: "new\nline 4\n")
      .replacingOccurrences(of: "line 14\n", with: "fourteen\n")
    #expect(diff(original, inserted).contains("@@ -11,7 +12,7 @@"))
  }

  @Test func newlineAndEmptyFiles() {
    #expect(
      diff("old", "new")
        == "--- a/rules.md\n+++ b/rules.md\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n"
    )
    #expect(diff("same", "same\n").contains("-same\n\\ No newline at end of file\n+same\n"))
    #expect(diff("", "line\n").contains("@@ -0,0 +1 @@\n+line\n"))
    #expect(diff(nil, "") == "empty file rules.md added\n")
    #expect(diff("", nil) == "empty file rules.md removed\n")
    #expect(diff("", "").isEmpty && diff(nil, nil).isEmpty)
    #expect(diff("same\n", "same\n").isEmpty)
  }

  @Test func unicodeBytesAndRepeatedLines() {
    #expect(diff("é\n", "e\u{301}\n").contains("-é\n+e\u{301}\n"))
    #expect(diff("a\nb\na\nb\n", "a\na\nb\nb\n").contains("@@ -1,4 +1,4 @@"))
    let long = String(repeating: "same\n", count: 10_000)
    #expect(diff(long + "old\n", long + "new\n").contains("@@ -9998,4 +9998,4 @@"))
  }

  @Test func binaryAndEntryKinds() {
    for bytes in [Data([255]), Data([0, 255])] {
      #expect(
        LineDiff.render(before: Data(), after: bytes, path: "file") == "Binary file file differs\n")
    }
    var output = ""
    Terminal.fileDifference(
      path: "run", before: .file(Data("same\n".utf8), executable: false),
      after: .file(Data("same\n".utf8), executable: true)
    ) { output += $0 }
    Terminal.fileDifference(path: "link", before: .symbolicLink("old"), after: .symbolicLink("new"))
    { output += $0 }
    Terminal.fileDifference(path: "dir", before: nil, after: .directory) { output += $0 }
    Terminal.fileDifference(path: "old-dir", before: .directory, after: nil) { output += $0 }
    #expect(
      output
        == "mode run: 644 -> 755\nlink link: old -> new\ndirectory dir added\ndirectory old-dir removed\n"
    )
    output = ""
    Terminal.fileDifference(
      path: "run", before: .file(Data("old\n".utf8), executable: false),
      after: .file(Data("new\n".utf8), executable: false)
    ) { output += $0 }
    #expect(!output.contains("mode") && output.contains("@@ -1 +1 @@"))
  }

  @Test func tabsAndControlCharactersStayVisible() {
    #expect(diff("a\tb\n", "a\tc\n").contains("-a\tb\n+a\tc\n"))
    #expect(
      diff("same\r\n", "same\n") == "--- a/rules.md\n+++ b/rules.md\n@@ -1 +1 @@\n-same\\r\n+same\n"
    )
    #expect(diff("old\r\n", "new\r\n").contains("-old\\r\n+new\\r\n"))
    #expect(diff(nil, "text\t\u{1b}[31m\0\n").contains("+text\t\\x1b[31m\\x00\n"))
    #expect(diff("old\r", "new\r").contains("-old\\r\n\\ No newline at end of file\n"))
    #expect(
      Terminal.line("a\tb\r\n\u{7}\u{7f}\u{9b}\u{202e}") == "a\tb\\r\\n\\x07\\x7f\\x9b\\u{202e}")
    for value in (0...0x9f).filter({ $0 != 9 && ($0 < 32 || $0 >= 0x7f) }) {
      let control = String(Unicode.Scalar(value)!)
      #expect(
        !Terminal.line(control).unicodeScalars.contains(
          where: CharacterSet.controlCharacters.contains))
    }
  }

  @Test func pathsRespectScopeAndDirectoryBoundaries() {
    let environment = RuntimeEnvironment(
      projectDirectory: URL(fileURLWithPath: "/home/me/project"),
      homeDirectory: URL(fileURLWithPath: "/home/me"), environment: [:])
    let project = HumanPaths(environment: environment)
    let user = HumanPaths(scope: .user, environment: environment)
    #expect(project.path("/home/me/project/AGENTS.md") == "AGENTS.md")
    #expect(project.path("/home/me/project") == ".")
    #expect(project.path("/home/me/project-two/AGENTS.md") == "~/project-two/AGENTS.md")
    #expect(project.path("/home/me-too/file") == "/home/me-too/file")
    #expect(project.path("/other/file") == "/other/file")
    #expect(user.path("/home/me/project/AGENTS.md") == "~/project/AGENTS.md")
    #expect(project.path("/home/me") == "~")
    #expect(project.source("local:/home/me/project") == "local:~/project")
    #expect(project.source("local:/other/rules") == "local:/other/rules")
    #expect(project.path("nested/file") == "nested/file")
  }

  @Test func itemOrderingPinsAndRepinning() {
    func item(
      _ name: String, source: String = "source", existed: Bool = true, exists: Bool = true,
      same: Bool = false, other: Bool = false
    ) -> HumanItem {
      HumanItem(
        name: name, source: source, existed: existed, exists: exists,
        oldRevision: "abcdef0123", newRevision: "1234567890", sameContent: same, otherChanges: other
      )
    }
    let items = HumanItem.ordered([
      item("a", exists: false), item("a", same: true), item("b"),
      item("a", source: "source-two"), item("a"), item("z", existed: false),
    ])
    #expect(items.map(\.change) == [.new, .changed, .changed, .changed, .repinned, .removed])
    #expect(items.map(\.name) == ["z", "a", "a", "b", "a", "a"])
    #expect(items[1].source == "source" && items[2].source == "source-two")
    #expect(item("a", same: true, other: true).change == .changed)
    #expect(items[4].render(paths: HumanPaths()) == "= repinned  a  source  abcdef0 -> 1234567\n")
    #expect(HumanItem.pin(revision: "abc123456") == "abc1234")
    #expect(HumanItem.pin(revision: nil) == "none")
  }

  @Test func multilineErrorsIndentEveryContinuation() {
    let error = CoreError.commandFailed(
      "git fetch origin\nfatal: Could not read from remote repository.\n\nError: remote text\n\n")
    #expect(
      Terminal.formatError(
        String(describing: error), remedy: Terminal.failureRemedy(error, command: Add()))
        == "Error: Command failed: git fetch origin\n  fatal: Could not read from remote repository.\n  \n  Error: remote text.\n  Check Git access and the source location.\n"
    )
  }

  @Test func errorLinesEscapeControlsAndPreserveTabs() {
    let message = "git\tfetch\u{1b}[31m\r failed\nError: remote\u{9b}31m\u{202e}text\n"
    let output = Terminal.formatError(message, remedy: "try again")
    #expect(
      output
        == "Error: git\tfetch\\x1b[31m\\r failed\n  Error: remote\\x9b31m\\u{202e}text.\n  Try again.\n"
    )
    #expect(
      !output.unicodeScalars.contains {
        $0 != "\n" && $0 != "\t" && CharacterSet.controlCharacters.contains($0)
      })
  }

  @Test(arguments: ["", "\n", "\n\n", "\n \t\n"])
  func errorsDropTrailingBlankLines(_ suffix: String) {
    #expect(
      Terminal.formatError("Command failed\nfatal: no access" + suffix, remedy: "try again")
        == "Error: Command failed\n  fatal: no access.\n  Try again.\n")
    #expect(
      Terminal.formatError("Command failed\nfatal: no access." + suffix, remedy: "try again")
        == "Error: Command failed\n  fatal: no access.\n  Try again.\n")
  }

  @Test(arguments: ["failure", "failure."])
  func crlfErrorsPunctuateBeforeLineEndings(_ detail: String) {
    #expect(
      Terminal.formatError("Command failed\r\nfatal: \(detail)\r\n\r\n", remedy: "try again")
        == "Error: Command failed\\r\n  fatal: failure.\\r\n  Try again.\n")
  }

  @Test(arguments: ["Problem", "Problem.", "Problem?", "Problem!", "Problem。"])
  func errorsKeepPunctuation(_ message: String) {
    let result = Terminal.formatError(message, remedy: "try again")
    let expected = message == "Problem" ? "Problem." : message
    #expect(result == "Error: " + expected + "\n  Try again.\n")
    #expect(!result.contains(".;") && !result.contains("?;"))
    #expect(Terminal.formatError(message, remedy: "Try again.") == result)
  }
}
