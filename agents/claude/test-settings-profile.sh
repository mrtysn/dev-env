#!/bin/zsh
# DESC: Self-check for settings-profile.sh: merge rules, drift refusal, overlay errors
#
# Runs against fixtures in a temp dir, never against a live config folder.
# Also checks that every committed overlay merges cleanly with the base.

set -euo pipefail

SCRIPT_DIR=${0:A:h}
TOOL="$SCRIPT_DIR/settings-profile.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/settings-profile-test.XXXXXX")
trap 'rm -rf -- "$T"' EXIT
pass=0; failed=0
ok()  { pass=$((pass + 1)) }
bad() { failed=$((failed + 1)); print -r -- "FAIL: $1" >&2 }
expect() { if [[ "$2" == "$3" ]]; then ok; else bad "$1: expected <$3>, got <$2>"; fi }

mkdir -p "$T/ov" "$T/cfg"
cat > "$T/base.json" <<'JSON'
{"model": "opus", "list": ["a", "b"],
 "autoMode": {"allow": ["$defaults"],
   "environment": ["### One", "**Org**: None configured", "**Repo**: generic", "### Two", "**Use**: None configured"]},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "base-stop"}]}]}}
JSON
cat > "$T/ov/p.json" <<'JSON'
{"model": "sonnet", "list": ["b", "c"],
 "autoMode": {"allow": ["deploy"], "environment": ["**Use**: personal", "**Org**: none", "**Extra**: new"]},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "p-stop"}]}],
           "SessionStart": [{"hooks": [{"type": "command", "command": "p-start"}]}]}}
JSON
print -r -- '{"model": "haiku"}' > "$T/ov/p.local.json"
print -r -- '{"model": "<FILL: model>"}' > "$T/ov/w.json.example"

run() { SETTINGS_BASE="$T/base.json" SETTINGS_OVERLAY_DIR="$T/ov" "$TOOL" "$@" }

m=$(run merge p)
expect "scalar: local overlay wins last" "$(jq -r .model <<<"$m")" "haiku"
expect "arrays concatenate without repeats" "$(jq -c .list <<<"$m")" '["a","b","c"]'
expect "allow keeps \$defaults first" "$(jq -c .autoMode.allow <<<"$m")" '["$defaults","deploy"]'
expect "environment merges by label, in base order" "$(jq -c .autoMode.environment <<<"$m")" \
    '["### One","**Org**: none","**Repo**: generic","### Two","**Use**: personal","**Extra**: new"]'
expect "hook groups concatenate" "$(jq -c '[.hooks.Stop[].hooks[].command]' <<<"$m")" '["base-stop","p-stop"]'
expect "new hook event added" "$(jq -c '[.hooks.SessionStart[].hooks[].command]' <<<"$m")" '["p-start"]'

# A live file equal up to hook order, survey state and env.AGENTS_SHARED matches.
jq '.hooks.Stop |= reverse | .feedbackSurveyState = {"x": 1} | .env.AGENTS_SHARED = "/somewhere"' <<<"$m" > "$T/cfg/settings.json"
print -r -- 'AGENT_PROFILE=p' > "$T/cfg/paths.local.sh"
if run check "$T/cfg" >/dev/null; then ok; else bad "reordered hooks should match"; fi

# Drift is refused and the keys are named.
jq '.model = "x" | .autoMode.environment[1] = "**Org**: changed" | .extra = 1' <<<"$m" > "$T/cfg/settings.json"
out=$(run check "$T/cfg" 2>&1) && bad "drift should exit 1" || expect "drift exit code" "$?" "1"
for k in model autoMode.environment extra; do
    print -r -- "$out" | grep -qx "  $k" && ok || bad "drift output should name $k"
done

# Error paths exit 2 with a message.
run merge none >/dev/null 2>&1 && bad "missing overlay should fail" || expect "missing overlay exit" "$?" "2"
out=$(run merge w 2>&1 || true)
print -r -- "$out" | grep -q 'copy .*w.json.example' && ok || bad "an example-only profile should say to copy the example"
print -r -- '{"model": "<FILL: model>"}' > "$T/ov/w.local.json"
out=$(run merge w 2>&1 || true)
print -r -- "$out" | grep -q 'placeholders' && ok || bad "unfilled placeholders should be refused"
: > "$T/cfg/paths.local.sh"
run check "$T/cfg" >/dev/null 2>&1 && bad "no AGENT_PROFILE should fail" || expect "no profile exit" "$?" "2"

# Every committed overlay merges with the real base.
for ov in "$SCRIPT_DIR"/overlays/*.json(N); do
    p=${${ov:t:r}%.local}
    "$TOOL" merge "$p" >/dev/null 2>&1 && ok || bad "committed overlay ${ov:t} does not merge with the base"
done

print -r -- "settings-profile: $pass passed, $failed failed"
(( failed == 0 ))
