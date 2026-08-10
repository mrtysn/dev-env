#!/bin/zsh
# DESC: Write the machine-local paths.local.sh that Claude's guard hooks read
#
# The PreToolUse guards in settings.json exit 2 — refusing the tool call — when
# they cannot resolve AGENTS_SHARED_DIR. That is deliberate: a safety hook which
# silently is not there is worse than one that fails loudly. The consequence is
# that a machine which imported settings.json without this file refuses every
# Bash tool call, so import.sh writes it as part of the same step.
#
# The path is never guessed from a hardcoded layout. It is derived, in order,
# from an explicit --path, an exported AGENTS_SHARED_DIR, an existing rules
# symlink in the config dir, or a sibling checkout beside this repo — and any
# candidate must actually contain the hooks before it is accepted.

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}

# CLAUDE_DIR, not CLAUDE_CONFIG_DIR: the latter is session-contextual (the
# claudep alias flips it), matching how export.sh and import.sh resolve this.
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

ASSUME_YES=0
FORCE=0
WANT_PATH=""

usage() {
    cat <<'USAGE'
usage: write-paths-local.sh [--path DIR] [--yes] [--force]

Writes ${CLAUDE_DIR:-$HOME/.claude}/paths.local.sh with AGENTS_SHARED_DIR set to
this machine's agents-shared checkout, which the guard hooks in settings.json
source at run time.

  --path DIR   use this checkout instead of detecting one
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
        -y|--yes) ASSUME_YES=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) print "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

TARGET="$CLAUDE_DIR/paths.local.sh"
SHOWN_TARGET="${TARGET/#$HOME/~}"

# A candidate counts only if it really is an agents-shared checkout.
is_checkout() {
    [ -n "${1:-}" ] && [ -x "$1/hooks/require-absolute-rm.sh" ]
}

# Already configured and working — nothing to do.
if [ "$FORCE" -eq 0 ] && [ -r "$TARGET" ]; then
    existing=$(AGENTS_SHARED_DIR=""; . "$TARGET" >/dev/null 2>&1; print -r -- "${AGENTS_SHARED_DIR:-}")
    if is_checkout "$existing"; then
        print "✓ $SHOWN_TARGET already resolves to $existing"
        exit 0
    fi
    print "! $SHOWN_TARGET exists but does not resolve to a checkout; rewriting"
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
if [ -f "$TARGET" ]; then
    cp "$TARGET" "$TARGET.backup-$(date +%Y%m%d-%H%M%S)"
    print "→ Backed up existing $SHOWN_TARGET"
fi

cat > "$TARGET" <<EOF
# Machine-local paths for hook commands in settings.json. Not committed:
# ~/.claude is not a repo, and dev-env/export.sh reads only settings.json.
# Written by dev-env/agents/claude/write-paths-local.sh; the committed shape is
# dev-env/agents/claude/paths.local.sh.example.

# Checkout of the agents-shared repo, which holds hooks/ and claude/rules/.
AGENTS_SHARED_DIR="$resolved"
EOF

print "✓ Wrote $SHOWN_TARGET (AGENTS_SHARED_DIR=$resolved)"
print "  Verify with: $SCRIPT_DIR/verify-hook-paths.sh"
