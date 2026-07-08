# beacon

**A beacon of status lights for your Claude Code terminal tabs.**

Run several Claude Code agents in VS Code terminal tabs and you quickly lose track of which one is working, which finished, and which is blocked waiting on you. `beacon` prefixes each tab's title with a small colored dot that reflects the agent's live state, so a glance across your tabs tells you where to look. The tab's text (the topic Claude Code already shows) is left intact.

```
🟢 myproj - refactor the auth module      <- working
🟣 api    - add pagination endpoint       <- a subagent is running
🟡 infra  - fix the flaky CI job          <- waiting on you
🔴 web    - migrate to the new router     <- needs your approval
⚪ docs   - rewrite the README            <- done, your turn
```

## The states

| Dot | Meaning | Fires on (Claude Code hook) |
|-----|---------|------------------------------|
| 🟢 green  | Main agent is working              | `UserPromptSubmit`, any `PreToolUse` / `PostToolUse` |
| 🟣 purple | At least one subagent is running   | `PreToolUse` (Task) / `SubagentStop` |
| 🟡 yellow | Idle, waiting on you               | `Notification` (idle) |
| 🔴 red    | Blocked, needs your approval       | `Notification` (permission) |
| ⚪ white  | Done, your turn                    | `Stop` |

It is modeled as a small state machine rather than independent handlers:

- `UserPromptSubmit` -> **green** (and captures the topic).
- Any tool activity (`PreToolUse` / `PostToolUse`) -> **green**, or **purple** if a subagent is running. This is what clears **red**/**yellow** the moment the agent resumes after you unblock it.
- `PreToolUse(Task)` -> **purple** (subagent counter++); `SubagentStop` -> counter--, back to **green** at zero.
- `Notification` -> **red** (permission - always, it's actionable) or **yellow** (idle - never downgrades a **red** block or a **white** done tab).
- `Stop` -> **white**.

Guard: **white** (done) is sticky - tool, subagent, and idle events never override it; a done tab leaves **white** only on your next prompt (-> green) or a real permission request (-> red). This prevents a late `SubagentStop`, a stray tool event, or the idle nudge from resurrecting or recoloring a finished tab. Full spec + transition table: [STATE_MACHINE.md](STATE_MACHINE.md).

## How it works

Claude Code exposes lifecycle **hooks**. `beacon` registers small hook commands that record the current state to a per-tab file and write an **OSC title escape sequence** straight to the terminal's controlling tty. VS Code renders whatever the process sets as the title when you enable `terminal.integrated.tabs.title: "${sequence}"`, so the dot shows up in the tab.

Claude Code also animates its own spinner in the title. To keep the dot visible, a tiny per-tab background daemon repaints a few times a second while the agent is working. It exits automatically when the terminal closes or the session ends.

The topic text is captured once from your first prompt of the session (`folder - your prompt`) and stays stable for the session.

## Requirements

- **Claude Code** (with hooks support) and **VS Code** with its integrated terminal.
- **macOS or Linux** (uses `ps` and `/dev/tty*`; works with `ttys*` and `pts/*`).
- **python3** (used by the installer to safely merge `settings.json`).
- **jq** *or* **python3** at runtime (used to read the prompt for the topic text). If neither is present, dots still work; the tab just falls back to the folder name.

## Install

```sh
git clone https://github.com/miladm/beacon.git
cd beacon
./install.sh
```

The installer:
1. copies `src/beacon.sh` to `~/.claude/hooks/beacon.sh`,
2. idempotently merges the hooks into `~/.claude/settings.json` (backing it up first),
3. prints the one VS Code setting you need and the likely `settings.json` paths.

Then add this to your VS Code **user** `settings.json`:

```json
"terminal.integrated.tabs.title": "${sequence}"
```

Finally:
- Reload VS Code: Command Palette -> **Developer: Reload Window**
- Relaunch any running `claude` sessions (hooks load at startup)

That's it. Open a terminal, run `claude`, and watch the tab.

## Configuration

All optional, via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `BEACON_STATE_DIR`      | `~/.claude/beacon` | Where per-tab state files live |
| `BEACON_WORK_INTERVAL`  | `0.02` | Repaint seconds while working (lower = smoother vs Claude's spinner, more CPU) |
| `BEACON_IDLE_INTERVAL`  | `0.3`  | Repaint seconds while idle |
| `CLAUDE_CONFIG_DIR`         | `~/.claude` | Claude Code config dir (respected by the installer) |

## Notes and limitations

- **Some flicker is expected while working.** Claude Code continuously animates its own title spinner, and there is no supported way to disable it. The daemon repaints fast enough to keep the dot mostly visible, but it cannot fully eliminate contention.
- **Keep one terminal per tab** to see the dot + topic + toolbar buttons on the panel header row. If you stack many terminals into one group, VS Code switches to a side tab list.
- Only VS Code **terminal** tabs are supported. Chat-style extension panels render their own tabs and cannot be targeted this way.

## Uninstall

```sh
./uninstall.sh
```

Removes the installed script and the beacon hook entries (backing up `settings.json` first) and deletes the state dir. Remove the VS Code `tabs.title` setting yourself if you added it.

## Tests

```sh
./tests/run.sh
```

This runs three layers: behavior checks, the exhaustive state-machine transition
matrix (`tests/state_machine.sh`), and a **real PTY integration test**
(`tests/integration_pty.py`, needs `python3`) that starts the actual repaint
daemon against a genuine pseudo-terminal, fires real hook processes, and reads
back the escape bytes rendered on the device to confirm the painted color. The
sh layers use a temp `HOME` and a fake device so they never touch your real
terminal.

## License

MIT - see [LICENSE](LICENSE).
