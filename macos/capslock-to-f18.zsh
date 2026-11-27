#!/bin/zsh
# Map Caps Lock to F18 with macOS's own hidutil, at every login, on a Mac without Karabiner-Elements
# (where Karabiner does it instead). F18 is bound to Show Launchpad (Show Apps on macOS 27) by the
# shared keyboard shortcuts (symbolic-hotkeys.plist, entry 160). On the built-in keyboard the same
# agent also applies the config's F-key overrides (F4 to F18, F5 kept as F5), which modifier-keys.py
# builtin computes from the keyboard's Fn layer. A login agent re-applies both, which hidutil forgets
# at logout.
#   capslock-to-f18.zsh           install or update the login agent and apply the mapping now
#   capslock-to-f18.zsh --check   say whether the agent is installed as this repo has it (exit 1 if not)
set -euo pipefail
LABEL=local.capslock-to-f18
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -d /Applications/Karabiner-Elements.app ]]; then
    print "Karabiner-Elements is installed: it maps Caps Lock here, so no hidutil agent"
    exit 0
fi

builtin=$("${0:A:h}/modifier-keys.py" builtin)
want=$(mktemp)
trap 'rm -f -- "$want"' EXIT
/usr/bin/python3 -I - "$want" "$LABEL" "$builtin" <<'PY'
import json, plistlib, shlex, sys
path, label, builtin = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
# Caps Lock (usage 0x39) to F18 (usage 0x6D), keyboard usage page 7, on every keyboard.
caps = [(0x700000039, 0x70000006D)]


def mapping(pairs):
    # hidutil's own syntax: hex usages, as its man page writes them.
    return '{"UserKeyMapping":[%s]}' % ",".join(
        '{"HIDKeyboardModifierMappingSrc":0x%X,"HIDKeyboardModifierMappingDst":0x%X}' % (s, d) for s, d in pairs)


hidutil = ["/usr/bin/hidutil", "property", "--set", mapping(caps)]
if builtin:
    # UserKeyMapping is one list per keyboard, so the built-in one gets Caps Lock again with its F keys.
    builtin_cmd = ["/usr/bin/hidutil", "property", "--matching", json.dumps(builtin["matching"], separators=(",", ":")),
                   "--set", mapping(caps + [tuple(p) for p in builtin["pairs"]])]
    args = ["/bin/sh", "-c", " && ".join(shlex.join(c) for c in (hidutil, builtin_cmd))]
else:
    args = hidutil
plistlib.dump({"Label": label, "RunAtLoad": True, "ProgramArguments": args}, open(path, "wb"))
PY

if [[ -f "$AGENT" ]] && /usr/bin/python3 -I -c 'import plistlib,sys; a,b=(plistlib.load(open(p,"rb")) for p in sys.argv[1:]); sys.exit(a!=b)' "$AGENT" "$want"; then
    print "✓ $LABEL already installed"
    exit 0
fi
if [[ "${1:-}" == --check ]]; then
    print "✗ $LABEL is not installed as dev-env has it"
    exit 1
fi
mkdir -p "${AGENT:h}"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
cp "$want" "$AGENT"
launchctl bootstrap "gui/$(id -u)" "$AGENT"
if [[ -n "$builtin" && "$builtin" != "{}" ]]; then
    print "✓ installed $LABEL: Caps Lock is F18, and the built-in keyboard has the config's F-key overrides, now and at every login"
else
    print "✓ installed $LABEL: Caps Lock is F18 now and at every login"
fi
