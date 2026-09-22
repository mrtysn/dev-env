# Single source of truth for the machine → label mapping.
#   c01 = Office     c02 = Home
# Sourced by export.sh and import.sh; the label names every per-machine file:
# .zshrc.<label>, Brewfile.<label>, tmux/<label>.conf, asdf/tool-versions.<label>.
#
# LocalHostName, not `hostname -s`: the latter can resolve to a DHCP name
# (e.g. "192") on some LANs and misroute per-machine files.
#
# Known exception: the ~/.zshrc loader (shipped by import.sh, exported back as
# .zshrc.loader) carries its own copy of this mapping — shell startup must not
# depend on this repo, whose path differs per machine.
# One case per machine: add a LocalHostName here to bind it to a label.
#
# "Unknown" is scutil's own not-set sentinel, but it's also what a sandboxed
# shell prints when it can't reach configd — a silently wrong answer, not an
# error. Never treat it as a real unmapped machine: stop instead of exporting
# partial data under a bogus label.
RESOLVED_HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
if [[ "$RESOLVED_HOST" == "Unknown" ]]; then
    echo "machine-label.sh: scutil returned \"Unknown\" for LocalHostName." >&2
    echo "This is either a genuinely unset hostname, or a sandboxed shell unable to reach" >&2
    echo "configd (known with agent-request-limiter's Seatbelt sandbox). Refusing to guess." >&2
    echo "Run 'scutil --get LocalHostName' in a real (non-agent) terminal to check, then" >&2
    echo "either fix the hostname or re-run this outside a restrictive sandbox." >&2
    exit 1
fi
case "$RESOLVED_HOST" in
    mrtysn-mbp-m2max)  MACHINE_LABEL="c02"; MACHINE_NAME="C02 (Home)" ;;
    *)                 MACHINE_LABEL="";   MACHINE_NAME="unknown" ;;
esac
