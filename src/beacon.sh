#!/bin/sh
# beacon - a beacon of status lights for your Claude Code terminal tabs.
#
# Paints a colored state dot in front of your VS Code terminal tab title so you
# can see, at a glance across many agent tabs, which one needs you:
#
#   green   main agent is working
#   purple  a subagent is running
#   yellow  waiting on you (idle notification)
#   red     blocked, needs your approval
#   white   done - your turn
#
# The tab TEXT stays whatever the terminal title already is (Claude Code writes
# a topic summary there); we only prefix the dot. Because Claude Code animates
# its own spinner in the title, a small per-tab background daemon repaints fast
# enough to keep the dot visible.
#
# It works by writing an OSC title escape sequence directly to the terminal's
# controlling tty (VS Code reflects that in the tab title via the
# `terminal.integrated.tabs.title: "${sequence}"` setting).
#
# Hook subcommands (wired via ~/.claude/settings.json):
#   start | capture | subup | subdown | notify | done | end
# Helpers:
#   dot <state> | version | daemon <device>
#
# Environment overrides (all optional):
#   BEACON_STATE_DIR      where per-tab state files live (default ~/.claude/beacon)
#   BEACON_DEVICE         force the target tty (mainly for tests)
#   BEACON_NO_DAEMON      set to skip launching the repaint daemon (tests)
#   BEACON_WORK_INTERVAL  repaint seconds while working (default 0.08)
#   BEACON_IDLE_INTERVAL  repaint seconds while idle (default 0.3)

VERSION=0.1.0
cmd="${1:-}"

STATE_DIR="${BEACON_STATE_DIR:-$HOME/.claude/beacon}"
WORK_INTERVAL="${BEACON_WORK_INTERVAL:-0.08}"
IDLE_INTERVAL="${BEACON_IDLE_INTERVAL:-0.3}"
mkdir -p "$STATE_DIR" 2>/dev/null

dot_for() {
  case "$1" in
    red)    printf '\360\237\224\264' ;;  # U+1F534 red circle
    yellow) printf '\360\237\237\241' ;;  # U+1F7E1 yellow circle
    green)  printf '\360\237\237\242' ;;  # U+1F7E2 green circle
    purple) printf '\360\237\237\243' ;;  # U+1F7E3 purple circle
    white)  printf '\342\232\252'     ;;  # U+26AA  white circle
    *)      printf ''                 ;;
  esac
}

case "$cmd" in
  dot)     dot_for "${2:-}"; exit 0 ;;
  version) echo "beacon $VERSION"; exit 0 ;;
  help|-h|--help|"")
    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# Turn an arbitrary device path into a safe filename key.
key_for() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

# Read a top-level string field from JSON on stdin. Prefers jq, falls back to
# python3; if neither exists it prints nothing (topic capture is skipped).
json_get() {
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); v=d.get(sys.argv[1],"")
    sys.stdout.write("" if v is None else str(v))
except Exception:
    pass' "$1"
  fi
}

# ---- daemon: tight repaint loop; device is passed in so no process walk ------
if [ "$cmd" = daemon ]; then
  dev="${2:-}"; [ -n "$dev" ] || exit 0
  k=$(key_for "$dev")
  STATE="$STATE_DIR/$k.state"; LABEL="$STATE_DIR/$k.label"
  while : ; do
    [ -w "$dev" ] || exit 0
    st=""; [ -r "$STATE" ] && IFS= read -r st < "$STATE" 2>/dev/null
    lb=""; [ -r "$LABEL" ] && IFS= read -r lb < "$LABEL" 2>/dev/null
    [ -n "$lb" ] || lb=${PWD##*/}
    case "$st" in
      red)    dot='\360\237\224\264' ;;
      yellow) dot='\360\237\237\241' ;;
      green)  dot='\360\237\237\242' ;;
      purple) dot='\360\237\237\243' ;;
      white)  dot='\342\232\252'     ;;
      *)      dot=''                 ;;
    esac
    printf "\033]0;$dot %s\007" "$lb" > "$dev" 2>/dev/null
    case "$st" in green|purple) sleep "$WORK_INTERVAL" ;; *) sleep "$IDLE_INTERVAL" ;; esac
  done
fi

