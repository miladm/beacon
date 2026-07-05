#!/usr/bin/env python3
"""Idempotently merge beacon's hooks into a Claude Code settings.json.

Usage: merge_hooks.py <settings.json path> <absolute path to beacon.sh>

Preserves any existing hooks and other settings. A backup is written to
<settings>.bak before changes. Re-running upgrades in place (old beacon
entries are removed first, then re-added).
"""
import json
import os
import shutil
import sys


def entry(script, cmd, matcher=None):
    e = {"hooks": [{"type": "command", "command": f"{script} {cmd}"}]}
    if matcher:
        e = {"matcher": matcher, "hooks": e["hooks"]}
    return e


def main():
    settings_path, script = sys.argv[1], sys.argv[2]

    data = {}
    if os.path.exists(settings_path):
        shutil.copy(settings_path, settings_path + ".bak")
        with open(settings_path) as f:
            text = f.read().strip()
        data = json.loads(text) if text else {}
    else:
        os.makedirs(os.path.dirname(settings_path), exist_ok=True)

    hooks = data.setdefault("hooks", {})

    wanted = {
        "SessionStart":     [entry(script, "start")],
        "UserPromptSubmit": [entry(script, "capture")],
        "PreToolUse":       [entry(script, "subup", matcher="Task")],
        "SubagentStop":     [entry(script, "subdown")],
        "Notification":     [entry(script, "notify")],
        "Stop":             [entry(script, "done")],
        "SessionEnd":       [entry(script, "end")],
    }

    marker = "beacon.sh"  # identify our entries to keep merge idempotent
    for event, items in wanted.items():
        arr = hooks.setdefault(event, [])
        arr[:] = [e for e in arr if marker not in json.dumps(e)]
        arr.extend(items)

    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"merged beacon hooks into {settings_path}")


if __name__ == "__main__":
    main()
