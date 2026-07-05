#!/bin/sh
# beacon test suite.
#
# Runs without a real terminal by pointing BEACON_DEVICE at a temp file and
# disabling the repaint daemon. Pure POSIX sh so anyone can run it: ./tests/run.sh
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

FAILED=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; FAILED=$((FAILED + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want [$3] got [$2])"; fi; }

state() { cat "$BEACON_STATE_DIR"/*.state 2>/dev/null; }
label() { cat "$BEACON_STATE_DIR"/*.label 2>/dev/null; }
sub()   { cat "$BEACON_STATE_DIR"/*.sub   2>/dev/null; }
reset() { rm -rf "$BEACON_STATE_DIR"; mkdir -p "$BEACON_STATE_DIR"; : > "$DEV"; }

# 1. dot color mapping
check "dot green"  "$(sh "$SCRIPT" dot green)"  "$(printf '\360\237\237\242')"
check "dot red"    "$(sh "$SCRIPT" dot red)"    "$(printf '\360\237\224\264')"
check "dot yellow" "$(sh "$SCRIPT" dot yellow)" "$(printf '\360\237\237\241')"
check "dot purple" "$(sh "$SCRIPT" dot purple)" "$(printf '\360\237\237\243')"
check "dot white"  "$(sh "$SCRIPT" dot white)"  "$(printf '\342\232\252')"

# 2. capture records topic and sets working
reset
printf '{"cwd":"/tmp/myproj","prompt":"fix the thing"}' | sh "$SCRIPT" capture
check "capture -> green"      "$(state)" "green"
check "capture -> topic"      "$(label)" "myproj - fix the thing"

# 3. topic is persistent (second prompt does not overwrite)
printf '{"cwd":"/tmp/other","prompt":"different task"}' | sh "$SCRIPT" capture
check "topic persists"        "$(label)" "myproj - fix the thing"

# 4. subagent counter drives purple, restores green at zero
reset
sh "$SCRIPT" subup
check "subup -> purple"       "$(state)" "purple"
check "subup -> count 1"      "$(sub)"   "1"
sh "$SCRIPT" subup
check "subup2 -> count 2"     "$(sub)"   "2"
sh "$SCRIPT" subdown
check "subdown -> still purple" "$(state)" "purple"
check "subdown -> count 1"    "$(sub)"   "1"
sh "$SCRIPT" subdown
check "subdown0 -> green"     "$(state)" "green"
check "subdown0 -> count 0"   "$(sub)"   "0"

# 5. done and notification states
sh "$SCRIPT" done
check "done -> white"         "$(state)" "white"
printf '{"message":"Claude needs your permission to run bash"}' | sh "$SCRIPT" notify
check "notify permission -> red" "$(state)" "red"
printf '{"message":"Claude is waiting for your input"}' | sh "$SCRIPT" notify
check "notify idle -> yellow" "$(state)" "yellow"

# 6. the device actually receives the topic text
reset
printf '{"cwd":"/x/demo","prompt":"hello world"}' | sh "$SCRIPT" capture
if grep -a -q "demo - hello world" "$DEV"; then pass "device receives topic"; else fail "device receives topic"; fi

# 7. graceful when the target device is not writable
reset
if ( BEACON_DEVICE="$TMP/nope/none"; export BEACON_DEVICE
     printf '{}' | sh "$SCRIPT" done >/dev/null 2>&1 ); then
  pass "unwritable device is graceful"
else
  fail "unwritable device is graceful"
fi

# 8. version and help do not error
sh "$SCRIPT" version >/dev/null 2>&1 && pass "version ok" || fail "version ok"
sh "$SCRIPT" help    >/dev/null 2>&1 && pass "help ok"    || fail "help ok"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All tests passed."
else
  echo "$FAILED test(s) failed."
  exit 1
fi
