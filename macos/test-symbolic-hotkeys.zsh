#!/bin/zsh
# Import a record into a copy of this Mac's shortcut settings twice: the first run switches the
# recorded shortcuts off, the second changes nothing. The live settings are only read.
set -u
here=${0:A:h}
tool=$here/symbolic-hotkeys.py
tmp=${$(mktemp -d):A}
trap 'rm -rf -- "$tmp"' EXIT
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }

domain=$tmp/hotkeys.plist
defaults export com.apple.symbolichotkeys - > $domain
# The copy has entry 30 on; the record says 30 and a made-up 9999 are off.
/usr/bin/python3 -I - "$domain" "$tmp/record.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
d.setdefault("AppleSymbolicHotKeys", {})["30"] = {"enabled": True, "value": {"parameters": [52, 21, 1441792], "type": "standard"}}
plistlib.dump(d, open(sys.argv[1], "wb"))
plistlib.dump({"30": {"enabled": False, "value": {"parameters": [52, 21, 1441792], "type": "standard"}},
               "9999": {"enabled": False}}, open(sys.argv[2], "wb"))
PY
export SYMBOLIC_HOTKEYS_RECORD=$tmp/record.plist

$tool check --domain $domain >/dev/null && bad "check passed before import" || ok
out=$($tool import --domain $domain); [[ $out == *"switched off 2"* ]] && ok || bad "first import: $out"
$tool check --domain $domain >/dev/null && ok || bad "check failed after import"
out=$($tool import --domain $domain); [[ $out == *"already off"* ]] && ok || bad "second import changed something: $out"
others=$(/usr/bin/python3 -I -c 'import plistlib,sys; a=plistlib.load(open(sys.argv[1],"rb"))["AppleSymbolicHotKeys"]; print(len(a))' $domain)
(( others > 2 )) && ok || bad "other entries were lost ($others left)"

print "symbolic-hotkeys: $pass passed, $fail failed"
(( fail == 0 ))
