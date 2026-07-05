#!/usr/bin/env python3
"""Remove beacon's hooks from a Claude Code settings.json.

Usage: remove_hooks.py <settings.json path>

Strips only entries whose command references beacon.sh, drops any event
arrays left empty, and leaves everything else untouched. Writes a .bak first.
"""
import json
import os
import shutil
import sys


def main():
    settings_path = sys.argv[1]
    if not os.path.exists(settings_path):
        print("no settings.json; nothing to remove")
        return

    shutil.copy(settings_path, settings_path + ".bak")
    with open(settings_path) as f:
        text = f.read().strip()
    data = json.loads(text) if text else {}

    hooks = data.get("hooks", {})
    marker = "beacon.sh"
    for event in list(hooks.keys()):
        hooks[event] = [e for e in hooks[event] if marker not in json.dumps(e)]
        if not hooks[event]:
            del hooks[event]
    if "hooks" in data and not data["hooks"]:
        del data["hooks"]

    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"removed beacon hooks from {settings_path}")


if __name__ == "__main__":
    main()
