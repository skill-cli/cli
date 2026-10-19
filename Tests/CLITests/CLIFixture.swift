import Foundation
import Testing

struct CLIResult {
  let stdout: String
  let stderr: String
  let status: Int32

  func json() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any])
  }
}

final class CLIFixture {
  let root: URL
  let home: URL
  let project: URL
  let source: URL
  let environment: [String: String]

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-cli-\(UUID())")
    home = root.appendingPathComponent("home")
    project = root.appendingPathComponent("project")
    source = root.appendingPathComponent("source")
    environment = [
      "HOME": home.path,
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "TMPDIR": root.appendingPathComponent("tmp").path,
      "LC_ALL": "C", "TERM": "dumb",
      "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
    ]
    do {
      for directory in [home, project, source, root.appendingPathComponent("tmp")] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      }
    } catch {
      try? FileManager.default.removeItem(at: root)
      throw error
    }
  }

  deinit { try? FileManager.default.removeItem(at: root) }

  func run(_ arguments: [String], directory: URL? = nil) throws -> CLIResult {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    // SwiftPM builds the executable dependency for the active test configuration.
    let testBinary = URL(fileURLWithPath: CommandLine.arguments[0])
    // The test bundle sits beside the executable in any scratch path, including release validation.
    let bundleProducts = Bundle(for: ProductsLocator.self).bundleURL.deletingLastPathComponent()
    let candidates = [
      bundleProducts.appendingPathComponent("skill"),
      testBinary.deletingLastPathComponent().appendingPathComponent("skill"),
      testBinary.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("skill"),
      package.appendingPathComponent(".build/debug/skill"),
    ]
    let executable = try #require(
      candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    return try process(executable, arguments, directory: directory ?? project)
  }

  @discardableResult
  func success(_ arguments: [String], directory: URL? = nil) throws -> CLIResult {
    let result = try run(arguments, directory: directory)
    try #require(result.status == 0, "\(arguments): \(result.stderr)")
    #expect(result.stderr.isEmpty)
    return result
  }

  @discardableResult
  func git(_ arguments: [String]) throws -> CLIResult {
    let result = try process(URL(fileURLWithPath: "/usr/bin/git"), arguments, directory: source)
    try #require(result.status == 0, "git \(arguments): \(result.stderr)")
    return result
  }

  func commit() throws {
    if !FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) {
      try git(["init", "--initial-branch=main"])
    }
    try git(["add", "."])
    try git([
      "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
      "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture",
    ])
  }

  func skill(
    _ name: String = "demo", body: String = "Original content", container: String = "skills"
  ) throws {
    let directory = source.appendingPathComponent("\(container)/\(name)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "---\nname: \(name)\ndescription: Fixture skill\n---\n\n\(body)\n".write(
      to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  }

  func instruction(
    _ name: String = "canonical-artifacts", heading: String = "Canonical Artifacts",
    body: String = "Original instructions", container: String = "instructions"
  ) throws {
    let directory = source.appendingPathComponent(container)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("# \(heading)\n\n\(body)\n".utf8).write(
      to: directory.appendingPathComponent(name + ".md"))
  }

  func declaration(scope: String = "project") throws -> [String: Any] {
    try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: state("agents.json", scope: scope)))
        as? [String: Any])
  }

  func state(_ name: String, scope: String = "project") -> URL {
    (scope == "user"
      ? home.appendingPathComponent(".agents") : project.appendingPathComponent(".agent"))
      .appendingPathComponent(name)
  }

  private func process(_ executable: URL, _ arguments: [String], directory: URL) throws -> CLIResult
  {
    let stdout = root.appendingPathComponent("stdout")
    let stderr = root.appendingPathComponent("stderr")
    try Data().write(to: stdout)
    try Data().write(to: stderr)
    let output = try FileHandle(forWritingTo: stdout)
    let errors = try FileHandle(forWritingTo: stderr)
    defer {
      try? output.close()
      try? errors.close()
    }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    return try CLIResult(
      stdout: String(contentsOf: stdout, encoding: .utf8),
      stderr: String(contentsOf: stderr, encoding: .utf8), status: process.terminationStatus)
  }
}

private final class ProductsLocator {}
