import Foundation
import Testing

@testable import Core

@Suite("Path Safety And Sanitization")
struct PathSafetyAndSanitizationTests {
  @Test func sanitizesSkillNamesForFilesystemPaths() {
    let cases: [(String, String)] = [
      ("MySkill", "myskill"),
      ("UPPERCASE", "uppercase"),
      ("my skill", "my-skill"),
      ("Convex Best Practices", "convex-best-practices"),
      ("my   skill", "my-skill"),
      ("bun.sh", "bun.sh"),
      ("my_skill", "my_skill"),
      ("skill.v2_beta", "skill.v2_beta"),
      ("skill123", "skill123"),
      ("v2.0", "v2.0"),
      ("skill@name", "skill-name"),
      ("skill#name", "skill-name"),
      ("skill$name", "skill-name"),
      ("skill!name", "skill-name"),
      ("skill@#$name", "skill-name"),
      ("a!!!b", "a-b"),
      ("../etc/passwd", "etc-passwd"),
      ("../../secret", "secret"),
      ("..\\..\\secret", "secret"),
      ("/etc/passwd", "etc-passwd"),
      ("C:\\Windows\\System32", "c-windows-system32"),
      (".hidden", "hidden"),
      ("..hidden", "hidden"),
      ("...skill", "skill"),
      ("skill.", "skill"),
      ("skill..", "skill"),
      ("-skill", "skill"),
      ("--skill", "skill"),
      ("skill-", "skill"),
      ("skill--", "skill"),
      (".-.-skill", "skill"),
      ("-.-.skill", "skill"),
      ("", "unnamed-skill"),
      ("...", "unnamed-skill"),
      ("---", "unnamed-skill"),
      ("@#$%", "unnamed-skill"),
      ("skill日本語", "skill"),
      ("émoji🎉skill", "moji-skill"),
      ("owner/repo.js", "owner-repo.js"),
      ("owner/repo-name", "owner-repo-name"),
      ("https://example.com", "https-example.com"),
      ("docs.example.com", "docs.example.com"),
    ]

    for (raw, expected) in cases {
      #expect(PathSafety.sanitizeName(raw) == expected, "sanitizeName: \(raw)")
    }

    let longName = String(repeating: "a", count: 300)
    #expect(PathSafety.sanitizeName(longName).count == 255)
  }

