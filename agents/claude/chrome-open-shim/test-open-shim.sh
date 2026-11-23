#!/bin/zsh
# DESC: Self-check for the open shim: profile added only to Claude-in-Chrome launches
set -euo pipefail
SHIM=${0:A:h}/open
T=$(mktemp -d "${TMPDIR:-/tmp}/open-shim-test.XXXXXX")
trap 'rm -rf -- "$T"' EXIT
pass=0; failed=0
expect() { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else failed=$((failed+1)); print -r -- "FAIL: $1: expected <$3>, got <$2>" >&2; fi }
printf '#!/bin/zsh\nprint -r -- "$*"\n' > "$T/real"; chmod +x "$T/real"
export CLAUDE_OPEN_REAL="$T/real"
run() { "$SHIM" "$@"; }

U=https://clau.de/chrome/tab/1
unset CLAUDE_CHROME_PROFILE
expect "no profile set" "$(CLAUDE_CONFIG_DIR=$T/none run -a 'Google Chrome' $U)" "-a Google Chrome $U"
expect "env profile" "$(CLAUDE_CHROME_PROFILE='Profile 2' run -a 'Google Chrome' $U)" "-a Google Chrome $U --args --profile-directory=Profile 2"
mkdir -p "$T/cfg"; print 'CLAUDE_CHROME_PROFILE="Profile 1"' > "$T/cfg/paths.local.sh"
expect "paths.local.sh profile" "$(CLAUDE_CONFIG_DIR=$T/cfg run -a 'Google Chrome' $U)" "-a Google Chrome $U --args --profile-directory=Profile 1"
expect "other url untouched" "$(CLAUDE_CONFIG_DIR=$T/cfg run -a 'Google Chrome' https://example.com)" "-a Google Chrome https://example.com"
expect "other app untouched" "$(CLAUDE_CONFIG_DIR=$T/cfg run -a Safari $U)" "-a Safari $U"
expect "existing --args untouched" "$(CLAUDE_CONFIG_DIR=$T/cfg run -a 'Google Chrome' $U --args --x)" "-a Google Chrome $U --args --x"

print -r -- "$pass passed, $failed failed"
(( failed == 0 ))
