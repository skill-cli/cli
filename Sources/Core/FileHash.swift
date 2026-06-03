import CryptoKit
import Foundation

public enum FileHash {
  public static func sha256Hex(data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func sha256Hex(file: URL) throws -> String {
    try sha256Hex(data: Data(contentsOf: file))
  }

  public static func folderHash(_ directory: URL) throws -> String {
    var hasher = SHA256()
    let files = try filesUnder(directory).sorted { $0.path < $1.path }
    for file in files {
      let relative = file.path.replacingOccurrences(of: directory.path + "/", with: "")
      hasher.update(data: Data(relative.utf8))
      hasher.update(data: Data([0]))
      hasher.update(data: try Data(contentsOf: file))
      hasher.update(data: Data([0]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func filesUnder(_ directory: URL) throws -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsPackageDescendants]
      )
    else {
      return []
    }
    var files: [URL] = []
    for case let url as URL in enumerator {
      let name = url.lastPathComponent
      if [".git", "node_modules", "__pycache__", "__pypackages__"].contains(name) {
        enumerator.skipDescendants()
        continue
      }
      if name == "metadata.json" {
        continue
      }
      if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        files.append(url)
      }
    }
    return files
  }
}
