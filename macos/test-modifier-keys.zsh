#!/bin/zsh
# Test modifier-keys.py on a made-up Karabiner config and a plist file (--domain): the real
# keyboard preferences are never read or written.
set -u -o pipefail
here=${0:A:h}
tool=$here/modifier-keys.py
tmp=${$(mktemp -d):A}   # resolved: defaults treats /var and /private/var as two files
trap 'rm -rf -- "$tmp"' EXIT
dom=$tmp/global.plist
export MODIFIER_KEYS_KARABINER=$tmp/karabiner.json
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }
# pairs KEY: the stored mapping as sorted "src>dst" hex lines.
pairs() {
    /usr/bin/python3 -I -c '
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")).get(sys.argv[2], [])
print(" ".join(sorted("%x>%x" % (p["HIDKeyboardModifierMappingSrc"], p["HIDKeyboardModifierMappingDst"]) for p in d)))' $dom $1
}

# An external keyboard with a Cmd/Opt swap, an Apple keyboard, and F4/F5 overridden as on the M2.
cat > $MODIFIER_KEYS_KARABINER <<'JSON'
{"profiles": [{"name": "Default profile", "selected": true,
  "fn_function_keys": [{"from": {"key_code": "f4"}, "to": [{"key_code": "launchpad"}]},
                       {"from": {"key_code": "f5"}, "to": [{"key_code": "f5"}]}],
  "devices": [
    {"identifiers": {"is_keyboard": true, "vendor_id": 4152, "product_id": 5666},
     "simple_modifications": [{"from": {"key_code": "left_command"}, "to": [{"key_code": "left_option"}]},
                              {"from": {"key_code": "left_option"}, "to": [{"key_code": "left_command"}]}]},
    {"identifiers": {"is_keyboard": true, "vendor_id": 1452, "product_id": 832},
     "simple_modifications": [{"from": {"key_code": "left_command"}, "to": [{"key_code": "left_option"}]}]}]}]}
JSON
ext=com.apple.keyboard.modifiermapping.4152-5666-0
apple=com.apple.keyboard.modifiermapping.1452-832-0

out=$($tool check --domain $dom); rc=$?
[[ $rc == 1 && $out == *"keyboard 4152-5666-0"* ]] && ok || bad "check on an empty domain: rc $rc, $out"
[[ $out != *"1452-832"* ]] && ok || bad "an Apple keyboard was listed: $out"

$tool import --domain $dom >/dev/null && ok || bad "import failed"
got=$(pairs $ext)
want=(
    7000000e2\>7000000e3 7000000e3\>7000000e2                # Cmd/Opt swap
    70000003a\>c00000070 70000003b\>c0000006f               # F1/F2 brightness
    70000003c\>ff0100000010                                  # F3 Mission Control
    70000003d\>70000006d                                     # F4 launchpad -> F18 (Show Apps)
    70000003f\>10000009b                                     # F6 Do Not Disturb
    700000040\>c000000b4 700000041\>c000000cd 700000042\>c000000b3   # F7-F9
    700000043\>c000000e2 700000044\>c000000ea 700000045\>c000000e9   # F10-F12
)
[[ $got == ${(j: :)${(o)want}} ]] && ok || bad "stored pairs: $got"
[[ $got != *70000003e* ]] && ok || bad "F5 was mapped though the config keeps it as F5: $got"
[[ -z $(pairs $apple) ]] && ok || bad "an Apple keyboard got a mapping"

out=$($tool check --domain $dom); rc=$?
[[ $rc == 0 ]] && ok || bad "check after import: rc $rc, $out"

# A target the table does not know is refused by name, before anything is written.
sed -i '' 's/"key_code": "launchpad"/"consumer_key_code": "no_such_key"/' $MODIFIER_KEYS_KARABINER
out=$($tool import --domain $tmp/other.plist 2>&1); rc=$?
[[ $rc != 0 && $out == *"no_such_key"*"TARGET"* && ! -e $tmp/other.plist ]] && ok || bad "unknown target: rc $rc, $out"

print "modifier-keys: $pass passed, $fail failed"
(( fail == 0 ))
