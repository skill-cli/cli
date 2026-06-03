import Foundation

public enum CoreError: Error, CustomStringConvertible, Equatable {
  case invalidSource(String)
  case unsafePath(String)
  case unsupported(String)
  case notFound(String)
  case invalidSkill(String)
  case commandFailed(String)

  public var description: String {
    switch self {
    case .invalidSource(let message):
      return "Invalid source: \(message)"
    case .unsafePath(let message):
      return "Unsafe path: \(message)"
    case .unsupported(let message):
      return "Unsupported: \(message)"
    case .notFound(let message):
      return "Not found: \(message)"
    case .invalidSkill(let message):
      return "Invalid skill: \(message)"
    case .commandFailed(let message):
      return "Command failed: \(message)"
    }
  }
}
