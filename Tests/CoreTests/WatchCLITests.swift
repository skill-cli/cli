import Foundation
import Testing

@testable import Core

@Suite("Watch CLI")
struct WatchCLITests {
  @Test func managesWatchLedgerAndReviewCursorsFromCLI() throws {
    let project = try watchCLITemporaryDirectory()
    let home = try watchCLITemporaryDirectory()
    let repo = project.appendingPathComponent("repo")
    let skill = repo.appendingPathComponent("skills/demo")
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try """
    ---
    name: demo
    description: Demo skill
    ---
    """.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let extra = repo.appendingPathComponent("skills/extra")
    try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
    try """
    ---
    name: extra
    description: Extra skill
    ---
    """.write(to: extra.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try watchCLIInitGitRepo(repo)
    let baseline = try watchCLIGitHead(repo)

    let env = ["HOME": home.path]
    let removedWatch = try runWatchSkills(
      ["watch", "--help"], currentDirectory: project, environment: env)
    #expect(removedWatch.exitCode != 0)

    var status = try runWatchSkills(
      ["add", repo.path, "--watch-only", "--path", "skills/demo"],
      currentDirectory: project,
      environment: env)
    #expect(status.exitCode == 0)
    #expect(status.stdout.contains("watched repo path skills/demo"))

    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.exitCode == 0)
    #expect(status.stdout.contains("baseline \(baseline)"))
    #expect(status.stdout.contains("path skills/demo"))

    #expect(
      try runWatchSkills(
        ["add", repo.path, "--watch-only", "--path", "skills/extra"],
        currentDirectory: project,
        environment: env
      ).exitCode == 0)
    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.stdout.contains("path skills/extra"))

    #expect(
      try runWatchSkills(
        ["remove", repo.path, "--watch", "--path", "skills/extra"],
        currentDirectory: project,
        environment: env
      ).exitCode == 0)
    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(!status.stdout.contains("path skills/extra"))

    try "changed".write(
      to: skill.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
    try ProcessRunner.run(
      "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "change"])
    let head = try watchCLIGitHead(repo)

    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.stdout.contains("head \(head)"))
    #expect(status.stdout.contains("checked -"))
    #expect(status.stdout.contains("seen -"))
    #expect(status.stdout.contains("reviewed -"))

    let diff = try runWatchSkills(
      ["diff", repo.path, "--watch", "--path", "skills/demo"],
      currentDirectory: project,
      environment: env)
    #expect(diff.exitCode == 0)
    #expect(diff.stdout.contains("skills/demo/notes.md"))
    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.stdout.contains("checked -"))

    let check = try runWatchSkills(
      ["review", "check", repo.path, "--watch", "--path", "skills/demo"],
      currentDirectory: project,
      environment: env)
    #expect(check.exitCode == 0)
    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.stdout.contains("checked \(head)"))
    #expect(status.stdout.contains("seen -"))

    let seen = try runWatchSkills(
      ["review", "seen", repo.path, "--watch", "--path", "skills/demo", "--note", "looked"],
      currentDirectory: project,
      environment: env)
    #expect(seen.exitCode == 0)
    status = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(status.stdout.contains("seen \(head)"))
    #expect(status.stdout.contains("reviewed -"))

    let done = try runWatchSkills(
      ["review", "done", repo.path, "--watch", "--path", "skills/demo", "--note", "accepted"],
      currentDirectory: project,
      environment: env)
    #expect(done.exitCode == 0)
    status = try runWatchSkills(
      ["status", repo.path, "--watch", "--history"],
      currentDirectory: project,
      environment: env)
    #expect(status.stdout.contains("reviewed \(head)"))
    #expect(status.stdout.contains("event done skills/demo \(head) accepted"))

    let list = try runWatchSkills(
      ["list", "--watch", "--json"], currentDirectory: project, environment: env)
    #expect(list.exitCode == 0)
    #expect(list.stdout.contains("\"watch_id\" : \"repo\""))

    let remove = try runWatchSkills(
      ["remove", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(remove.exitCode == 0)
    let missing = try runWatchSkills(
      ["status", repo.path, "--watch"], currentDirectory: project, environment: env)
    #expect(missing.exitCode != 0)
  }

}

private struct WatchCLIResult {
  var stdout: String
  var stderr: String
  var exitCode: Int32
}

private func runWatchSkills(
  _ arguments: [String],
  currentDirectory: URL,
  environment: [String: String]
) throws -> WatchCLIResult {
  let process = Process()
  process.executableURL = watchSkillsExecutableURL()
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory
  var env = ProcessInfo.processInfo.environment
  for (key, value) in environment {
    env[key] = value
  }
  process.environment = env
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()
  return WatchCLIResult(
    stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    exitCode: process.terminationStatus
  )
}

private func watchSkillsExecutableURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(".build/debug/skill")
}

private func watchCLITemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-watch-cli-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func watchCLIInitGitRepo(_ repo: URL) throws {
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "init", repo.path])
  try ProcessRunner.run(
    "/usr/bin/env",
    arguments: ["git", "-C", repo.path, "config", "user.email", "tests@example.com"])
  try ProcessRunner.run(
    "/usr/bin/env", arguments: ["git", "-C", repo.path, "config", "user.name", "Tests"])
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "add", "."])
  try ProcessRunner.run(
    "/usr/bin/env", arguments: ["git", "-C", repo.path, "commit", "-m", "initial"])
}

private func watchCLIGitHead(_ repo: URL) throws -> String {
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "rev-parse", "HEAD"])
    .stdout
    .trimmingCharacters(in: .whitespacesAndNewlines)
}
