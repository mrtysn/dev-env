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

# Caps Lock set to No Action on the built-in keyboard (0-0-0) is reported, and import takes it out.
caps=com.apple.keyboard.modifiermapping.0-0-0
defaults write $dom $caps -array '<dict><key>HIDKeyboardModifierMappingDst</key><integer>30064771072</integer><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer></dict>'
out=$($tool check --domain $dom); rc=$?
[[ $rc == 1 && $out == *"keyboard 0-0-0 has Caps Lock"* ]] && ok || bad "Caps Lock set to none not reported: rc $rc, $out"
$tool import --domain $dom >/dev/null && ok || bad "import with Caps Lock set to none failed"
[[ -z $(pairs $caps) ]] && ok || bad "Caps Lock pair left in place: $(pairs $caps)"
# Caps Lock left as Caps Lock, or already F18, is not touched.
defaults write $dom $caps -array '<dict><key>HIDKeyboardModifierMappingDst</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer></dict>'
$tool check --domain $dom >/dev/null && ok || bad "Caps Lock as Caps Lock was reported"

# The built-in keyboard: its Fn layer's F4 (Spotlight) and F5 (Dictation) become F18 and F5.
export MODIFIER_KEYS_IOREG=$tmp/ioreg.txt
cat > $MODIFIER_KEYS_IOREG <<'IOREG'
+-o AppleHIDKeyboardEventDriverV2  <class AppleHIDKeyboardEventDriverV2, id 0x1, registered>
  |   "Built-In" = Yes
  |   "VendorID" = 0
  |   "ProductID" = 0
  |   "FnFunctionUsageMap" = "0x0007003a,0x00ff0005,0x0007003d,0x000c0221,0x0007003e,0x000c00cf,0x0007003f,0x0001009b"
IOREG
out=$($tool builtin)
[[ $out == '{"matching": {"VendorID": 0, "ProductID": 0, "PrimaryUsagePage": 1, "PrimaryUsage": 6}, "pairs": [[51539608097, 30064771181], [51539607759, 30064771134]]}' ]] \
    && ok || bad "built-in pairs: $out"
# No built-in keyboard (a desktop Mac): nothing.
print -r -- '+-o AppleHIDKeyboardEventDriverV2  <class X>
  |   "Built-In" = No' > $MODIFIER_KEYS_IOREG
[[ $($tool builtin) == '{}' ]] && ok || bad "a Mac without a built-in keyboard got pairs"
unset MODIFIER_KEYS_IOREG

# A target the table does not know is refused by name, before anything is written.
sed -i '' 's/"key_code": "launchpad"/"consumer_key_code": "no_such_key"/' $MODIFIER_KEYS_KARABINER
out=$($tool import --domain $tmp/other.plist 2>&1); rc=$?
[[ $rc != 0 && $out == *"no_such_key"*"TARGET"* && ! -e $tmp/other.plist ]] && ok || bad "unknown target: rc $rc, $out"

print "modifier-keys: $pass passed, $fail failed"
(( fail == 0 ))
