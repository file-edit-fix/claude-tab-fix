#!/bin/sh
# install-global.sh — Install claude-tab-fix hooks into the global Claude Code settings
#
# Usage: ./scripts/install-global.sh
#
# This script adds the claude-tab-fix hooks to your global ~/.claude/settings.json
# so they activate in every project (including worktrees).

set -e

# --- Find the global settings file ---
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
  SETTINGS_DIR="$CLAUDE_CONFIG_DIR"
else
  SETTINGS_DIR="$HOME/.claude"
fi
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

# --- Check if claude-tab-fix binary is in PATH ---
if ! command -v claude-tab-fix >/dev/null 2>&1; then
  echo "ERROR: 'claude-tab-fix' binary not found in PATH."
  echo "Install it first: go install github.com/WithHolm/claude-tab-fix@latest"
  exit 1
fi

echo "claude-tab-fix binary found at: $(command -v claude-tab-fix)"

# --- Ensure settings directory exists ---
mkdir -p "$SETTINGS_DIR"

# --- Hook configuration template ---
read -r HOOKS_JSON << 'HOOKEOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      },
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      }
    ]
  }
}
HOOKEOF

# --- Merge hooks into settings ---
if [ -f "$SETTINGS_FILE" ]; then
  echo "Found existing settings file: $SETTINGS_FILE"

  # Check if claude-tab-fix hooks are already present in hooks section
  # (not just anywhere in the file — "enabledPlugins" also contains the string)
  if python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    config = json.load(f)
hooks = config.get('hooks', {})
for hook_type in ['PreToolUse', 'PostToolUse']:
    for h in hooks.get(hook_type, []):
        for hook in h.get('hooks', []):
            if hook.get('command') == 'claude-tab-fix':
                print('found')
                exit(0)
exit(1)
  " 2>/dev/null | grep -q found; then
    echo "claude-tab-fix hooks are already configured in the global settings."
    echo "No changes made."
    exit 0
  fi

  # Use Python to merge the hooks into the existing JSON
  python3 << 'PYEOF'
import json
import sys

settings_file = sys.argv[1]
hooks_json = sys.stdin.read()

with open(settings_file, 'r') as f:
    config = json.load(f)

hooks_config = json.loads(hooks_json)

if 'hooks' not in config:
    config['hooks'] = {}

for hook_type in ['PreToolUse', 'PostToolUse']:
    if hook_type not in config['hooks']:
        config['hooks'][hook_type] = []
    existing_matchers = {h.get('matcher') for h in config['hooks'].get(hook_type, [])}
    for new_hook in hooks_config['hooks'].get(hook_type, []):
        if new_hook['matcher'] not in existing_matchers:
            config['hooks'][hook_type].append(new_hook)
            print(f'Added {hook_type}/{new_hook["matcher"]} hook')

with open(settings_file, 'w') as f:
    json.dump(config, f, indent=2)
PYEOF

  echo "$HOOKS_JSON" | python3 - "$SETTINGS_FILE"
  echo "Settings file updated successfully."
else
  echo "No existing settings file. Creating new one..."
  echo "$HOOKS_JSON" > "$SETTINGS_FILE"
  echo "Settings file created at $SETTINGS_FILE"
fi

# --- Verify ---
echo ""
echo "=== Verification ==="
if python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    config = json.load(f)
hooks = config.get('hooks', {})
for hook_type in ['PreToolUse', 'PostToolUse']:
    for h in hooks.get(hook_type, []):
        for hook in h.get('hooks', []):
            if hook.get('command') == 'claude-tab-fix':
                print('found')
                exit(0)
exit(1)
" 2>/dev/null | grep -q found; then
  echo "PASS: claude-tab-fix hooks found in $SETTINGS_FILE"
  echo ""
  echo "The hook will now activate in ALL projects, including worktrees."
  echo "To test it, run:"
  echo "  echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/path/to/tab/file.go\",\"old_string\":\"    func\",\"new_string\":\"    func\"}}' | claude-tab-fix"
  echo ""
  echo "Expected: exit code 2 with indent normalization message"
else
  echo "FAIL: claude-tab-fix hooks not found in $SETTINGS_FILE"
  echo "Please check the file manually."
  exit 1
fi