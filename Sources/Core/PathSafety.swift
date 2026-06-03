import Foundation

public enum PathSafety {
  public static func sanitizeSubpath(_ subpath: String) throws -> String {
    let normalized = subpath.replacingOccurrences(of: "\\", with: "/")
    if normalized.contains("\0") {
      throw CoreError.unsafePath("subpath contains null byte: \(subpath)")
    }
    if normalized.isEmpty || normalized == "." {
      return "."
    }
    if normalized.hasPrefix("/")
      || normalized.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil
    {
      throw CoreError.unsafePath("subpath must be relative: \(subpath)")
    }
    let segments = normalized.split(separator: "/", omittingEmptySubsequences: true).map(
      String.init)
    for segment in segments where segment == ".." {
      throw CoreError.unsafePath("subpath contains path traversal segment: \(subpath)")
    }
    let safe = segments.filter { $0 != "." }.joined(separator: "/")
    return safe.isEmpty ? "." : safe
  }

  public static func isSubpathSafe(base: URL, subpath: String) -> Bool {
    let normalized = subpath.replacingOccurrences(of: "\\", with: "/")
    let target = base.appendingPathComponent(normalized).standardizedFileURL
    return isContained(target, in: base)
  }

  public static func resolvedChild(base: URL, subpath: String) throws -> URL {
    let safe = try sanitizeSubpath(subpath)
    let target = safe == "." ? base : base.appendingPathComponent(safe)
    guard isContained(target, in: base) else {
      throw CoreError.unsafePath("\(subpath) escapes \(base.path)")
    }
    return target
  }

  public static func isContained(_ target: URL, in base: URL) -> Bool {
    let basePath = base.standardizedFileURL.path
    let targetPath = target.standardizedFileURL.path
    return targetPath == basePath || targetPath.hasPrefix(basePath + "/")
  }

  public static func sanitizeName(_ name: String) -> String {
    let lowercased = name.lowercased()
    let replaced = lowercased.replacingOccurrences(
      of: #"[^a-z0-9._]+"#,
      with: "-",
      options: .regularExpression
    )
    let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    let limited = String(trimmed.prefix(255))
    return limited.isEmpty ? "unnamed-skill" : limited
  }

  public static func shortenPath(_ fullPath: String, cwd: String, home: String, separator: String)
    -> String
  {
    if fullPath == home || fullPath.hasPrefix(home + separator) {
      return "~" + String(fullPath.dropFirst(home.count))
    }
    if fullPath == cwd || fullPath.hasPrefix(cwd + separator) {
      return "." + String(fullPath.dropFirst(cwd.count))
    }
    return fullPath
  }

  public static func isValidSkillFile(_ file: String) -> Bool {
    guard !file.isEmpty else { return false }
    if file.hasPrefix("/") || file.hasPrefix("\\") || file.contains("..") {
      return false
    }
    return true
  }

  public static func normalizeSkillPath(_ skillPath: String) -> String {
    var folderPath = skillPath
    if folderPath.hasSuffix("/SKILL.md") || folderPath.hasSuffix("\\SKILL.md") {
      folderPath = String(folderPath.dropLast(9))
    } else if folderPath.hasSuffix("SKILL.md") {
      folderPath = String(folderPath.dropLast(8))
    }
    if folderPath.hasSuffix("/") || folderPath.hasSuffix("\\") {
      folderPath = String(folderPath.dropLast())
    }
    return folderPath.replacingOccurrences(of: "\\", with: "/")
  }

  public static func relativeSkillFilePath(root: String?, skillPath: String, separator: String)
    -> String?
  {
    guard let root else { return nil }
    if skillPath == root {
      return "SKILL.md"
    }
    guard skillPath.hasPrefix(root + separator) else {
      return nil
    }
    return String(skillPath.dropFirst(root.count + separator.count))
      .replacingOccurrences(of: separator, with: "/") + "/SKILL.md"
  }

  public static func relativePath(_ path: String, to base: String) -> String {
    let pathComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    let baseComponents = URL(fileURLWithPath: base).standardizedFileURL.pathComponents
    var index = 0
    while index < pathComponents.count, index < baseComponents.count,
      pathComponents[index] == baseComponents[index]
    {
      index += 1
    }
    let up = Array(repeating: "..", count: max(0, baseComponents.count - index))
    let down = pathComponents.dropFirst(index)
    let components = up + down
    return components.isEmpty ? "." : components.joined(separator: "/")
  }
}
