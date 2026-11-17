#!/usr/bin/python3 -I
"""On a Mac without Karabiner-Elements, give each keyboard the modifier-key swaps that dev-env's
Karabiner config (karabiner/karabiner.json) makes for it, through macOS's own per-keyboard setting
(System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys).

    modifier-keys.py check    list the keyboards whose macOS mapping differs from Karabiner's (exit 1 if any)
    modifier-keys.py import   write those mappings

macOS keeps one mapping per keyboard, keyed by vendor and product id, in the current host's global
preferences (com.apple.keyboard.modifiermapping.<vendor>-<product>-0); it applies to a keyboard
when it next connects, or at the next login. Only Karabiner's modifier-to-modifier rules for a
named device are carried; Caps Lock goes through capslock-to-f18.zsh instead.
Option: --domain PATH reads and writes a plist file instead of the current host's global domain (tests).
"""
import json, os, plistlib, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KARABINER = os.environ.get("MODIFIER_KEYS_KARABINER") or os.path.join(os.path.dirname(HERE), "karabiner", "karabiner.json")
# HID keyboard usages (page 7) of the modifier keys, as macOS's mapping stores them.
USAGE = {"left_control": 0x7000000E0, "left_shift": 0x7000000E1, "left_option": 0x7000000E2,
         "left_command": 0x7000000E3, "right_control": 0x7000000E4, "right_shift": 0x7000000E5,
         "right_option": 0x7000000E6, "right_command": 0x7000000E7}


def wanted():
    """{preference key: [mapping dicts]} from Karabiner's per-device modifier swaps."""
    with open(KARABINER) as f:
        config = json.load(f)
    out = {}
    for profile in config.get("profiles", []):
        if not profile.get("selected", True) and len(config.get("profiles", [])) > 1:
            continue
        for device in profile.get("devices", []):
            ids = device.get("identifiers", {})
            vendor, product = ids.get("vendor_id"), ids.get("product_id")
            if not ids.get("is_keyboard") or vendor is None or product is None:
                continue
            pairs = []
            for rule in device.get("simple_modifications", []):
                src = rule.get("from", {}).get("key_code")
                dst = [t.get("key_code") for t in rule.get("to", [])]
                if src in USAGE and len(dst) == 1 and dst[0] in USAGE:
                    pairs.append({"HIDKeyboardModifierMappingSrc": USAGE[src],
                                  "HIDKeyboardModifierMappingDst": USAGE[dst[0]]})
            if pairs:
                out[f"com.apple.keyboard.modifiermapping.{vendor}-{product}-0"] = pairs
    return out


def live(domain):
    args = ["defaults", "export", domain, "-"] if domain else ["defaults", "-currentHost", "export", "-g", "-"]
    out = subprocess.run(args, capture_output=True)
    return plistlib.loads(out.stdout) if out.returncode == 0 and out.stdout else {}


def as_set(pairs):
    return sorted((p["HIDKeyboardModifierMappingSrc"], p["HIDKeyboardModifierMappingDst"]) for p in pairs or [])


def differing(domain):
    have = live(domain)
    return {k: v for k, v in wanted().items() if as_set(have.get(k)) != as_set(v)}


def check(domain):
    todo = differing(domain)
    for k in todo:
        print(f"differs here: modifier keys of keyboard {k.rsplit('.', 1)[1]}")
    if not todo:
        print("✓ modifier keys match Karabiner's config")
    return 1 if todo else 0


def import_(domain):
    todo = differing(domain)
    if not todo:
        print("✓ modifier keys already match Karabiner's config")
        return 0
    for key, pairs in todo.items():
        # XML fragments keep the values integers; the {a=1;} form would store them as strings.
        items = ["<dict><key>HIDKeyboardModifierMappingDst</key><integer>%d</integer>"
                 "<key>HIDKeyboardModifierMappingSrc</key><integer>%d</integer></dict>"
                 % (p["HIDKeyboardModifierMappingDst"], p["HIDKeyboardModifierMappingSrc"]) for p in pairs]
        args = (["defaults", "write", domain, key, "-array", *items] if domain
                else ["defaults", "-currentHost", "write", "-g", key, "-array", *items])
        if subprocess.run(args).returncode != 0:
            print(f"✗ could not write {key}")
            return 1
        print(f"✓ set the modifier keys of keyboard {key.rsplit('.', 1)[1]} (applies when it reconnects or at the next login)")
    return 1 if differing(domain) else 0


def main(argv):
    if not argv or argv[0] not in ("check", "import"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    domain = os.path.realpath(argv[argv.index("--domain") + 1]) if "--domain" in argv else ""
    return {"check": check, "import": import_}[argv[0]](domain)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
