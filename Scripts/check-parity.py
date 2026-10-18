#!/usr/bin/env python3
"""Compare skills and watch contracts with a read-only agents package checkout."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]
STATE_FILES = ("agents.json", "agents.resolved", "agents.watch")


def run(command, directory, environment=None):
    result = subprocess.run(
        [str(value) for value in command], cwd=directory, env=environment,
        stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True,
    )
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
        return run([*prefix, *group, *arguments, "--scope", scope],
                   roots[index] / "project", environments[index])

    def both(arguments, skills=False, report=False):
        results = [command(index, arguments, skills) for index in range(2)]
        if report:
            results = [json.loads(value) for value in results]
            if arguments[0] == "install":
                instructions = results[1].pop("instructions")
                assert not instructions["changed"], instructions
            results = [json.dumps(value, sort_keys=True) for value in results]
        normalized = [value.replace(str(client), "/client")
                      for value, client in zip(results, roots)]
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
    write(source / "instructions/rules.md", "# Rules\n\nOriginal\n")
    initial = commit()
    both(["add", str(source), "--all", "--agent", "codex", "--mode", mode,
          "--branch", "main"], skills=True)
    installed = both(["list", "--json"], skills=True, report=True)
    state()
    for index in range(2):
        rows = json.loads(command(index, ["list", "--json"], skills=True))["skills"]
        for row in rows:
            target = Path(row["path"])
            if target.is_symlink():
                target.unlink()
            else:
                shutil.rmtree(target)
    both(["install", "--json"], report=True)
    state()
    both(["watch", "add", str(source)])
    baseline = state()
    assert all(baseline[name] is not None for name in STATE_FILES)
    both(["watch", "status", "--json"], report=True)
    skill(source, "demo", "Updated")
    skill(source, "new", "Added")
    shutil.rmtree(source / "skills/legacy")
    write(source / "instructions/rules.md", "# Rules\n\nUpdated\n")
    write(source / "skills/demo/run.sh", "echo parity\n")
    (source / "skills/demo/run.sh").chmod(0o755)
    current = commit()
    skill(source, "uncommitted", "Ignored")
    report = both(["watch", "status", "--json"], report=True)
    changes = report["sources"][0]["changes"]
    assert {item["kind"] for item in changes} == {"skill", "instructions"}
    assert {item["change"] for item in changes} == {"new", "changed", "removed"}
    assert report["sources"][0]["seen"] == {"revision": initial}
    assert report["sources"][0]["current"] == {"revision": current}
    both(["watch"])
    both(["watch", "diff", str(source)])
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
    both(["update", "--apply"], skills=True)
    state()
    both(["watch", "seen", str(source), "--revision", initial])
    state()
    both(["watch", "remove", str(source)])
    state()
    both(["remove", "demo", "new"], skills=True)
    state()
    print(f"PASS {scope}/{mode}: lifecycle, watch reports/output, all three state files")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agents-package", type=Path, required=True)
    parser.add_argument("--skill", type=Path, default=PACKAGE / ".build/debug/skill")
    args = parser.parse_args()
    reference = args.agents_package.expanduser().resolve()
    agents = ["/usr/bin/swift", "run", "--package-path", str(reference),
              "--build-path", str(PACKAGE / ".build/agents")]
    print(run([*agents, "agents", "--version"], PACKAGE).strip(), flush=True)
    agents += ["--skip-build", "agents"]
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
