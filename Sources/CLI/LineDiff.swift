import Foundation

/// Readable unified diffs with three context lines and visibly escaped control characters.
enum LineDiff {
  private struct Line: Equatable {
    let text: String
    let terminated: Bool

    static func == (lhs: Line, rhs: Line) -> Bool {
      lhs.terminated == rhs.terminated && lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }
  }

  private enum Edit {
    case equal(Line)
    case remove(Line)
    case insert(Line)

    var line: Line {
      switch self {
      case .equal(let line), .remove(let line), .insert(let line): line
      }
    }
    var prefix: String {
      switch self {
      case .equal: " "
      case .remove: "-"
      case .insert: "+"
      }
    }
    var oldCount: Int { if case .insert = self { 0 } else { 1 } }
    var newCount: Int { if case .remove = self { 0 } else { 1 } }
    var changed: Bool { if case .equal = self { false } else { true } }
  }

  static func render(before: Data?, after: Data?, path: String) -> String {
    guard before != after else { return "" }
    let path = Terminal.line(path)
    guard let old = lines(before ?? Data()), let new = lines(after ?? Data()) else {
      return "Binary file \(path) differs\n"
    }
    if before == nil && after?.isEmpty == true { return "empty file \(path) added\n" }
    if after == nil && before?.isEmpty == true { return "empty file \(path) removed\n" }
    let oldPath = before == nil ? "/dev/null" : "a/\(path)"
    let newPath = after == nil ? "/dev/null" : "b/\(path)"
    var output = "--- \(oldPath)\n+++ \(newPath)\n"
    let edits = difference(old[...], new[...])
    var hunks: [Range<Int>] = []
    for index in edits.indices where edits[index].changed {
      let range = max(0, index - 3)..<min(edits.count, index + 4)
      if let last = hunks.last, range.lowerBound <= last.upperBound {
        hunks[hunks.count - 1] = last.lowerBound..<range.upperBound
      } else {
        hunks.append(range)
      }
    }
    var oldLine = 0
    var newLine = 0
    var cursor = 0
    for hunk in hunks {
      for edit in edits[cursor..<hunk.lowerBound] {
        oldLine += edit.oldCount
        newLine += edit.newCount
      }
      let content = edits[hunk]
      let oldCount = content.reduce(0) { $0 + $1.oldCount }
      let newCount = content.reduce(0) { $0 + $1.newCount }
      output +=
        "@@ -\(range(start: oldLine, count: oldCount)) +\(range(start: newLine, count: newCount)) @@\n"
      for edit in content {
        output += edit.prefix + Terminal.line(edit.line.text) + "\n"
        if !edit.line.terminated { output += "\\ No newline at end of file\n" }
      }
      oldLine += oldCount
      newLine += newCount
      cursor = hunk.upperBound
    }
    return output
  }

  private static func range(start: Int, count: Int) -> String {
    if count == 0 { return "\(start),0" }
    if count == 1 { return "\(start + 1)" }
    return "\(start + 1),\(count)"
  }

  private static func lines(_ data: Data) -> [Line]? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    if text.isEmpty { return [] }
    var parts = text.components(separatedBy: "\n")
    let terminated = data.last == 10
    if terminated { parts.removeLast() }
    return parts.enumerated().map {
      Line(text: $0.element, terminated: $0.offset < parts.count - 1 || terminated)
    }
  }

  // Hirschberg's LCS split avoids a quadratic table of line pairs.
  private static func difference(_ old: ArraySlice<Line>, _ new: ArraySlice<Line>) -> [Edit] {
    if old.isEmpty { return new.map(Edit.insert) }
    if new.isEmpty { return old.map(Edit.remove) }
    var old = old
    var new = new
    var prefix: [Edit] = []
    var suffix: [Edit] = []
    while let first = old.first, first == new.first {
      prefix.append(.equal(first))
      old = old.dropFirst()
      new = new.dropFirst()
    }
    while let last = old.last, last == new.last {
      suffix.append(.equal(last))
      old = old.dropLast()
      new = new.dropLast()
    }
    if !prefix.isEmpty || !suffix.isEmpty {
      return prefix + difference(old, new) + suffix.reversed()
    }
    if old.count == 1 {
      let line = old.first!
      if let match = new.firstIndex(of: line) {
        return new[..<match].map(Edit.insert) + [.equal(line)]
          + new[(match + 1)...].map(Edit.insert)
      }
      return [.remove(line)] + new.map(Edit.insert)
    }
    let middle = old.startIndex + old.count / 2
    let forward = lengths(Array(old[..<middle]), Array(new))
    let backward = lengths(Array(old[middle...].reversed()), Array(new.reversed()))
    let split = (0...new.count).max {
      forward[$0] + backward[new.count - $0] < forward[$1] + backward[new.count - $1]
    }!
    let index = new.startIndex + split
    return difference(old[..<middle], new[..<index]) + difference(old[middle...], new[index...])
  }

  private static func lengths(_ old: [Line], _ new: [Line]) -> [Int] {
    var row = Array(repeating: 0, count: new.count + 1)
    for line in old {
      var diagonal = 0
      for index in new.indices {
        let previous = row[index + 1]
        row[index + 1] = line == new[index] ? diagonal + 1 : max(row[index], previous)
        diagonal = previous
      }
    }
    return row
  }
}
