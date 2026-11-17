#!/bin/zsh
# DESC: Write the machine-local paths.local.sh that Claude's guard hooks read
#
# The PreToolUse guards in settings.json source AGENTS_SHARED_DIR from
# ${CLAUDE_DIR:-$HOME/.claude}/paths.local.sh and exit 2 when it is unset, so a
# config dir without that file refuses every Bash tool call.
#
# The checkout is derived, in order, from an explicit --path, an exported
# AGENTS_SHARED_DIR, a rules symlink in the config dir, or a sibling checkout
# beside this repo. A candidate must contain the hooks to be accepted; with none
# found, the script asks.
#
# --profile also records the folder's agent profile (AGENT_PROFILE=work|personal),
# which import.sh and export.sh read to pick the settings overlay. Rewriting the
# file keeps every other line in it (SYSTEM_ONE_DIR, CC_STATUS_PATH, ...). It also records
# CC_STATUSLINE_DIR when a cc-statusline checkout sits beside this repo.

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}

# CLAUDE_DIR, not CLAUDE_CONFIG_DIR: the latter is session-contextual (the
# claudep alias flips it), matching how export.sh and import.sh resolve this.
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

ASSUME_YES=0
FORCE=0
WANT_PATH=""
WANT_PROFILE=""

usage() {
    cat <<'USAGE'
usage: write-paths-local.sh [--path DIR] [--profile NAME] [--yes] [--force]

Writes ${CLAUDE_DIR:-$HOME/.claude}/paths.local.sh with AGENTS_SHARED_DIR set to
this machine's agents-shared checkout, which the guard hooks in settings.json
source at run time.

  --path DIR   use this checkout instead of detecting one
  --profile N  set AGENT_PROFILE=N (work, personal, ...) for this config folder
  --yes        accept the detected path without prompting
  --force      rewrite the file even if it already resolves

Exits nonzero if no valid checkout could be resolved, leaving the guards
blocking rather than silently disabled.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --path) WANT_PATH=${2-}; shift 2 ;;
        --path=*) WANT_PATH=${1#--path=}; shift ;;
        --profile) WANT_PROFILE=${2-}; shift 2 ;;
        --profile=*) WANT_PROFILE=${1#--profile=}; shift ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) print "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

TARGET="$CLAUDE_DIR/paths.local.sh"
SHOWN_TARGET="${TARGET/#$HOME/~}"
# Whether the file was there before this run: a profile line written just below must not
# make a new file look like an old one to report and back up.
PRE_EXISTED=0; [ -f "$TARGET" ] && PRE_EXISTED=1

# A candidate counts only if it really is an agents-shared checkout.
is_checkout() {
    [ -n "${1:-}" ] && [ -x "$1/hooks/require-absolute-rm.sh" ]
}

if [[ -n "$WANT_PROFILE" && ! "$WANT_PROFILE" =~ '^[a-z0-9-]+$' ]]; then
    print "profile must be lowercase letters, digits or -: $WANT_PROFILE" >&2
    exit 1
fi

# Replace one VAR="value" assignment in TARGET, keeping every other line.
set_var() {
    local var=$1 value=$2 kept=""
    mkdir -p "$CLAUDE_DIR"
    if [ -f "$TARGET" ]; then
        kept=$(grep -v "^${var}=" "$TARGET" || true)
    else
        kept="# Machine-local paths for hook commands in settings.json. Not committed:
# ~/.claude is not a repo, and dev-env/export.sh reads only settings.json.
# Written by dev-env/agents/claude/write-paths-local.sh; the committed shape is
# dev-env/agents/claude/paths.local.sh.example.
"
    fi
    print -r -- "$kept" > "$TARGET.tmp"
    print -r -- "${var}=\"${value}\"" >> "$TARGET.tmp"
    mv "$TARGET.tmp" "$TARGET"
}

# The status line reads CC_STATUSLINE_DIR from the same file and shows nothing when it is
# unset. Set it only from a cc-statusline checkout beside this repo; never overwrite a value.
ensure_statusline() {
    local current=""
    [ -r "$TARGET" ] && current=$(CC_STATUSLINE_DIR=""; . "$TARGET" >/dev/null 2>&1; print -r -- "${CC_STATUSLINE_DIR:-}")
    [ -n "$current" ] && return 0
    local candidate="${REPO_ROOT:h}/cc-statusline"
    if [ -x "$candidate/cc-statusline.js" ]; then
        set_var CC_STATUSLINE_DIR "$candidate"
        print "✓ Set CC_STATUSLINE_DIR=$candidate in $SHOWN_TARGET"
    else
        print "! No cc-statusline checkout beside this repo: this folder's status line stays blank. Clone it, then re-run this script (README, \"Setting up a fresh config folder\")."
    fi
}

if [ -n "$WANT_PROFILE" ]; then
    current=""
    [ -r "$TARGET" ] && current=$(AGENT_PROFILE=""; . "$TARGET" >/dev/null 2>&1; print -r -- "${AGENT_PROFILE:-}")
    if [ "$current" != "$WANT_PROFILE" ]; then
        set_var AGENT_PROFILE "$WANT_PROFILE"
        print "✓ Set AGENT_PROFILE=$WANT_PROFILE in $SHOWN_TARGET"
    fi
fi

# Already configured and working — nothing to do.
if [ "$FORCE" -eq 0 ] && [ -r "$TARGET" ]; then
    existing=$(AGENTS_SHARED_DIR=""; . "$TARGET" >/dev/null 2>&1; print -r -- "${AGENTS_SHARED_DIR:-}")
    if is_checkout "$existing"; then
        print "✓ $SHOWN_TARGET already resolves to $existing"
        ensure_statusline
        exit 0
    fi
    (( PRE_EXISTED )) && print "! $SHOWN_TARGET exists but does not resolve to a checkout; rewriting"
fi

resolved=""
source_of=""

# 1. Explicit argument wins.
if [ -n "$WANT_PATH" ]; then
    if ! is_checkout "$WANT_PATH"; then
        print "not an agents-shared checkout (no hooks/require-absolute-rm.sh): $WANT_PATH" >&2
        exit 1
    fi
    resolved=$WANT_PATH
    source_of="--path"
fi

# 2. Already exported in this environment.
if [ -z "$resolved" ] && is_checkout "${AGENTS_SHARED_DIR:-}"; then
    resolved=$AGENTS_SHARED_DIR
    source_of="AGENTS_SHARED_DIR in the environment"
fi

# 3. A rules symlink in the config dir points straight at the checkout. Derived
#    at runtime, so it is a fact about this machine rather than an assumption.
if [ -z "$resolved" ]; then
    for link in "$CLAUDE_DIR"/rules/*.md(N@); do
        target=${link:A}
        candidate=${target%/claude/rules/*}
        if is_checkout "$candidate"; then
            resolved=$candidate
            source_of="the rules symlink ${link:t}"
            break
        fi
    done
fi

# 4. A checkout sitting beside this repo — repo-relative, not a typed path.
if [ -z "$resolved" ]; then
    candidate="${REPO_ROOT:h}/agents-shared"
    if is_checkout "$candidate"; then
        resolved=$candidate
        source_of="a sibling of ${REPO_ROOT:t}"
    fi
fi

# 5. Ask. Nothing is assumed on this machine's behalf.
if [ -z "$resolved" ]; then
    if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
        print "could not locate an agents-shared checkout; re-run with --path DIR" >&2
        exit 1
    fi
    print "No agents-shared checkout found next to this repo or in $CLAUDE_DIR."
    read "reply?Path to the agents-shared checkout on this machine: "
    if ! is_checkout "$reply"; then
        print "not an agents-shared checkout (no hooks/require-absolute-rm.sh): ${reply:-<empty>}" >&2
        exit 1
    fi
    resolved=$reply
    source_of="your answer"
fi

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ] && [ "$source_of" != "your answer" ]; then
    print "Found agents-shared at $resolved (via $source_of)."
    read "reply?Write $SHOWN_TARGET with that path? [Y/n] "
    reply=${reply:-Y}
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        print "! Skipped. The guard hooks will refuse Bash tool calls until $SHOWN_TARGET exists." >&2
        exit 1
    fi
fi

mkdir -p "$CLAUDE_DIR"
if (( PRE_EXISTED )) && [ -f "$TARGET" ]; then
    cp "$TARGET" "$TARGET.backup-$(date +%Y%m%d-%H%M%S)"
    print "→ Backed up existing $SHOWN_TARGET"
fi

set_var AGENTS_SHARED_DIR "$resolved"

print "✓ Wrote $SHOWN_TARGET (AGENTS_SHARED_DIR=$resolved)"
ensure_statusline
print "  Verify with: $SCRIPT_DIR/verify-hook-paths.sh"
