#!/bin/zsh
# Test system-settings.py on plist files in a sandbox (--dir, --record): the user's real
# domains are never read or written, and nothing is restarted.
set -u -o pipefail   # run's exit code is the tool's, not sed's
here=${0:A:h}
tool=$here/system-settings.py
tmp=${$(mktemp -d):A}   # resolved: defaults treats /var and /private/var as two files
trap 'rm -rf -- "$tmp"' EXIT
live=$tmp/live other=$tmp/other rec=$tmp/record
mkdir -p $live $other $rec
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }
run() { $tool "$@" --record $rec | plain; }

# A Finder domain with carried keys, an uncarried one, a home path and an address.
defaults write $live/finder.plist ShowPathbar -bool true
defaults write $live/finder.plist FXRecentFolders -string "not carried"
defaults write $live/finder.plist NewWindowTargetPath -string "file://$HOME/Downloads/"
defaults write $live/finder.plist FXDefaultSearchScope -string "someone@example.com"
# A Dock tile with a per-machine bookmark and GUID.
/usr/bin/python3 -I - $live/dock.plist <<'PY'
import plistlib, sys
plistlib.dump({"tilesize": 40, "persistent-apps": [{"GUID": 123, "tile-type": "file-tile", "tile-data": {
    "book": b"bookmark", "file-mod-date": 5, "file-label": "Safari", "bundle-identifier": "com.apple.Safari",
    "file-data": {"_CFURLString": "file:///Applications/Safari.app/", "_CFURLStringType": 15}}}]},
    open(sys.argv[1], "wb"))
PY

out=$(run export --dir $live --label c02)
[[ $out == *"FXDefaultSearchScope holds a home path or an address"* ]] && ok || bad "an address was not refused: $out"
f=$(plutil -p $rec/finder.plist)
[[ $f == *ShowPathbar* && $f != *FXRecentFolders* && $f != *example.com* ]] && ok || bad "finder record is not the allowlist: $f"
[[ $f == *'file://$HOME/Downloads/'* && $f != *$HOME* ]] && ok || bad "home path not recorded as \$HOME: $f"
d=$(plutil -p $rec/dock.plist)
[[ $d == *com.apple.Safari* && $d != *book* && $d != *GUID* && $d != *mod-date* ]] && ok || bad "dock tile not reduced: $d"
out=$(run export --dir $live --label c02)
[[ $out == *"already match the repo"* ]] && ok || bad "second export wrote something: $out"

# Import into an empty machine, then again: the second run sets nothing.
out=$(run import --dir $other --label c02)
[[ $out == *"finder: set"* && $out == *"dock: set"* ]] && ok || bad "first import: $out"
[[ $(defaults read $other/finder.plist NewWindowTargetPath) == "file://$HOME/Downloads/" ]] && ok || bad "\$HOME not expanded on import"
ls -d $other/.macos-settings-backup-* >/dev/null 2>&1 && ok || bad "import kept no backup"
run check --dir $other --label c02 >/dev/null && ok || bad "check differs after import"
out=$(run import --dir $other --label c02)
[[ $out == *"already match the repo"* ]] && ok || bad "second import set something: $out"

# Another machine differs in one key: its export writes only that key, in its overlay.
defaults write $other/finder.plist ShowPathbar -bool false
out=$(run check --dir $other --label c03)
[[ $out == *"differs here: finder ShowPathbar"* ]] && ok || bad "check missed a difference: $out"
run export --dir $other --label c03 >/dev/null
o=$(plutil -p $rec/finder.c03.plist 2>&1)
[[ $o == *ShowPathbar* && $o != *NewWindowTargetPath* ]] && ok || bad "c03 overlay is not just the difference: $o"
[[ $(plutil -p $rec/finder.plist) == *'"ShowPathbar" => 1'* ]] && ok || bad "c03 export changed the shared record"
run check --dir $other --label c03 >/dev/null && ok || bad "c03 differs from its own overlay"
run check --dir $other --label c02 >/dev/null && bad "c02 should differ from c03's Finder" || ok

print "system-settings: $pass passed, $fail failed"
(( fail == 0 ))
