#!/bin/zsh
# Map Caps Lock to F18 with macOS's own hidutil, at every login, on a Mac without Karabiner-Elements
# (where Karabiner does it instead). F18 is then bound to Show Launchpad by the machine's keyboard
# shortcuts (symbolic-hotkeys.<label>.plist). A login agent re-applies the mapping, which hidutil
# forgets at logout.
#   capslock-to-f18.zsh           install or update the login agent and apply the mapping now
#   capslock-to-f18.zsh --check   say whether the agent is installed as this repo has it (exit 1 if not)
set -euo pipefail
LABEL=local.capslock-to-f18
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
# Caps Lock (usage 0x39) to F18 (usage 0x6D), keyboard usage page 7.
MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'

if [[ -d /Applications/Karabiner-Elements.app ]]; then
    print "Karabiner-Elements is installed: it maps Caps Lock here, so no hidutil agent"
    exit 0
fi

want=$(mktemp)
trap 'rm -f -- "$want"' EXIT
/usr/bin/python3 -I - "$want" "$LABEL" "$MAPPING" <<'PY'
import plistlib, sys
path, label, mapping = sys.argv[1:4]
plistlib.dump({"Label": label, "RunAtLoad": True,
               "ProgramArguments": ["/usr/bin/hidutil", "property", "--set", mapping]}, open(path, "wb"))
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
print "✓ installed $LABEL: Caps Lock is F18 now and at every login"
