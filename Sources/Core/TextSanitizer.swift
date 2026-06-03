import Foundation

public enum TextSanitizer {
  public static func stripTerminalEscapes(_ value: String) -> String {
    var result = value
    let patterns = [
      "\u{001B}\\][\\s\\S]*?(?:\u{0007}|\u{001B}\\\\)",
      "\u{001B}[P^_][\\s\\S]*?(?:\u{001B}\\\\)",
      "\u{001B}\\[[0-?]*[ -/]*[@-~]",
      "\u{001B}[ -~]",
      "[\u{0080}-\u{009F}]",
      "[\u{0000}-\u{0008}\u{000B}\u{000C}\u{000D}-\u{001A}\u{001C}-\u{001F}\u{007F}]",
    ]
    for pattern in patterns {
      result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    return result
  }

  public static func sanitizeMetadata(_ value: String) -> String {
    stripTerminalEscapes(value)
      .replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