  @Test func stripsUnsafeTerminalControlCharacters() {
    let esc = "\u{001B}"
    let cases: [(String, String)] = [
      ("Hello \(esc)[31mred\(esc)[0m", "Hello red"),
      ("\(esc)[1;32mbold green\(esc)[0m", "bold green"),
      ("\(esc)[38;5;145mextended color\(esc)[0m", "extended color"),
      ("\(esc)[H", ""),
      ("\(esc)[5;10H", ""),
      ("\(esc)[A\(esc)[10B\(esc)[C\(esc)[D", ""),
      ("Move\(esc)[2Jclear", "Moveclear"),
      ("\(esc)[3J\(esc)[K\(esc)[2K", ""),
      ("\(esc)[S\(esc)[T", ""),
      ("Title\(esc)]0;owned\u{0007}done", "Titledone"),
      ("\(esc)]0;title\(esc)\\", ""),
      ("Link \(esc)]8;;https://evil.example\u{0007}click\(esc)]8;;\u{0007}", "Link click"),
      ("Save\(esc)7restore\(esc)8", "Saverestore"),
      ("\(esc)M\(esc)c", ""),
      ("Bell\u{0007}Back\u{0008}Return\rNull\u{0000}", "BellBackReturnNull"),
      ("hello\tworld", "hello\tworld"),
      ("hello\nworld", "hello\nworld"),
      ("hello\u{009B}world\u{009D}", "helloworld"),
      ("plain ASCII", "plain ASCII"),
      ("unicode 日本語", "unicode 日本語"),
      ("emoji 🎉", "emoji 🎉"),
      ("safe-skill\(esc)[8m(downloads malware)\(esc)[0m", "safe-skill(downloads malware)"),
      (
        "safe-skill\(esc)[2J\(esc)[H\(esc)[32m✓ Verified Safe\(esc)[0m", "safe-skill✓ Verified Safe"
      ),
      (
        "\(esc)]0;pwned\u{0007}\(esc)[3J\(esc)[2J\(esc)[H\(esc)[32mFake output\(esc)[0m",
        "Fake output"
      ),
    ]

    for (raw, expected) in cases {
      #expect(TextSanitizer.stripTerminalEscapes(raw) == expected)
    }

    let malicious =
      "\(esc)]0;[POC] skills output hijacked\u{0007}\(esc)[3J\(esc)[2J\(esc)[H\(esc)[31m[POC] Terminal output injected from SKILL.md\(esc)[0m\n\(esc)[33mThis cleared the screen and overwrote CLI output.\(esc)[0m"
    let stripped = TextSanitizer.stripTerminalEscapes(malicious)
    #expect(!stripped.contains(esc))
    #expect(!stripped.contains("\u{0007}"))
    #expect(stripped.contains("[POC] Terminal output injected from SKILL.md"))
    #expect(stripped.contains("This cleared the screen and overwrote CLI output."))

    #expect(TextSanitizer.sanitizeMetadata("  \(esc)[31mhello\(esc)[0m  ") == "hello")
    #expect(TextSanitizer.sanitizeMetadata("line1\nline2\nline3") == "line1 line2 line3")
    #expect(TextSanitizer.sanitizeMetadata("  hello\nworld\r\nagain  ") == "hello world again")
    #expect(
      TextSanitizer.sanitizeMetadata(malicious)
        == "[POC] Terminal output injected from SKILL.md This cleared the screen and overwrote CLI output."
    )
    #expect(TextSanitizer.sanitizeMetadata("next-best-practices") == "next-best-practices")
    #expect(TextSanitizer.sanitizeMetadata("AI SDK") == "AI SDK")
    #expect(TextSanitizer.sanitizeMetadata("Creating Diagrams") == "Creating Diagrams")
    #expect(
      TextSanitizer.sanitizeMetadata("Build UIs with @nuxt/ui v4")
        == "Build UIs with @nuxt/ui v4")
  }

  @Test func normalizesCrossPlatformPathInputs() {
    #expect(
      PathSafety.shortenPath(
        "/Users/test/documents/file.txt",
        cwd: "/Users/test/projects/myproject",
        home: "/Users/test",
        separator: "/"
      ) == "~/documents/file.txt")
    #expect(
      PathSafety.shortenPath(
        "/var/www/myproject/src/file.ts",
        cwd: "/var/www/myproject",
        home: "/Users/test",
        separator: "/"
      ) == "./src/file.ts")
    #expect(
      PathSafety.shortenPath(
        "/Users/tester/file.txt",
        cwd: "/Users/test/projects/myproject",
        home: "/Users/test",
        separator: "/"
      ) == "/Users/tester/file.txt")
    #expect(
      PathSafety.shortenPath(
        "C:\\Users\\test\\documents\\file.txt",
        cwd: "C:\\Users\\test\\projects\\myproject",
        home: "C:\\Users\\test",
        separator: "\\"
      ) == "~\\documents\\file.txt")
    #expect(
      PathSafety.shortenPath(
        "/Users/test",
        cwd: "/Users/test/projects/myproject",
        home: "/Users/test",
        separator: "/"
      ) == "~")
    #expect(
      PathSafety.shortenPath(
        "/Users/test/projects/myproject",
        cwd: "/Users/test/projects/myproject",
        home: "/Users/test",
        separator: "/"
      ) == "~/projects/myproject")
    #expect(
      PathSafety.shortenPath(
        "/var/www/myproject",
        cwd: "/var/www/myproject",
        home: "/Users/test",
        separator: "/"
      ) == ".")
    #expect(
      PathSafety.shortenPath(
        "/Users/tester/file.txt",
        cwd: "/var/www/myproject",
        home: "/Users/test",
        separator: "/"
      ) == "/Users/tester/file.txt")
    #expect(
      PathSafety.shortenPath(
        "C:\\Users\\test",
        cwd: "C:\\Users\\test\\projects\\myproject",
        home: "C:\\Users\\test",
        separator: "\\"
      ) == "~")
    #expect(
      PathSafety.shortenPath(
        "C:\\Users\\test\\projects\\myproject",
        cwd: "C:\\Users\\test\\projects\\myproject",
        home: "C:\\Users\\test",
        separator: "\\"
      ) == "~\\projects\\myproject")
    #expect(
      PathSafety.shortenPath(
        "D:\\workspace\\project",
        cwd: "D:\\workspace\\project",
        home: "C:\\Users\\test",
        separator: "\\"
      ) == ".")
    #expect(
      PathSafety.shortenPath(
        "C:\\Users\\tester\\file.txt",
        cwd: "D:\\workspace\\project",
        home: "C:\\Users\\test",
        separator: "\\"
      ) == "C:\\Users\\tester\\file.txt")

    for path in ["SKILL.md", "src/helper.ts", "assets/logo.png", ".config"] {
      #expect(PathSafety.isValidSkillFile(path), "valid skill file: \(path)")
    }
    for path in ["/etc/passwd", "\\Windows\\System32", "../../../etc/passwd", "file..name"] {
      #expect(!PathSafety.isValidSkillFile(path), "invalid skill file: \(path)")
    }

    #expect(PathSafety.normalizeSkillPath("skills/my-skill/SKILL.md") == "skills/my-skill")
    #expect(PathSafety.normalizeSkillPath("skills\\my-skill\\SKILL.md") == "skills/my-skill")
    #expect(PathSafety.normalizeSkillPath("SKILL.md") == "")
    #expect(PathSafety.normalizeSkillPath("skills/my-skill/") == "skills/my-skill")
    #expect(PathSafety.normalizeSkillPath("skills\\my-skill\\") == "skills/my-skill")
    #expect(PathSafety.normalizeSkillPath("skills\\deep\\nested\\SKILL.md") == "skills/deep/nested")
    #expect(
      PathSafety.normalizeSkillPath("skills\\.curated\\advanced-skill\\SKILL.md")
        == "skills/.curated/advanced-skill")
  }

  @Test func computesRelativeSkillFilePaths() {
    #expect(
      PathSafety.relativeSkillFilePath(
        root: "/tmp/abc123", skillPath: "/tmp/abc123", separator: "/")
        == "SKILL.md")
    #expect(
      PathSafety.relativeSkillFilePath(
        root: "/tmp/abc123", skillPath: "/tmp/abc123/skills/my-skill", separator: "/")
        == "skills/my-skill/SKILL.md")
    #expect(
      PathSafety.relativeSkillFilePath(
        root: "/tmp/abc123", skillPath: "/tmp/other/my-skill", separator: "/") == nil)
    #expect(
      PathSafety.relativeSkillFilePath(
        root: "C:\\Users\\test\\Temp\\abc123",
        skillPath: "C:\\Users\\test\\Temp\\abc123\\skills\\my-skill",
        separator: "\\") == "skills/my-skill/SKILL.md")
    #expect(
      PathSafety.relativeSkillFilePath(
        root: "C:\\Users\\test\\Temp\\abc",
        skillPath: "C:\\Users\\test\\Temp\\abc123\\skills\\my-skill",
        separator: "\\") == nil)
  }

}
