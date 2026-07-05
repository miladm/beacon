#!/usr/bin/env bash
# beacon uninstaller - removes the hooks and script it installed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
SCRIPT_DEST="$CLAUDE_DIR/hooks/beacon.sh"
STATE_DIR="${BEACON_STATE_DIR:-$CLAUDE_DIR/beacon}"

echo "uninstalling beacon..."

if command -v python3 >/dev/null 2>&1; then
  python3 "$HERE/scripts/remove_hooks.py" "$SETTINGS" >/dev/null || true
  echo "  hooks removed from $SETTINGS"
else
  echo "  python3 not found; remove the beacon hook entries from $SETTINGS manually"
fi

rm -f "$SCRIPT_DEST" && echo "  removed $SCRIPT_DEST" || true
rm -rf "$STATE_DIR"  && echo "  removed state dir $STATE_DIR" || true

cat <<'EOF'

Done. The VS Code setting was not auto-added, so nothing to revert there
(remove "terminal.integrated.tabs.title": "${sequence}" yourself if you like).
Reload VS Code and relaunch claude to fully clear it.
EOF
