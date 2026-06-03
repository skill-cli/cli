import Foundation

@testable import Core

func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("skill-cli-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func initGitRepo(_ repo: URL) throws {
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

func gitHead(_ repo: URL) throws -> String {
  try ProcessRunner.run("/usr/bin/env", arguments: ["git", "-C", repo.path, "rev-parse", "HEAD"])
    .stdout
    .trimmingCharacters(in: .whitespacesAndNewlines)
}
