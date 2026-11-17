#!/bin/zsh
# DESC: Build a Claude settings.json from the base file and a profile's overlays, and check a live one against it
#
# A Claude config folder's settings.json is not stored whole. It is
#
#     settings.json  (base: valid on every machine and profile)
#   + overlays/<profile>.json        (committed overlay, if the profile has one)
#   + overlays/<profile>.local.json  (untracked overlay, if this machine has one)
#
# where <profile> is the AGENT_PROFILE the folder declares in its paths.local.sh.
#
# Merge rules (jq's own `*` replaces arrays whole, which would make an overlay restate
# every base hook and environment line):
#   - objects merge key by key, the overlay winning on scalars;
#   - arrays concatenate, base first, skipping overlay items already in the base;
#   - autoMode.environment is merged by field label: a line "**Label**: text" in an
#     overlay replaces the base line with the same label in place, so the section order
#     of the base is kept; overlay lines with a new label are appended.
#
# Comparing a live file ignores what is machine-local (feedbackSurveyState,
# env.AGENTS_SHARED, and theme, which Claude Code's theme picker writes) and the order of hooks within an event, which Claude Code runs
# in parallel: each hook is compared as an (event, matcher, hook) triple.

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
BASE="${SETTINGS_BASE:-$SCRIPT_DIR/settings.json}"
OVERLAY_DIR="${SETTINGS_OVERLAY_DIR:-$SCRIPT_DIR/overlays}"

usage() {
    cat <<'USAGE'
usage: settings-profile.sh merge PROFILE
       settings-profile.sh check CONFIG_DIR [PROFILE]
       settings-profile.sh profile CONFIG_DIR
       settings-profile.sh overlays PROFILE
       settings-profile.sh dirs

  merge     print base + PROFILE's overlays as one settings.json (sorted keys)
  check     exit 0 when CONFIG_DIR/settings.json equals merge(PROFILE); otherwise
            exit 1, name the keys that differ and show their diff. PROFILE defaults
            to the folder's own.
  profile   print the AGENT_PROFILE declared in CONFIG_DIR/paths.local.sh
  overlays  print the overlay files PROFILE uses, one per line
  dirs      print this machine's Claude config folders, one per line: the
            space-separated $CLAUDE_CONFIG_DIRS when set, otherwise ~/.claude and every
            ~/.claude-* folder that holds a settings.json or paths.local.sh
USAGE
}

die() { print -r -- "settings-profile.sh: $*" >&2; exit 2 }

# What a live file carries that the repo never does.
STRIP='del(.feedbackSurveyState) | del(.theme) | del(.env.AGENTS_SHARED) | if .env == {} then del(.env) else . end'

MERGE_JQ='
def lbl: if type == "string" then (capture("^\\*\\*(?<l>[^*]+)\\*\\*:").l // null) else null end;
def envmerge($a; $b):
  ([$b[] | lbl | select(. != null)]) as $blabels
  | ([$a[] | lbl | select(. != null)]) as $alabels
  | ($a | map(lbl as $l
        | if $l != null and ($blabels | index($l)) then ([$b[] | select(lbl == $l)] | last) else . end))
    + [$b[] | select((lbl) as $l | $l == null or ($alabels | index($l) | not))];
def m($a; $b; $path):
  if ($a | type) == "object" and ($b | type) == "object" then
    reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = (if has($k) then m($a[$k]; $b[$k]; $path + [$k]) else $b[$k] end))
  elif ($a | type) == "array" and ($b | type) == "array" then
    if $path == ["autoMode", "environment"] then envmerge($a; $b) else $a + ($b - $a) end
  else $b end;
reduce .[1:][] as $o (.[0]; m(.; $o; []))
'

