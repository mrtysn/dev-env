#!/bin/zsh
# Import the repo's app settings into an empty home twice, then change one key and import
# again: the second run must load nothing, the third only that key. Needs the apps installed
# (import skips one that is not); the real home is never written.
set -u -o pipefail   # a piped run's exit code is the tool's, not sed's
here=${0:A:h}
tool=$here/app-settings.py
home=${$(mktemp -d):A}   # resolved: defaults treats /var and /private/var as two files
trap 'rm -rf -- "$home"' EXIT
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# Per-machine overlays, on a made-up app with its own record folder (--repo, --apps): c02 owns
# the shared copies, c03 records only where it differs, and a fresh c03 gets both laid together.
sb=$home/overlay rec=$sb/record
mkdir -p $sb/Fake.app $rec $sb/c02 $sb/c03 $sb/c03-new
print -r -- '{"owner": "c02", "apps": [
  {"name": "fake", "app": "'$sb/Fake.app'", "file": "Library/Preferences/test.fake.plist", "keys": "size|theme"},
  {"name": "fake-files", "app": "'$sb/Fake.app'", "dir": "Fake/User",
   "files": ["Prefs.sublime-settings", "Keys.sublime-keymap"]}]}' > $sb/apps.json
ov() { $tool "$@" --repo $rec --apps $sb/apps.json --ignore-running | plain; }
seed() {  # $1 home, $2 size, $3 font_size, $4 keymap key
    defaults write "$1/Library/Preferences/test.fake.plist" size -int $2
    defaults write "$1/Library/Preferences/test.fake.plist" theme -string dark
    mkdir -p $1/Fake/User
    print -r -- $'{\n\t// font\n\t"font_size": '$3$', // here\n\t"theme": "x",\n}' > $1/Fake/User/Prefs.sublime-settings
    print -r -- '[{"keys": ["'$4'"], "command": "noop"}]' > $1/Fake/User/Keys.sublime-keymap
}
seed $sb/c02 10 26 super+k
ov export --home $sb/c02 --label c02 >/dev/null
[[ -f $rec/fake.plist && -f $rec/fake-files/Prefs.sublime-settings && ! -e $rec/fake.c02.plist ]] && ok || bad "owner did not write the shared copies: $(ls -R $rec)"
ov import --home $sb/c03 --label c03 >/dev/null
ov check --home $sb/c03 --label c03 >/dev/null && ok || bad "c03 differs after importing the shared copies"
seed $sb/c03 12 21 super+j
out=$(ov export --home $sb/c03 --label c03)
[[ $(plutil -p $rec/fake.c03.plist) == *size* && $(plutil -p $rec/fake.c03.plist) != *theme* ]] && ok || bad "plist overlay is not just the difference: $(plutil -p $rec/fake.c03.plist)"
[[ $(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])))' $rec/fake-files/Prefs.c03.sublime-settings) == "{'font_size': 21}" ]] && ok || bad "settings overlay is not just font_size: $(cat $rec/fake-files/Prefs.c03.sublime-settings)"
[[ $(cat $rec/fake-files/Keys.c03.sublime-keymap) == *super+j* ]] && ok || bad "keymap overlay is not the whole file"
[[ $(plutil -p $rec/fake.plist) == *'"size" => 10'* && $(cat $rec/fake-files/Prefs.sublime-settings) == *26* ]] && ok || bad "c03 export changed the shared copies"
ov check --home $sb/c03 --label c03 >/dev/null && ok || bad "c03 differs from its own overlays"
ov check --home $sb/c03 --label c02 >/dev/null && bad "c02 should differ from c03" || ok
[[ $(ov export --home $sb/c03 --label c03) == *"already match"* ]] && ok || bad "second c03 export wrote something"
ov import --home $sb/c03-new --label c03 >/dev/null
[[ $(defaults read $sb/c03-new/Library/Preferences/test.fake.plist size) == 12 ]] && ok || bad "fresh c03 did not get its plist overlay"
p=$(/usr/bin/python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["font_size"], d["theme"])' $sb/c03-new/Fake/User/Prefs.sublime-settings)
[[ $p == "21 x" ]] && ok || bad "fresh c03 settings are not shared + overlay: $p"
ov check --home $sb/c03-new --label c03 >/dev/null && ok || bad "fresh c03 differs after import"
seed $sb/c03 10 26 super+k
ov export --home $sb/c03 --label c03 >/dev/null
[[ ! -e $rec/fake.c03.plist && ! -e $rec/fake-files/Prefs.c03.sublime-settings && ! -e $rec/fake-files/Keys.c03.sublime-keymap ]] && ok || bad "overlays not removed once c03 matches: $(ls $rec $rec/fake-files)"

installed=$(/usr/bin/python3 -I -c 'import json,os,sys; print(sum(os.path.isdir(a["app"]) for a in json.load(open(sys.argv[1]))["apps"]))' $here/apps.json)
(( installed > 0 )) || { print "app-settings: $pass passed, $fail failed (no carried app installed: real apps not tested)"; exit $(( fail > 0 )); }

out=$($tool import --home $home --ignore-running | plain)
[[ $out == *"✗"* ]] && bad "first import failed: $out" || ok
$tool check --home $home >/dev/null && ok || bad "after the first import, check still differs"

out=$($tool import --home $home --ignore-running | plain)
n=$(print -r -- $out | grep -c 'already match')
(( n == installed )) && ok || bad "second import loaded something ($n of $installed already matched)"

if [[ -f $here/mos.plist && -d /Applications/Mos.app ]]; then
    defaults write "$home/Library/Preferences/com.caldis.Mos.plist" step -float 99
    out=$($tool import --home $home --ignore-running | plain)
    [[ $out == *"mos: loaded 1 settings"* ]] && ok || bad "a changed key was not the only one loaded: $out"
fi

out=$($tool check --home $home)
[[ $? == 0 ]] && ok || bad "final check differs: $out"

print "app-settings: $pass passed, $fail failed"
(( fail == 0 ))
