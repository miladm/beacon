#!/bin/sh
# Exhaustive transition-matrix test for the beacon state machine.
# Every assertion here corresponds to a cell/rule in STATE_MACHINE.md.
#
# It sets a starting (STATE, SUB) directly, fires one event, and checks the
# resulting STATE (and SUB where the event touches the counter). Runs with a
# fake device and no daemon, so it never touches a real terminal.
set -u

HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$HERE/src/beacon.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; mkdir -p "$HOME"; export HOME
BEACON_STATE_DIR="$TMP/state"; export BEACON_STATE_DIR
BEACON_NO_DAEMON=1; export BEACON_NO_DAEMON
DEV="$TMP/faketty"; : > "$DEV"
BEACON_DEVICE="$DEV"; export BEACON_DEVICE

# beacon keys its files by the device path with non-alnum -> '_'
KEY=$(printf '%s' "$DEV" | tr -c 'A-Za-z0-9' '_')
SF="$BEACON_STATE_DIR/$KEY.state"
SUBF="$BEACON_STATE_DIR/$KEY.sub"
LF="$BEACON_STATE_DIR/$KEY.label"

FAILED=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAILED=$((FAILED + 1)); fi; }

setup() { mkdir -p "$BEACON_STATE_DIR"; printf '%s' "$1" > "$SF"; printf '%s' "${2:-0}" > "$SUBF"; : > "$LF"; : > "$DEV"; }
cur()   { cat "$SF" 2>/dev/null; }
cnt()   { cat "$SUBF" 2>/dev/null; }

fire() {
  case "$1" in
    capture) printf '{"cwd":"/x/proj","prompt":"topic"}' | sh "$SCRIPT" capture ;;
    perm)    printf '{"message":"needs your permission"}' | sh "$SCRIPT" notify ;;
    idle)    printf '{"message":"waiting for your input"}' | sh "$SCRIPT" notify ;;
    *)       sh "$SCRIPT" "$1" ;;
  esac
}

# t <desc> <start_state> <start_sub> <event> <expect_state> [expect_sub]
t() {
  setup "$2" "$3"
  fire "$4"
  check "$2(sub=$3) --$4--> state" "$(cur)" "$5"
  [ $# -ge 6 ] && check "$2(sub=$3) --$4--> sub" "$(cnt)" "$6"
  return 0
}

echo "-- prompt: always -> green --"
for s in green purple yellow red white; do t "prompt" "$s" 0 capture green; done

echo "-- tool: clears attention, resolves working, never resurrects white --"
t "tool" green  0 work green
t "tool" purple 1 work purple
t "tool" yellow 0 work green
t "tool" yellow 2 work purple
t "tool" red    0 work green
t "tool" red    3 work purple
t "tool" white  0 work white

echo "-- task_start: SUB++, purple only from a working/unset state --"
t "task_start" green  0 subup purple 1
t "task_start" purple 1 subup purple 2
t "task_start" yellow 0 subup yellow 1
t "task_start" red    0 subup red    1
t "task_start" white  0 subup white  1

echo "-- subagent_end: SUB--, re-resolve only if working, guard attention/done --"
t "subagent_end" purple 2 subdown purple 1
t "subagent_end" purple 1 subdown green  0
t "subagent_end" green  1 subdown green  0
t "subagent_end" red    1 subdown red    0
t "subagent_end" yellow 1 subdown yellow 0
t "subagent_end" white  1 subdown white  0
t "subagent_end" green  0 subdown green  0

echo "-- perm: always red (actionable, even from done) --"
for s in green purple yellow red white; do t "perm" "$s" 0 perm red; done
echo "-- idle: yellow, but never overrides a block (red) or done (white) --"
for s in green purple yellow; do t "idle" "$s" 0 idle yellow; done
t "idle" red   0 idle red
t "idle" white 0 idle white

echo "-- stop: -> white, SUB reset to 0 --"
t "stop" green  0 done white 0
t "stop" purple 3 done white 0
t "stop" red    0 done white 0

echo "-- start: fresh session -> white, SUB 0 --"
t "start" red 5 start white 0

echo
if [ "$FAILED" -eq 0 ]; then
  echo "State-machine matrix: all transitions correct."
else
  echo "State-machine matrix: $FAILED transition(s) wrong."
  exit 1
fi
