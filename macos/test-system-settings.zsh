#!/bin/zsh
# Test system-settings.py on plist files in a sandbox (--dir, --record): the user's real
# domains are never read or written, and nothing is restarted. Each made-up machine has its own
# applied-state folder (DEV_ENV_STATE_DIR), as each real Mac has its own.
set -u -o pipefail   # run's exit code is the tool's, not sed's
here=${0:A:h}
tool=$here/system-settings.py
tmp=${$(mktemp -d):A}   # resolved: defaults treats /var and /private/var as two files
trap 'rm -rf -- "$tmp"' EXIT
rec=$tmp/record
mkdir -p $rec $tmp/c02 $tmp/c03 $tmp/c04
export DEV_ENV_KEEPS=$tmp/keeps.json
print -r -- '{"c03": {"system-settings/finder": ["ShowStatusBar"]}}' > $DEV_ENV_KEEPS
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }
# on LABEL ARGS...: run the tool as machine LABEL, on its own settings folder and applied state.
on() { local m=$1; shift; DEV_ENV_STATE_DIR=$tmp/state-$m $tool "$@" --dir $tmp/$m --label $m --record $rec | plain; }
val() { defaults read $tmp/$1/$2.plist $3 2>&1; }
recval() { /usr/bin/python3 -I -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb")).get(sys.argv[2],"<none>"))' $rec/$1.plist $2; }

# c02's settings: carried keys, an uncarried one, a home path, an address, and a Dock tile.
defaults write $tmp/c02/finder.plist ShowPathbar -bool true
defaults write $tmp/c02/finder.plist ShowStatusBar -bool true
defaults write $tmp/c02/finder.plist FXRecentFolders -string "not carried"
defaults write $tmp/c02/finder.plist NewWindowTargetPath -string "file://$HOME/Downloads/"
defaults write $tmp/c02/finder.plist FXDefaultSearchScope -string "someone@example.com"
/usr/bin/python3 -I - $tmp/c02/dock.plist <<'PY'
import plistlib, sys
t = lambda label, path: {"GUID": 1, "tile-type": "file-tile", "tile-data": {"book": b"bookmark", "file-mod-date": 5,
     "file-label": label, "file-data": {"_CFURLString": f"file://{path}", "_CFURLStringType": 15}}}
plistlib.dump({"tilesize": 40, "persistent-apps": [t("Safari", "/Applications/Safari.app/"),
    t("No Such App", "/Applications/No%20Such%20App.app/"), t("Settings", "/System/Applications/System%20Settings.app/")]},
    open(sys.argv[1], "wb"))
PY

# Export: only the allowlist, $HOME for the home folder, no address, Dock tiles reduced.
out=$(on c02 export)
[[ $out == *"FXDefaultSearchScope holds a home path or an address"* ]] && ok || bad "an address was not refused: $out"
f=$(plutil -p $rec/finder.plist)
[[ $f == *ShowPathbar* && $f != *FXRecentFolders* && $f != *example.com* ]] && ok || bad "finder record is not the allowlist: $f"
[[ $f == *'file://$HOME/Downloads/'* && $f != *$HOME* && $f == *_macos* ]] && ok || bad "home path or _macos not recorded: $f"
d=$(plutil -p $rec/dock.plist)
[[ $d == *Safari* && $d != *book* && $d != *GUID* && $d != *mod-date* ]] && ok || bad "dock tile not reduced: $d"
[[ $(on c02 export) == *"already match the repo"* ]] && ok || bad "second export wrote something"

# Import on c03: everything shared arrives, $HOME expanded, a backup kept, other keys untouched.
defaults write $tmp/c03/finder.plist FXRecentFolders -string "kept"
out=$(on c03 import)
[[ $out == *"finder: set"* && $out == *"dock: set"* ]] && ok || bad "first import: $out"
[[ $(val c03 finder NewWindowTargetPath) == "file://$HOME/Downloads/" ]] && ok || bad "\$HOME not expanded on import"
[[ $(val c03 finder FXRecentFolders) == kept ]] && ok || bad "import removed an uncarried key"
ls -d $tmp/c03/.macos-settings-backup-* >/dev/null 2>&1 && ok || bad "import kept no backup"
on c03 check >/dev/null && ok || bad "check differs after import"
[[ $(on c03 import) == *"already match the repo"* ]] && ok || bad "second import set something"

# A tile for an app c03 lacks is named, not written, not a difference.
[[ $(on c03 check) == *"tiles not on this Mac, left out: No Such App"* ]] && ok || bad "missing app tile not named"
[[ $(defaults read $tmp/c03/dock.plist persistent-apps) != *"No Such App"* ]] && ok || bad "missing app tile was written"

# Shared by default: a change exported on c03 goes to the shared record, not to a c03 file.
defaults write $tmp/c03/finder.plist ShowPathbar -bool false
out=$(on c03 export)
[[ $(recval finder ShowPathbar) == False && $(plutil -p $rec/finder.c03.plist) != *ShowPathbar* ]] && ok || bad "c03's change did not reach the shared record: $out"
# The shared Dock keeps the tile c03 lacks, in its place, after c03 exports its Dock.
defaults write $tmp/c03/dock.plist tilesize -int 50
on c03 export >/dev/null
order=$(/usr/bin/python3 -I -c 'import plistlib,sys; print(",".join(t["tile-data"]["file-label"] for t in plistlib.load(open(sys.argv[1],"rb"))["persistent-apps"]))' $rec/dock.plist)
[[ $order == "Safari,No Such App,Settings" ]] && ok || bad "shared Dock lost or moved the tile c03 lacks: $order"
[[ $(recval dock tilesize) == 50 ]] && ok || bad "c03's Dock size did not reach the shared record"

# c02 is behind now: its export is refused until it imports, and --force overrides.
defaults write $tmp/c02/finder.plist ShowSidebar -bool true
out=$(on c02 export)
[[ $out == *"changed since this Mac last imported it"* && $(recval finder ShowPathbar) == False ]] && ok || bad "a behind export was not refused: $out"
on c02 import >/dev/null
[[ $(val c02 finder ShowPathbar) == 0 ]] && ok || bad "c02 did not take c03's change"
on c02 export >/dev/null
[[ $(recval finder ShowSidebar) == True ]] && ok || bad "c02's export after importing was refused"
defaults write $tmp/c03/finder.plist ShowSidebar -bool false
out=$(on c03 export --force)
[[ $(recval finder ShowSidebar) == False ]] && ok || bad "--force did not overwrite: $out"

# A declared keep: c03's ShowStatusBar stays in finder.c03.plist; the shared value is c02's.
defaults write $tmp/c03/finder.plist ShowStatusBar -bool false
on c03 import >/dev/null   # catch up after the forced export
defaults write $tmp/c03/finder.plist ShowStatusBar -bool false
on c03 export >/dev/null
[[ $(plutil -p $rec/finder.c03.plist) == *ShowStatusBar* && $(recval finder ShowStatusBar) == True ]] && ok || bad "keep not kept apart: $(plutil -p $rec/finder.c03.plist 2>&1)"
on c03 check >/dev/null && ok || bad "c03 differs from its kept value"
on c02 import >/dev/null
[[ $(val c02 finder ShowStatusBar) == 1 ]] && ok || bad "c03's kept value reached c02"

# A key a machine has never written keeps its recorded value when that machine exports.
on c04 import >/dev/null
defaults delete $tmp/c04/finder.plist ShowSidebar
defaults write $tmp/c04/finder.plist ShowPathbar -bool true
on c04 export >/dev/null
[[ $(recval finder ShowSidebar) == False && $(recval finder ShowPathbar) == True ]] && ok || bad "c04's export dropped a key it never wrote"

# Another macOS version: named once; a same_version domain is neither applied nor exported.
on c02 import >/dev/null
defaults write $tmp/c02/spotlight.plist orderedItems -array '{enabled = 1; name = APPLICATIONS;}'
on c02 export >/dev/null
out=$(on c04 check --macos 99)
[[ $out == *"this Mac runs 99"* && $out == *"not applied, recorded on another macOS version: spotlight"* ]] && ok || bad "version note: $out"
out=$(on c04 import --macos 99)
[[ ! -f $tmp/c04/spotlight.plist ]] && ok || bad "spotlight applied across versions"
defaults write $tmp/c04/spotlight.plist orderedItems -array '{enabled = 0; name = MUSIC;}'
out=$(on c04 export --macos 99)
[[ $out == *"spotlight: recorded on macOS"*"not exported"* && $(plutil -p $rec/spotlight.plist) == *APPLICATIONS* ]] && ok || bad "spotlight exported across versions: $out"

# A key dropped from the allowlist is no longer wanted, even while the record still holds it.
/usr/bin/python3 -I -c 'import plistlib,sys; p=sys.argv[1]; r=plistlib.load(open(p,"rb")); r["NotAllowlisted"]=1; plistlib.dump(r,open(p,"wb"))' $rec/finder.plist
[[ $(on c02 check) != *NotAllowlisted* ]] && ok || bad "a key outside the allowlist is wanted"

print "system-settings: $pass passed, $fail failed"
(( fail == 0 ))
