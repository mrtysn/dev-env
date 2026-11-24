#!/usr/bin/python3 -I
"""On a Mac without Karabiner-Elements, give each external keyboard the key mappings that dev-env's
Karabiner config (karabiner/karabiner.json) gives it, through macOS's own per-keyboard setting
(the one System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys writes):

  - the modifier swaps Karabiner makes for that device (simple_modifications), and
  - F1-F12 as media keys, as Karabiner's fn_function_keys do: Karabiner's built-in defaults
    (FN_DEFAULTS below, copied from its source) with the config's own overrides on top.

    modifier-keys.py check    list the keyboards whose macOS mapping differs from Karabiner's (exit 1 if any)
    modifier-keys.py import   write those mappings

macOS keeps one mapping per keyboard, keyed by vendor and product id, in the current host's global
preferences (com.apple.keyboard.modifiermapping.<vendor>-<product>-0); it applies to a keyboard
when it next connects, or at the next login. The HID keyboard filter reads it as a general remap
table, so F-key-to-media pairs work there as well as modifier swaps. Only devices the config names
are carried, and never an Apple keyboard, whose top row already sends media keys. Caps Lock goes
through capslock-to-f18.zsh instead.
Option: --domain PATH reads and writes a plist file instead of the current host's global domain (tests).
"""
import json, os, plistlib, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KARABINER = os.environ.get("MODIFIER_KEYS_KARABINER") or os.path.join(os.path.dirname(HERE), "karabiner", "karabiner.json")
APPLE_VENDOR = 1452  # 0x05AC


def page(p, u):
    """A HID usage as macOS's mapping stores it: usage page in the high 32 bits."""
    return (p << 32) | u


KEYBOARD, GENERIC_DESKTOP, CONSUMER, APPLE_KEYBOARD = 0x07, 0x01, 0x0C, 0xFF01
FKEY = {f"f{n}": page(KEYBOARD, 0x3A + n - 1) for n in range(1, 13)}
FKEY["f18"] = page(KEYBOARD, 0x6D)
MODIFIER = {"left_control": 0xE0, "left_shift": 0xE1, "left_option": 0xE2, "left_command": 0xE3,
            "right_control": 0xE4, "right_shift": 0xE5, "right_option": 0xE6, "right_command": 0xE7}
# Karabiner target ({kind: name}) -> usage. Names and values from pqrs-org/cpp-hid usage.hpp.
TARGET = {("key_code", k): page(KEYBOARD, u) for k, u in MODIFIER.items()}
TARGET.update({("key_code", k): u for k, u in FKEY.items()})
TARGET.update({
    ("consumer_key_code", "display_brightness_decrement"): page(CONSUMER, 0x70),
    ("consumer_key_code", "display_brightness_increment"): page(CONSUMER, 0x6F),
    ("consumer_key_code", "rewind"): page(CONSUMER, 0xB4),
    ("consumer_key_code", "play_or_pause"): page(CONSUMER, 0xCD),
    ("consumer_key_code", "fast_forward"): page(CONSUMER, 0xB3),
    ("consumer_key_code", "mute"): page(CONSUMER, 0xE2),
    ("consumer_key_code", "volume_decrement"): page(CONSUMER, 0xEA),
    ("consumer_key_code", "volume_increment"): page(CONSUMER, 0xE9),
    ("consumer_key_code", "dictation"): page(CONSUMER, 0xCF),
    ("generic_desktop", "do_not_disturb"): page(GENERIC_DESKTOP, 0x9B),
    ("apple_vendor_keyboard_key_code", "mission_control"): page(APPLE_KEYBOARD, 0x10),
    ("apple_vendor_keyboard_key_code", "spotlight"): page(APPLE_KEYBOARD, 0x01),
    # macOS 27 has no Launchpad; its successor Show Apps is bound to F18 by the machine's shortcuts
    # (symbolic hotkey 160), the key Caps Lock sends here too.
    ("key_code", "launchpad"): FKEY["f18"],
    ("apple_vendor_keyboard_key_code", "launchpad"): FKEY["f18"],
})
# Karabiner-Elements' default fn_function_keys (src/share/core_configuration/details/profile.hpp).
FN_DEFAULTS = {
    "f1": ("consumer_key_code", "display_brightness_decrement"),
    "f2": ("consumer_key_code", "display_brightness_increment"),
    "f3": ("apple_vendor_keyboard_key_code", "mission_control"),
    "f4": ("apple_vendor_keyboard_key_code", "spotlight"),
    "f5": ("consumer_key_code", "dictation"),
    "f6": ("generic_desktop", "do_not_disturb"),
    "f7": ("consumer_key_code", "rewind"),
    "f8": ("consumer_key_code", "play_or_pause"),
    "f9": ("consumer_key_code", "fast_forward"),
    "f10": ("consumer_key_code", "mute"),
    "f11": ("consumer_key_code", "volume_decrement"),
    "f12": ("consumer_key_code", "volume_increment"),
}


