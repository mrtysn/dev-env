#!/bin/zsh
# DESC: Check that the Bash PreToolUse hook commands in a Claude settings.json resolve on this machine
#
# The guards exit 2 when they cannot find their checkout, so an unconfigured
# config dir refuses every Bash tool call. Commands are read out of settings.json
# rather than restated here, so this cannot drift from the config it checks.

set -euo pipefail

SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

usage() {
    cat <<'USAGE'
usage: verify-hook-paths.sh [settings.json]

Runs each Bash PreToolUse hook command with a harmless payload (ls -la) and
reports whether it resolves. Exit 0 if all resolve, 1 otherwise.

Defaults to ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json.
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    ?*) SETTINGS=$1 ;;
esac

if [ ! -r "$SETTINGS" ]; then
    print "missing: $SETTINGS" >&2
    exit 1
fi

# A command that no guard should object to; anything nonzero means the hook
# could not be located, not that the payload was refused.
payload=$(jq -Rn '{tool_name: "Bash", cwd: $ENV.PWD, tool_input: {command: "ls -la"}}')

failed=0
count=0

while IFS= read -r cmd; do
    count=$((count + 1))
    out=$(print -r -- "$payload" | /bin/bash -c "$cmd" 2>&1 >/dev/null) || {
        failed=$((failed + 1))
        print "UNRESOLVED  ${cmd:0:60}..."
        print "            ${out%%$'\n'*}"
        continue
    }
    print "ok          ${cmd:0:60}..."
done < <(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "command") | .command' "$SETTINGS")

print ""
print "$count Bash PreToolUse hooks, $failed unresolved"
[ "$failed" -eq 0 ]
