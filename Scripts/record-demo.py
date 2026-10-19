#!/usr/bin/env python3
"""Record the README demo using a release build and an offline Git fixture."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess


PACKAGE = Path(__file__).resolve().parents[1]
OUTPUT = PACKAGE / "Documentation/Assets/Demo"
SCRATCH = PACKAGE / ".build/readme-demo"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, directory=PACKAGE, environment=None):
    result = subprocess.run(
        command, cwd=directory, env=environment, stdin=subprocess.DEVNULL,
        capture_output=True, text=True,
    )
    result.check_returncode()
    return result


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    executable = (PACKAGE / ".build/release/skill").resolve()
    if not executable.is_file():
        raise SystemExit("Run swift build -c release first.")
    if execute(["git", "diff", "HEAD", "--", "Sources", "Package.swift",
                "Package.resolved"]).stdout:
        raise SystemExit("Commit source and dependency changes before recording.")
    if SCRATCH.exists():
        raise SystemExit("Remove the previous .build/readme-demo before recording.")

    home = SCRATCH / "home"
    source = home / "skills"
    project = home / "project"
    for directory in (source, project, home / "bin", SCRATCH / "tmp"):
        directory.mkdir(parents=True, exist_ok=True)
    (home / "bin/skill").symlink_to(executable)
    environment = {
        "HOME": str(home), "TMPDIR": str(SCRATCH / "tmp"),
        "PATH": f"{home / 'bin'}:/usr/bin:/bin:/usr/sbin:/sbin",
        "LC_ALL": "C", "TERM": "dumb",
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0", "GIT_ALLOW_PROTOCOL": "file",
        "GIT_AUTHOR_NAME": "Demo", "GIT_COMMITTER_NAME": "Demo",
        "GIT_AUTHOR_EMAIL": "demo@example.invalid",
        "GIT_COMMITTER_EMAIL": "demo@example.invalid",
        "GIT_AUTHOR_DATE": "2000-01-01T00:00:00+00:00",
        "GIT_COMMITTER_DATE": "2000-01-01T00:00:00+00:00",
    }
    commands, receipts, normalizations = [], [], []

    def git(*arguments):
        return execute(["/usr/bin/git", *arguments], source, environment).stdout.strip()

    def skill(name, body):
        directory = source / name
        directory.mkdir(exist_ok=True)
        (directory / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: README demo skill\n---\n\n{body}\n"
        )

    def normalize(value, field):
        count = value.count(str(home))
        if count:
            normalizations.append({
                "field": field, "from": "isolated HOME", "to": "~",
                "occurrences": count,
            })
        return value.replace(str(home), "~")

    def record(command):
        result = execute(["/bin/sh", "-c", command], project, environment)
        index = len(commands)
        stdout = normalize(result.stdout, f"commands[{index}].stdout")
        stderr = normalize(result.stderr, f"commands[{index}].stderr")
        if stderr:
            raise RuntimeError(f"Unexpected stderr from {command}: {stderr}")
        commands.append({
            "command": command, "stdout": stdout.removesuffix("\n"),
            "exit_code": result.returncode,
        })
        receipts.append({"command": command, "exit_code": result.returncode,
                         "stderr": stderr,
                         "removed_final_newline": stdout.endswith("\n")})

    try:
        git("init", "--initial-branch=main", "--object-format=sha1", "--template=")
        git("config", "commit.gpgsign", "false")
        git("config", "core.hooksPath", "/dev/null")
        skill("commit", "Describe the change.")
        skill("review", "Read the diff.")
        git("add", ".")
        git("commit", "-qm", "Add demo skills")
        initial = git("rev-parse", "HEAD")
        initial_tree = git("rev-parse", "HEAD^{tree}")

        record("skill add ~/skills review commit")
        record("skill watch add ~/skills")
        record("printf 'Check edge cases.\\n' >> ~/skills/review/SKILL.md")
        record('git -C ~/skills commit -qam "Expand review"')
        updated = git("rev-parse", "HEAD")
        record("skill watch")
        record("skill update --apply")

        for agent in (".agents", ".claude"):
            installed = project / agent / "skills/review/SKILL.md"
            if installed.read_bytes() != (source / "review/SKILL.md").read_bytes():
                raise RuntimeError(f"Update did not reach {agent}.")
        output_lines = sum(len(item["stdout"].splitlines()) for item in commands)
        if output_lines > 25:
            raise RuntimeError(f"Demo has {output_lines} output lines; limit is 25.")

        provenance = {
            "source": {
                "repository": "https://github.com/skill-cli/cli",
                "revision": execute(["git", "rev-parse", "HEAD"]).stdout.strip(),
                "build_command": "swift build -c release",
                "package_resolved_sha256": digest(PACKAGE / "Package.resolved"),
                "dependencies": json.loads((PACKAGE / "Package.resolved").read_text())["pins"],
            },
            "executable": {
                "path": ".build/release/skill", "sha256": digest(executable),
                "version": execute([str(executable), "--version"], project,
                                   environment).stdout.strip(),
            },
            "toolchain": {
                "swift": execute(["swift", "--version"]).stdout.strip(),
                "git": execute(["/usr/bin/git", "--version"]).stdout.strip(),
                "python": execute(["python3", "--version"]).stdout.strip(),
            },
            "recorder": {"path": "Scripts/record-demo.py", "sha256": digest(Path(__file__))},
            "fixture": {
                "source": "~/skills", "working_directory": "~/project",
                "initial_revision": initial, "initial_tree": initial_tree,
                "updated_revision": updated, "updated_tree": git("rev-parse", "HEAD^{tree}"),
                "commit_timestamp": environment["GIT_AUTHOR_DATE"],
                "git_allowed_protocols": ["file"],
                "environment": "Explicit isolated HOME; no inherited agent configuration.",
            },
            "commands": receipts,
            "normalizations": {
                "paths": normalizations,
                "home_display": "Commands use ~; skill itself abbreviates HOME as ~.",
                "stdout": "Remove one final newline per command when present; preserve all other text.",
                "private_receipt": (
                    ".build/readme-demo/normalizations.json" if normalizations else None
                ),
            },
            "output_lines": output_lines,
        }
        OUTPUT.mkdir(parents=True, exist_ok=True)
        write_json(OUTPUT / "record.json", {"title": "skill", "commands": commands})
        write_json(OUTPUT / "provenance.json", provenance)
        if normalizations:
            write_json(SCRATCH / "normalizations.json", {
                "from": str(home), "to": "~", "fields": normalizations,
            })
        print(f"Recorded {len(commands)} successful commands, {output_lines} output lines.")
    finally:
        shutil.rmtree(home)
        shutil.rmtree(SCRATCH / "tmp")
        if not any(SCRATCH.iterdir()):
            SCRATCH.rmdir()


if __name__ == "__main__":
    main()
