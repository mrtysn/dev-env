#!/bin/zsh
# Import the repo's app settings into an empty home twice, then change one key and import
# again: the second run must load nothing, the third only that key. Needs the apps installed
# (import skips one that is not); the real home is never written.
set -u
here=${0:A:h}
tool=$here/app-settings.py
home=${$(mktemp -d):A}   # resolved: defaults treats /var and /private/var as two files
trap 'rm -rf -- "$home"' EXIT
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }

installed=$(/usr/bin/python3 -I -c 'import json,os,sys; print(sum(os.path.isdir(a["app"]) for a in json.load(open(sys.argv[1]))["apps"]))' $here/apps.json)
(( installed > 0 )) || { print "no carried app is installed here: nothing to test"; exit 0; }

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
