# beacon state machine

This is the authoritative spec for the per-tab state. `src/beacon.sh` implements
it and `tests/state_machine.sh` verifies every cell of the transition table.

## State

A tab has two pieces of state:

- `STATE` - one of the colors below (the thing painted on the tab).
- `SUB` - an integer count of currently-running subagents (>= 0).

| Color | Name | Meaning |
|-------|------|---------|
| `green`  | WORKING  | main agent is actively working |
| `purple` | SUBAGENT | at least one subagent is running |
| `yellow` | WAITING  | idle, waiting on you |
| `red`    | BLOCKED  | needs your approval |
| `white`  | DONE     | turn finished, your move |

`green` and `purple` are the two **working** colors; which one shows is derived
from `SUB` (`purple` if `SUB > 0`, else `green`). `yellow`/`red` are **attention**
states; `white` is the **done** state.

## Events

Each event is a Claude Code hook wired to one `beacon.sh` subcommand.

| Event | Hook | Subcommand |
|-------|------|------------|
| `prompt`        | `UserPromptSubmit`            | `capture` |
| `tool`          | `PreToolUse` (any) / `PostToolUse` | `work` |
| `task_start`    | `PreToolUse` (matcher `Task`) | `subup` |
| `subagent_end`  | `SubagentStop`                | `subdown` |
| `perm`          | `Notification` (msg has "permission") | `notify` |
| `idle`          | `Notification` (otherwise)    | `notify` |
| `stop`          | `Stop`                        | `done` |
| `session_start` | `SessionStart`                | `start` |
| `session_end`   | `SessionEnd`                  | `end` |

## Transition rules

Let `w()` = `purple` if `SUB > 0` else `green` (the resolved working color).

- **prompt**: `STATE <- green`; capture the topic once (first prompt of the session).
- **tool**: if `STATE != white` then `STATE <- w()`. (Clears `red`/`yellow` when the
  agent resumes; never resurrects a done tab.)
- **task_start**: `SUB <- SUB + 1`; if `STATE in {green, purple, unset}` then `STATE <- purple`.
- **subagent_end**: `SUB <- max(0, SUB - 1)`; if `STATE in {green, purple}` then `STATE <- w()`.
- **perm**: `STATE <- red` (always; a permission request is actionable even from a done tab).
- **idle**: if `STATE not in {red, white}` then `STATE <- yellow` (never downgrades a
  block or recolors a done tab; the ~60s idle nudge can fire while a permission
  prompt is still unanswered).
- **stop**: `SUB <- 0`; `STATE <- white`.
- **session_start**: `STATE <- white`; `SUB <- 0`; clear topic.
- **session_end**: remove all state files (tab is gone).

### Invariants / guards

1. `white` is sticky, with one exception: only **prompt** (new turn, -> green) or
   **perm** (an actionable permission request, -> red) leave it; **stop**/
   **session_start** enter it. Everything else (`tool`, `task_start`,
   `subagent_end`, `idle`) leaves `white` untouched. This stops a late
   `SubagentStop`, a stray tool event, or the ~60s idle nudge from resurrecting
   or recoloring a finished tab, while still surfacing a real approval prompt.
2. `subagent_end` and `task_start` never override an **attention** state
   (`red`/`yellow`); they only re-resolve the working color when already working.
   `tool` is the one that clears attention states (agent is provably active again).
3. `SUB` is clamped at 0; it is fully reset to 0 by **stop** and **session_start**,
   so counter drift cannot outlive a turn.

## Transition table

Each cell is the next `STATE`. Counter changes are shown as `SUB++` / `SUB--`
(clamped at 0). `purple` is one state; whether the working color shows as
`purple` or `green` is just `SUB > 0` vs `SUB == 0`.

| current \\ event | prompt | tool | task_start | subagent_end | perm | idle | stop |
|------------------|--------|------|------------|--------------|------|------|------|
| green   | green | green  | purple (SUB++) | green        | red   | yellow | white |
| purple  | green | purple | purple (SUB++) | SUB>1 ? purple : green (SUB--) | red | yellow | white |
| yellow  | green | green  | yellow (SUB++) | yellow (SUB--) | red  | yellow | white |
| red     | green | green  | red (SUB++)    | red (SUB--)    | red  | red    | white |
| white   | green | white  | white (SUB++)  | white (SUB--)  | **red** | white | white |

Notes:
- `tool` from `yellow`/`red` resolves to the working color: `purple` if `SUB > 0`,
  else `green`.
- `white` is sticky against `idle` and tool/subagent events, but a `perm`
  (permission request) moves it to `red` because that is actionable. A new
  `prompt` moves it to `green`.
- `red` (a permission block) is sticky against `idle`: the ~60s idle nudge never
  downgrades a block to `yellow`. It clears only when the agent resumes (`tool`),
  finishes (`stop`), or a new `prompt` starts.
