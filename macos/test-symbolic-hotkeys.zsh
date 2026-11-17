#!/bin/zsh
# Import a record into a copy of this Mac's shortcut settings twice: the first run makes the
# recorded entries match (one switched off, one re-keyed), the second changes nothing. The live
# settings are only read.
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
# The copy has 30 on and 31 on macOS's keys; the record has 30 off and 31 on the swapped keys.
/usr/bin/python3 -I - "$domain" "$tmp/record.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
d.setdefault("AppleSymbolicHotKeys", {})["30"] = {"enabled": True, "value": {"parameters": [52, 21, 1441792], "type": "standard"}}
d["AppleSymbolicHotKeys"]["31"] = {"enabled": True, "value": {"parameters": [52, 21, 1441792], "type": "standard"}}
plistlib.dump(d, open(sys.argv[1], "wb"))
plistlib.dump({"30": {"enabled": False, "value": {"parameters": [52, 21, 1441792], "type": "standard"}},
               "31": {"enabled": True, "value": {"parameters": [52, 21, 1179648], "type": "standard"}}},
              open(sys.argv[2], "wb"))
PY
export SYMBOLIC_HOTKEYS_RECORD=$tmp/record.plist

$tool check --domain $domain >/dev/null && bad "check passed before import" || ok
out=$($tool import --domain $domain); [[ $out == *"set 2 shortcut entries"* ]] && ok || bad "first import: $out"
$tool check --domain $domain >/dev/null && ok || bad "check failed after import"
out=$($tool import --domain $domain); [[ $out == *"already match"* ]] && ok || bad "second import changed something: $out"
others=$(/usr/bin/python3 -I -c 'import plistlib,sys; a=plistlib.load(open(sys.argv[1],"rb"))["AppleSymbolicHotKeys"]; print(len(a))' $domain)
(( others > 2 )) && ok || bad "other entries were lost ($others left)"

# Per machine: the record belongs to c02; c03's overlay turns 160 on, on F18.
/usr/bin/python3 -I - "$tmp/record.plist" "$tmp/symbolic-hotkeys.c03.plist" <<'PY'
import plistlib, sys
r = plistlib.load(open(sys.argv[1], "rb"))
r["_machine"] = "c02"
r["160"] = {"enabled": False, "value": {"parameters": [65535, 65535, 0], "type": "standard"}}
plistlib.dump(r, open(sys.argv[1], "wb"))
plistlib.dump({"160": {"enabled": True, "value": {"parameters": [65535, 79, 8388608], "type": "standard"}}},
              open(sys.argv[2], "wb"))
PY
out=$($tool import --domain $domain --label c03); [[ $out == *"Show Launchpad"*"(on)"* ]] && ok || bad "c03 import did not turn Show Launchpad on: $out"
$tool check --domain $domain --label c03 >/dev/null && ok || bad "c03 check differs after import"
$tool check --domain $domain --label c02 >/dev/null && bad "c02 check passed with 160 on" || ok
# Export on c03 writes only where it differs from c02's record, and leaves the record alone.
before=$(shasum "$tmp/record.plist")
rm -f -- "$tmp/symbolic-hotkeys.c03.plist"
$tool export --domain $domain --label c03 >/dev/null
[[ "$(shasum "$tmp/record.plist")" == "$before" ]] && ok || bad "c03 export changed the shared record"
n=$(/usr/bin/python3 -I -c 'import plistlib,sys; print(len(plistlib.load(open(sys.argv[1],"rb"))))' "$tmp/symbolic-hotkeys.c03.plist")
(( n >= 1 )) && ok || bad "c03 export wrote no overlay"

print "symbolic-hotkeys: $pass passed, $fail failed"
(( fail == 0 ))
