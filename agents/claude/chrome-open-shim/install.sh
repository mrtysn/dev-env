#!/bin/zsh
# DESC: Link the open shim to ~/.local/share/claude-open-shim, where the claude() wrapper looks
#
# Run it only on a machine that wants per-account Chrome profiles. Then add
# CLAUDE_CHROME_PROFILE="<Chrome profile folder>" to each config folder's paths.local.sh.
set -euo pipefail
dest="$HOME/.local/share/claude-open-shim"
mkdir -p "$dest"
ln -sfn "${0:A:h}/open" "$dest/open"
print -r -- "linked $dest/open"
