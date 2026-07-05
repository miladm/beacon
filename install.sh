#!/usr/bin/env bash
# beacon installer - wires the state-dot hooks into Claude Code and points
# you at the one VS Code setting you need.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
SCRIPT_DEST="$HOOKS_DIR/beacon.sh"

say() { printf '  %s\n' "$1"; }

echo "installing beacon..."

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required (used to safely merge settings.json)." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "error: need jq or python3 for topic capture." >&2
  exit 1
fi

# 1. install the script
mkdir -p "$HOOKS_DIR"
install -m 0755 "$HERE/src/beacon.sh" "$SCRIPT_DEST"
say "script  -> $SCRIPT_DEST"

# 2. merge hooks into Claude Code settings.json (idempotent, backs up first)
python3 "$HERE/scripts/merge_hooks.py" "$SETTINGS" "$SCRIPT_DEST" >/dev/null
say "hooks   -> $SETTINGS (backup at $SETTINGS.bak)"

# 3. VS Code setting (printed, not auto-edited, since settings.json may have comments)
echo
echo "One VS Code setting is required. Add this to your VS Code user settings.json:"
echo
echo '    "terminal.integrated.tabs.title": "${sequence}"'
echo
echo "Likely settings.json locations on this machine:"
for p in \
  "$HOME/Library/Application Support/Code/User/settings.json" \
  "$HOME/Library/Application Support/Code - Insiders/User/settings.json" \
  "$HOME/Library/Application Support/VSCodium/User/settings.json" \
  "$HOME/.config/Code/User/settings.json" \
  "$HOME/.config/Code - Insiders/User/settings.json" \
  "$HOME/.config/VSCodium/User/settings.json"; do
  [ -f "$p" ] && say "$p"
done

cat <<'EOF'

Done. To activate:
  1. Reload VS Code:  Command Palette -> "Developer: Reload Window"
  2. Relaunch any running `claude` sessions (hooks load at startup)

Then a working tab shows a green dot, done shows white, needs-approval red, etc.
Uninstall any time with ./uninstall.sh
EOF