# ---- resolve the controlling terminal device --------------------------------
resolve_dev() {
  if [ -n "${BEACON_DEVICE:-}" ]; then dev="$BEACON_DEVICE"; return 0; fi
  pid=$$; dev=""
  while [ "${pid:-0}" -gt 1 ]; do
    t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$t" in
      ttys*|tty[0-9]*) dev="/dev/$t"; return 0 ;;   # macOS / some linux
      pts/*)           dev="/dev/$t"; return 0 ;;   # linux
      s[0-9]*)         dev="/dev/tty$t"; return 0 ;; # bsd short form
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$pid" in ''|*[!0-9]*) break ;; esac
  done
  return 1
}
resolve_dev || exit 0

k=$(key_for "$dev")
STATE="$STATE_DIR/$k.state"; LABEL="$STATE_DIR/$k.label"
SUB="$STATE_DIR/$k.sub";     PIDF="$STATE_DIR/$k.pid"

paint() {
  lb=""; [ -r "$LABEL" ] && IFS= read -r lb < "$LABEL" 2>/dev/null
  [ -n "$lb" ] || lb=${PWD##*/}
  st=""; [ -r "$STATE" ] && IFS= read -r st < "$STATE" 2>/dev/null
  dot=$(dot_for "$st")
  if [ -w "$dev" ]; then printf "\033]0;$dot %s\007" "$lb" > "$dev" 2>/dev/null; fi
  return 0
}

start_daemon() {
  [ -n "${BEACON_NO_DAEMON:-}" ] && return 0
  if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then return 0; fi
  nohup "$0" daemon "$dev" >/dev/null 2>&1 &
  echo $! > "$PIDF"
}

case "$cmd" in
  start)                                    # SessionStart: fresh session
    echo white > "$STATE"; echo 0 > "$SUB"; : > "$LABEL"
    start_daemon; paint ;;
  capture)                                  # UserPromptSubmit: topic + working
    input=$(cat)
    if [ ! -s "$LABEL" ]; then
      cwd=$(printf '%s' "$input" | json_get cwd)
      prompt=$(printf '%s' "$input" | json_get prompt | tr '\n\t' '  ' | sed 's/[[:space:]]*$//')
      if [ -n "$prompt" ]; then
        folder=""; [ -n "$cwd" ] && folder=$(basename "$cwd")
        printf '%s - %s' "$folder" "$prompt" | cut -c1-60 > "$LABEL"
      fi
    fi
    echo green > "$STATE"; start_daemon; paint ;;
  subup)                                    # PreToolUse(Task): subagent started
    n=$(cat "$SUB" 2>/dev/null); n=$(( ${n:-0} + 1 )); echo "$n" > "$SUB"
    cur=""; [ -r "$STATE" ] && IFS= read -r cur < "$STATE" 2>/dev/null
    case "$cur" in green|purple|"") echo purple > "$STATE" ;; esac
    paint ;;
  subdown)                                  # SubagentStop: a subagent finished
    n=$(cat "$SUB" 2>/dev/null); n=$(( ${n:-1} - 1 )); [ "$n" -lt 0 ] && n=0; echo "$n" > "$SUB"
    # Only adjust color while actually working; never resurrect a finished/idle
    # tab -- a straggler SubagentStop can arrive at or after Stop.
    cur=""; [ -r "$STATE" ] && IFS= read -r cur < "$STATE" 2>/dev/null
    case "$cur" in
      green|purple) if [ "$n" -gt 0 ]; then echo purple > "$STATE"; else echo green > "$STATE"; fi ;;
    esac
    paint ;;
  work)                                     # Pre/PostToolUse: agent is active again
    # Any tool activity means the agent resumed; recompute the working state.
    # This clears red/yellow after you unblock it. Never resurrect a done tab.
    cur=""; [ -r "$STATE" ] && IFS= read -r cur < "$STATE" 2>/dev/null
    if [ "$cur" != white ]; then
      n=$(cat "$SUB" 2>/dev/null); n=${n:-0}
      if [ "$n" -gt 0 ]; then echo purple > "$STATE"; else echo green > "$STATE"; fi
    fi
    paint ;;
  notify)                                   # Notification: blocked or idle (never overrides done)
    input=$(cat); msg=$(printf '%s' "$input" | json_get message)
    cur=""; [ -r "$STATE" ] && IFS= read -r cur < "$STATE" 2>/dev/null
    if [ "$cur" != white ]; then
      case "$msg" in *ermission*) echo red > "$STATE" ;; *) echo yellow > "$STATE" ;; esac
    fi
    paint ;;
  done)                                     # Stop: turn finished
    echo 0 > "$SUB"; echo white > "$STATE"; paint ;;
  end)                                      # SessionEnd: cleanup
    [ -f "$PIDF" ] && kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null
    rm -f "$PIDF" "$STATE" "$SUB" "$LABEL" ;;
  *)
    echo "beacon: unknown command '$cmd' (try: help)" >&2; exit 2 ;;
esac
