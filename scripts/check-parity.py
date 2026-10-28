#!/usr/bin/env python3
"""Compare skills and watch contracts with a read-only agents package checkout."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]
STATE_FILES = ("agents.json", "agents.resolved", "agents.watch")


def execute(command, directory, environment=None):
    result = subprocess.run(
        [str(value) for value in command], cwd=directory, env=environment,
        stdin=subprocess.DEVNULL, capture_output=True, text=True,
    )
    return result


def run(command, directory, environment=None):
    result = execute(command, directory, environment)
    result.check_returncode()
    return result.stdout


def environment(root):
    for name in ("home", "project", "tmp"):
        (root / name).mkdir(parents=True)
    return {
        "HOME": str(root / "home"), "TMPDIR": str(root / "tmp"),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "TERM": "dumb",
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
    }


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def skill(source, name, body):
    write(source / "skills" / name / "SKILL.md",
          f"---\nname: {name}\ndescription: Parity fixture\n---\n\n{body}\n")


def rules(source, body):
    write(source / "instructions/rules.md",
          f"---\ndescription: Parity fixture\n---\n\n# Rules\n\n{body}\n")


def scenario(root, scope, mode, skill_command, agents_command):
    roots = [root / "skill", root / "agents"]
    environments = [environment(client) for client in roots]
    source = root / "source"
    source.mkdir()

    def git(*arguments):
        return run(["/usr/bin/git", *arguments], source, environments[0]).strip()

    def commit():
        git("add", ".")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
            "commit", "-m", "fixture")
        return git("rev-parse", "HEAD")

    def command(index, arguments, skills=False):
        prefix = skill_command if index == 0 else agents_command
        group = ["skills"] if index == 1 and skills else []
        scope_arguments = [] if arguments[0] == "init" else ["--scope", scope]
        return execute([*prefix, *group, *arguments, *scope_arguments],
                       roots[index] / "project", environments[index])

    def normalize(value, index):
        value = value.replace(str(roots[index]), "/client")
        if index == 1:
            value = value.replace("agents skills", "skill")
            for suffix in (" --help", " watch", " doctor"):
                value = value.replace("agents" + suffix, "skill" + suffix)
        return value

    def both(arguments, skills=False, report=False, status=0):
        results = [command(index, arguments, skills) for index in range(2)]
        assert all(result.returncode == status for result in results), (
            arguments, [(result.returncode, result.stderr) for result in results])
        errors = [normalize(result.stderr, index) for index, result in enumerate(results)]
        assert errors[0] == errors[1], (arguments, errors)
        results = [result.stdout for result in results]
        if report:
            results = [json.loads(value) for value in results]
            if arguments[0] in ("install", "update"):
                # agents version 2 changed instruction targets only; skill reports carry none.
                versions = [value.pop("schemaVersion") for value in results]
                assert versions == [1, 2], (arguments, versions)
            if arguments[0] == "install":
                instructions = results[1].pop("instructions")
                assert not instructions["changed"], instructions
            results = [json.dumps(value, sort_keys=True) for value in results]
        elif arguments[0] == "install":
            # Top-level agents install also reports its separate instruction operation.
            suffix = "No locked instruction targets to restore.\n"
            assert results[1].endswith(suffix), results[1]
            results[1] = results[1][:-len(suffix)]
        normalized = [normalize(value, index) for index, value in enumerate(results)]
        assert normalized[0] == normalized[1], (arguments, normalized)
        return json.loads(results[0]) if report else results[0]

    state_directories = [
        client / ("home/.agents" if scope == "user" else "project/.agent")
        for client in roots
    ]

    def state():
        snapshots = []
        for directory in state_directories:
            snapshots.append({name: (directory / name).read_bytes()
                              if (directory / name).exists() else None
                              for name in STATE_FILES})
        assert snapshots[0] == snapshots[1], f"State differs: {scope}/{mode}"
        return snapshots[0]

    git("init", "--initial-branch=main")
    skill(source, "demo", "Original")
    skill(source, "legacy", "Original")
    skill(source, "repinned", "Unchanged")
    write(source / "skills/demo/run.sh", "echo parity\n")
    write(source / "skills/demo/old-empty", "")
    write(source / "skills/demo/controls", "Old\ttext\r\n\x1b[31m\0\n")
    (source / "skills/demo/data.bin").write_bytes(bytes([0, 254]))
    (source / "skills/demo/link").symlink_to("SKILL.md")
    rules(source, "Original")
    initial = commit()
    both(["init", "local-skill"], skills=True)
    both(["list", str(source)], skills=True)
    both(["add", str(source)], skills=True)
    both(["add", str(source), "--all", "--mode", mode,
          "--branch", "main"], skills=True)
    installed = both(["list", "--json"], skills=True, report=True)
    both(["list"], skills=True)
    state()
    for index in range(2):
        rows = json.loads(command(index, ["list", "--json"], skills=True).stdout)["skills"]
        for row in rows:
            target = Path(row["path"])
            if target.is_symlink():
                target.unlink()
            else:
                shutil.rmtree(target)
    both(["install", "--json"], report=True)
    both(["install"])
    state()
    both(["watch", "add", str(source)])
    baseline = state()
    assert all(baseline[name] is not None for name in STATE_FILES)
    both(["watch", "status", "--json"], report=True)
    both(["watch", "status"])
    both(["watch", "diff", str(source)])
    skill(source, "demo", "Updated")
    skill(source, "new", "Added")
    shutil.rmtree(source / "skills/legacy")
    rules(source, "Updated")
    write(source / "skills/demo/run.sh", "echo parity\n")
    (source / "skills/demo/run.sh").chmod(0o755)
    (source / "skills/demo/old-empty").unlink()
    write(source / "skills/demo/new-empty", "")
    write(source / "skills/demo/controls", "New\ttext\n\x1b[32m\0\n")
    (source / "skills/demo/data.bin").write_bytes(bytes([0, 255]))
    (source / "skills/demo/link").unlink()
    (source / "skills/demo/link").symlink_to("run.sh")
    current = commit()
    skill(source, "uncommitted", "Ignored")
    report = both(["watch", "status", "--json"], report=True)
    changes = report["sources"][0]["changes"]
    assert {item["kind"] for item in changes} == {"skill", "instructions"}
    assert {item["change"] for item in changes} == {"new", "changed", "removed"}
    assert report["sources"][0]["seen"] == {"revision": initial}
    assert report["sources"][0]["current"] == {"revision": current}
    both(["watch"])
    both(["watch", "status"])
    both(["watch", "diff", str(source)])
    both(["watch", "diff", str(source), "demo", "--kind", "skill"])
    both(["watch", "diff", str(source), "rules", "--kind", "instructions"])
    both(["watch", "diff", str(source), "--json"], report=True)
    both(["watch", "diff", str(source), "rules", "--kind", "instructions", "--json"],
         report=True)
    assert state() == baseline, "Watch inspection changed state"
    assert both(["list", "--json"], skills=True, report=True) == installed
    both(["watch", "seen", str(source)])
    acknowledged = state()
    assert acknowledged["agents.watch"] != baseline["agents.watch"]
    assert all(acknowledged[name] == baseline[name] for name in STATE_FILES[:2])
    assert both(["watch", "--json"], report=True)["sources"][0]["changes"] == []
    both(["update", "--json"], skills=True, report=True)
    preview = both(["update"], skills=True)
    assert preview.count("--- a/demo/SKILL.md\n") == 1, preview
    assert "= repinned  repinned  " in preview, preview
    assert "cache/" not in preview, preview
    assert "empty file demo/new-empty added\n" in preview, preview
    assert "empty file demo/old-empty removed\n" in preview, preview
    both(["update", "--apply"], skills=True)
    state()
    for arguments in (["update"], ["update", "--apply"],
                      ["update", "demo"], ["update", "demo", "--apply"]):
        assert both(arguments, skills=True) == "No skill changes.\n", arguments
    state()
    both(["list"], skills=True)
    both(["watch", "diff", str(source)])
    both(["watch", "seen", str(source), "--revision", initial])
    state()
    both(["watch", "remove", str(source)])
    state()
    both(["remove", "demo", "--agent", "claude-code"], skills=True)
    state()
    both(["remove", "demo", "new", "repinned"], skills=True)
    state()
    both(["list"], skills=True)
    both(["watch"])
    both(["remove", "missing\nname"], skills=True, status=1)
    both(["watch", "diff", str(source)], status=1)
    both(["update", "--apply", "--json"], skills=True, status=64)
    both(["list", "--unknown\x1b[31m"], skills=True, status=64)
    both(["watch", "add", str(source)])
    both(["watch", "seen", str(source), "--revision=missing"], status=1)
    shutil.rmtree(source / ".git")
    both(["watch", "diff", str(source)], status=1)
    state()
    print(f"PASS {scope}/{mode}: lifecycle/watch human stdout and stderr, JSON, state bytes",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agents-package", type=Path, required=True)
    parser.add_argument("--skill", type=Path, default=PACKAGE / ".build/debug/skill")
    args = parser.parse_args()
    reference = args.agents_package.expanduser().resolve()
    revision = run(["git", "rev-parse", "HEAD"], reference).strip()
    reference_root = PACKAGE / ".build/agents"
    source = reference_root / "source"
    if source.exists():
        shutil.rmtree(source)
    source.mkdir(parents=True)
    archive = subprocess.run(
        ["git", "archive", revision], cwd=reference, capture_output=True, check=True,
    ).stdout
    subprocess.run(["tar", "-xf", "-", "-C", str(source)], input=archive, check=True)
    build = ["/usr/bin/swift", "build", "--package-path", str(source),
             "--build-path", str(reference_root / "build")]
    run(build, PACKAGE)
    binary_path = run([*build, "--show-bin-path"], PACKAGE).strip()
    agents = [str(Path(binary_path) / "agents")]
    print(f"{run([*agents, '--version'], PACKAGE).strip()} at {revision}", flush=True)
    skill_command = [str(args.skill.resolve())]
    for command in ([], ["add"], ["status"], ["diff"], ["seen"], ["remove"]):
        skill_help = run([*skill_command, "watch", *command, "--help"], PACKAGE)
        agents_help = run([*agents, "watch", *command, "--help"], PACKAGE)
        assert skill_help == agents_help.replace("agents watch", "skill watch").replace(
            "agents help watch", "skill help watch"), command
    root = PACKAGE / ".agent/parity"
    root.mkdir(parents=True)
    try:
        for scope in ("project", "user"):
            for mode in ("link", "copy"):
                scenario(root / f"{scope}-{mode}", scope, mode, skill_command, agents)
    finally:
        shutil.rmtree(root)
    print("PASS watch help for the group and all five subcommands")


if __name__ == "__main__":
    main()