def target(to, where):
    """The usage of a Karabiner `to` list holding one key, or exit naming what is not carried."""
    if len(to) != 1 or len(to[0]) != 1:
        sys.exit(f"✗ {where}: only a single target key can be carried, not {to}")
    (kind, name), = to[0].items()
    if (kind, name) not in TARGET:
        sys.exit(f"✗ {where}: {kind} {name} has no usage in modifier-keys.py's TARGET table; add it there")
    return TARGET[(kind, name)]


def function_keys(profile):
    """[(src, dst)] for F1-F12 under this profile: Karabiner's defaults, then its overrides."""
    chosen = dict(FN_DEFAULTS)
    for rule in profile.get("fn_function_keys", []):
        chosen[rule["from"]["key_code"]] = rule["to"]
    pairs = []
    for key in sorted(chosen, key=lambda k: int(k[1:])):
        to = chosen[key]
        dst = TARGET[to] if isinstance(to, tuple) else target(to, f"fn_function_keys {key}")
        if dst != FKEY[key]:
            pairs.append((FKEY[key], dst))
    return pairs


def wanted():
    """{preference key: [mapping dicts]} for each named external keyboard."""
    with open(KARABINER) as f:
        config = json.load(f)
    out = {}
    for profile in config.get("profiles", []):
        if not profile.get("selected", True) and len(config.get("profiles", [])) > 1:
            continue
        fn = function_keys(profile)
        for device in profile.get("devices", []):
            ids = device.get("identifiers", {})
            vendor, product = ids.get("vendor_id"), ids.get("product_id")
            if not ids.get("is_keyboard") or vendor is None or product is None or vendor == APPLE_VENDOR:
                continue
            pairs = []
            for rule in device.get("simple_modifications", []):
                src = rule.get("from", {}).get("key_code")
                if src in MODIFIER:
                    pairs.append((TARGET[("key_code", src)], target(rule.get("to", []), f"device {vendor}-{product} {src}")))
            pairs += fn
            if pairs:
                out[f"com.apple.keyboard.modifiermapping.{vendor}-{product}-0"] = [
                    {"HIDKeyboardModifierMappingSrc": s, "HIDKeyboardModifierMappingDst": d} for s, d in pairs]
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
        print(f"differs here: key mapping of keyboard {k.rsplit('.', 1)[1]}")
    if not todo:
        print("✓ keyboard mappings match Karabiner's config")
    return 1 if todo else 0


def import_(domain):
    todo = differing(domain)
    if not todo:
        print("✓ keyboard mappings already match Karabiner's config")
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
        print(f"✓ set the key mapping of keyboard {key.rsplit('.', 1)[1]} (applies when it reconnects or at the next login)")
    return 1 if differing(domain) else 0


def main(argv):
    if not argv or argv[0] not in ("check", "import"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    domain = os.path.realpath(argv[argv.index("--domain") + 1]) if "--domain" in argv else ""
    return {"check": check, "import": import_}[argv[0]](domain)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
