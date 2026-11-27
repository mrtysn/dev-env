#!/bin/zsh
# Make ~/Downloads/ff-sidebery a symlink to ~/backups/ff-sidebery, so Sidebery's snapshot auto-export
# lands in ~/backups. Sidebery saves through Firefox's downloads API, which takes only a path inside
# Firefox's download folder (no absolute path, no ../), so its "auto-export path" setting
# ("ff-sidebery/snapshot-%Y.%M.%D-%h.%m.%s") cannot name ~/backups itself; the link carries it there.
#   sidebery-backup-link.zsh           create the link; an existing real folder is moved to ~/backups first
#   sidebery-backup-link.zsh --check   exit 1 if the link is not as this repo has it
set -euo pipefail
LINK="$HOME/Downloads/ff-sidebery"
TARGET="$HOME/backups/ff-sidebery"

if [[ -L "$LINK" && "$(readlink "$LINK")" == "$TARGET" ]]; then
    print "✓ $LINK already points at $TARGET"
    exit 0
fi
if [[ "${1:-}" == --check ]]; then
    print "✗ $LINK is not a link to $TARGET"
    exit 1
fi
if [[ -L "$LINK" ]]; then
    print "✗ $LINK is a link to $(readlink "$LINK"), not $TARGET; remove it and re-run" >&2
    exit 1
fi
mkdir -p "$HOME/backups"
if [[ -d "$LINK" ]]; then
    if [[ -e "$TARGET" ]]; then
        print "✗ both $LINK and $TARGET exist as folders; merge them into $TARGET, remove $LINK, and re-run" >&2
        exit 1
    fi
    mv "$LINK" "$TARGET"
    print "✓ moved $LINK to $TARGET"
elif [[ -e "$LINK" ]]; then
    print "✗ $LINK exists and is not a folder; move it away and re-run" >&2
    exit 1
fi
mkdir -p "$TARGET" "$HOME/Downloads"
ln -s "$TARGET" "$LINK"
print "✓ linked $LINK -> $TARGET"
print "  Sidebery's auto-export path must start with ff-sidebery/ (Settings > Snapshots)."
