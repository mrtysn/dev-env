#!/bin/zsh
# Make ~/"MY Applications" a symlink to ~/Applications. Finder's sidebar labels an item with its file
# name, so dragging this link into the sidebar shows "MY Applications" next to the system Applications,
# while the path bar still reads ~/Applications. The sidebar entry itself is per machine and cannot be
# scripted on this macOS (LSSharedFileList returns nothing, sfltool has no add), so it stays one drag.
#   my-applications-link.zsh           create the link (and ~/Applications if missing)
#   my-applications-link.zsh --check   exit 1 if the link is not as this repo has it
set -euo pipefail
LINK="$HOME/MY Applications"
TARGET="$HOME/Applications"

if [[ -L "$LINK" && "$(readlink "$LINK")" == "$TARGET" ]]; then
    print "✓ $LINK already points at $TARGET"
    exit 0
fi
if [[ "${1:-}" == --check ]]; then
    print "✗ $LINK is not a link to $TARGET"
    exit 1
fi
if [[ -e "$LINK" || -L "$LINK" ]]; then
    print "✗ $LINK exists and is not a link to $TARGET; move it away and re-run" >&2
    exit 1
fi
mkdir -p "$TARGET"
ln -s "$TARGET" "$LINK"
print "✓ linked $LINK -> $TARGET"
print "  Once per machine: drag \"$LINK\" into Finder's sidebar (Favorites) to show it as MY Applications."