CANON_JQ='
if .hooks then
  .hooks |= with_entries(.value |= ([.[] | (.matcher // null) as $m | .hooks[] | {matcher: $m, hook: .}] | sort))
else . end
'

DIFF_JQ='
def dk($a; $b):
  [(($a | keys) + ($b | keys) | unique[]) as $k
   | select($a[$k] != $b[$k])
   | if ($a[$k] | type) == "object" and ($b[$k] | type) == "object"
     then (dk($a[$k]; $b[$k])[] | "\($k).\(.)")
     else $k end];
dk(.[0]; .[1])[]
'

overlays_for() {
    local profile=$1 committed="$OVERLAY_DIR/$1.json" local_file="$OVERLAY_DIR/$1.local.json"
    [[ "$profile" =~ '^[a-z0-9-]+$' ]] || die "profile name must be lowercase letters, digits or -: '$profile'"
    if [[ ! -f "$committed" && ! -f "$local_file" ]]; then
        if [[ -f "$committed.example" ]]; then
            die "profile '$profile' has no overlay yet: copy ${committed#$REPO_ROOT/}.example to ${local_file#$REPO_ROOT/} (untracked) and fill in its <FILL: ...> placeholders"
        fi
        die "profile '$profile' has no overlay: expected ${committed#$REPO_ROOT/} or ${local_file#$REPO_ROOT/}"
    fi
    [[ -f "$committed" ]] && print -r -- "$committed"
    [[ -f "$local_file" ]] && print -r -- "$local_file"
    return 0
}

merge() {
    local profile=$1 f ov
    local -a files
    [[ -f "$BASE" ]] || die "base settings not found: $BASE"
    ov=$(overlays_for "$profile") || exit 2
    files=("$BASE" "${(@f)ov}")
    for f in "${files[@]}"; do
        jq -e 'type == "object"' "$f" >/dev/null 2>&1 || die "not a JSON object: $f"
        if grep -q '<FILL:' "$f"; then
            die "$f still has <FILL: ...> placeholders: $(grep -o '<FILL:[^>]*>' "$f" | sort -u | tr '\n' ' ')"
        fi
    done
    jq -S -s "$MERGE_JQ" "${files[@]}"
}

folder_profile() {
    local dir=$1 p=""
    [[ -r "$dir/paths.local.sh" ]] && p=$(AGENT_PROFILE=""; . "$dir/paths.local.sh" >/dev/null 2>&1; print -r -- "${AGENT_PROFILE:-}")
    print -r -- "$p"
}

# Every hook and status line command that sources paths.local.sh and reads ${NAME:-} must find
# NAME set there, or it exits 0 and silently does nothing (the status line went blank this way
# on 2026-11-16). Prints each missing NAME; exit 1 when any is missing.
missing_local_vars() {
    local dir=$1 settings=$2 name value missing=0
    local -a names
    names=(${(f)"$(jq -r '[.. | strings | select(test("paths\\.local\\.sh"))
        | [scan("\\$\\{([A-Z][A-Z0-9_]*):-\\}")[0]] | .[]] | unique | .[]' "$settings")"})
    # Unset by design where the tool is not installed (paths.local.sh.example says so for each).
    local -a optional=(CLAUDE_CONFIG_DIR ARL_DIR CC_STATUS_PATH SYSTEM_ONE_DIR)  # their hooks exit 0 when unset
    for name in $names; do
        (( ${optional[(Ie)$name]} )) && continue
        value=$(unset $name; [[ -r "$dir/paths.local.sh" ]] && . "$dir/paths.local.sh" >/dev/null 2>&1; print -r -- "${(P)name:-}")
        if [[ -z "$value" ]]; then
            print -r -- "$name"
            missing=1
        fi
    done
    return $missing
}

check() {
    local dir=$1 profile=${2:-} live="$1/settings.json" diffs
    [[ -f "$live" ]] || die "no settings.json in $dir"
    if [[ -z "$profile" ]]; then
        profile=$(folder_profile "$dir")
        [[ -n "$profile" ]] || die "$dir/paths.local.sh declares no AGENT_PROFILE (write one with: CLAUDE_DIR=$dir ${SCRIPT_DIR#$REPO_ROOT/}/write-paths-local.sh --profile NAME)"
    fi
    local expected
    expected=$(merge "$profile") || exit 2
    diffs=$(jq -n -r --slurpfile live "$live" --argjson want "$expected" \
        "[(\$live[0] | $STRIP | $CANON_JQ), (\$want | $STRIP | $CANON_JQ)] | $DIFF_JQ") || die "could not compare $live"
    if [[ -n "$diffs" ]]; then
        print -r -- "$live differs from base + '$profile' overlays in:"
        print -r -- "$diffs" | sed 's/^/  /'
        # The differing top-level keys side by side (repo first), to port by hand into
        # the base or an overlay. Hooks show in their compared form: one row per hook.
        local keys
        keys=$(print -r -- "$diffs" | cut -d. -f1 | sort -u | jq -R . | jq -sc .)
        print -r -- "  diff (- repo, + live), first 60 lines:"
        diff -u \
            <(print -r -- "$expected" | jq -S --argjson k "$keys" "$STRIP | $CANON_JQ | with_entries(select(.key as \$x | \$k | index(\$x)))") \
            <(jq -S --argjson k "$keys" "$STRIP | $CANON_JQ | with_entries(select(.key as \$x | \$k | index(\$x)))" "$live") \
            | tail -n +3 | head -60 | cut -c1-160 | sed 's/^/    /' || true
        return 1
    fi
    local unset_vars
    if ! unset_vars=$(missing_local_vars "$dir" "$live"); then
        print -r -- "$live matches base + '$profile' overlays, but its commands read variables $dir/paths.local.sh does not set, so they silently do nothing:"
        print -r -- "$unset_vars" | sed 's/^/  /'
        print -r -- "  Fix: CLAUDE_DIR=$dir ${SCRIPT_DIR#$REPO_ROOT/}/write-paths-local.sh (or add NAME=\"<path>\" lines to that file)"
        return 1
    fi
    print -r -- "$live matches base + '$profile' overlays"
}

dirs() {
    local d
    if [[ -n "${CLAUDE_CONFIG_DIRS:-}" ]]; then
        for d in ${=CLAUDE_CONFIG_DIRS}; do print -r -- "${d%/}"; done
        return 0
    fi
    print -r -- "$HOME/.claude"
    for d in "$HOME"/.claude-*(N/); do
        [[ -f "$d/settings.json" || -f "$d/paths.local.sh" ]] && print -r -- "$d"
    done
    return 0
}

command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq)"

case "${1:-}" in
    merge)    (( $# == 2 )) || { usage >&2; exit 2 }; merge "$2" ;;
    check)    (( $# >= 2 && $# <= 3 )) || { usage >&2; exit 2 }; check "$2" "${3:-}" ;;
    profile)  (( $# == 2 )) || { usage >&2; exit 2 }; folder_profile "$2" ;;
    overlays) (( $# == 2 )) || { usage >&2; exit 2 }; overlays_for "$2" ;;
    dirs)     dirs ;;
    -h|--help) usage ;;
    *)        usage >&2; exit 2 ;;
esac
