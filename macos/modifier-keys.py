#!/usr/bin/python3 -I
"""Give each keyboard the key mappings macos/keyboard-mappings.json names, through macOS's own
settings:

  - each external keyboard listed there gets its modifier swaps and its whole F1-F12 row through
    macOS's per-keyboard setting (the one System Settings > Keyboard > Keyboard Shortcuts >
    Modifier Keys writes);
  - the Mac's built-in keyboard gets its top-row overrides (built_in_function_keys) through
    hidutil, which capslock-to-f18.zsh applies at every login with Caps Lock to F18.

    modifier-keys.py check    list the keyboards whose macOS mapping differs from the record, and those
                              whose Caps Lock is set to another key or to none (exit 1 if any)
    modifier-keys.py import   write those mappings, and take out such a Caps Lock setting
    modifier-keys.py builtin  print, as JSON, the hidutil matching and mapping pairs for the built-in
                              keyboard's top-row overrides ({} on a Mac without one, or with none)

macOS keeps one mapping per keyboard, keyed by vendor and product id, in the current host's global
preferences (com.apple.keyboard.modifiermapping.<vendor>-<product>-0); it applies to a keyboard
when it next connects, or at the next login. The HID keyboard filter reads it as a general remap
table, so F-key-to-media pairs work there as well as modifier swaps. Caps Lock goes through
capslock-to-f18.zsh instead, and lives in a separate property (UserKeyMapping) of the same keyboard;
the two do not overwrite each other. A Caps Lock pair in the per-keyboard setting (Modifier Keys'
"Caps Lock key: No Action") is applied before UserKeyMapping, so Caps Lock would send nothing for
the agent to map: check reports it and import removes it.

The built-in keyboard is not carried through that setting. Its top row reaches the event system
already translated by Apple's Fn layer (F4 arrives as Spotlight, F5 as Dictation, per the keyboard's
FnFunctionUsageMap in ioreg), and the setting is read only when a keyboard connects, which the
built-in one never does. So `builtin` maps each translated usage the record overrides to the
override's target; fn+F4 stays F4. An override whose target equals Apple's default is left out.
To see what a connected keyboard actually has, read ioreg (`ioreg -r -c IOHIDEventService -l`, its
HIDEventServiceProperties): `hidutil property --get HIDKeyboardModifierMappingPairs` prints (null)
even while the mapping is live.
Option: --domain PATH reads and writes a plist file instead of the current host's global domain (tests).
MODIFIER_KEYS_MAPPINGS names another record, MODIFIER_KEYS_IOREG a file holding
`ioreg -r -c AppleHIDKeyboardEventDriverV2 -l -w0` output (tests).
"""
import json, os, plistlib, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAPPINGS = os.environ.get("MODIFIER_KEYS_MAPPINGS") or os.path.join(HERE, "keyboard-mappings.json")
MAPPING_PREFIX = "com.apple.keyboard.modifiermapping."


def page(p, u):
    """A HID usage as macOS's mapping stores it: usage page in the high 32 bits."""
    return (p << 32) | u


KEYBOARD, GENERIC_DESKTOP, CONSUMER, APPLE_KEYBOARD = 0x07, 0x01, 0x0C, 0xFF01
FKEY = {f"f{n}": page(KEYBOARD, 0x3A + n - 1) for n in range(1, 13)}
FKEY["f18"] = page(KEYBOARD, 0x6D)
CAPS_LOCK = page(KEYBOARD, 0x39)
MODIFIER = {"left_control": 0xE0, "left_shift": 0xE1, "left_option": 0xE2, "left_command": 0xE3,
            "right_control": 0xE4, "right_shift": 0xE5, "right_option": 0xE6, "right_command": 0xE7}
# Name -> HID usage, for keys and targets in keyboard-mappings.json.
TARGET = {k: page(KEYBOARD, u) for k, u in MODIFIER.items()}
TARGET.update(FKEY)
TARGET.update({
    "display_brightness_decrement": page(CONSUMER, 0x70),
    "display_brightness_increment": page(CONSUMER, 0x6F),
    "rewind": page(CONSUMER, 0xB4),
    "play_or_pause": page(CONSUMER, 0xCD),
    "fast_forward": page(CONSUMER, 0xB3),
    "mute": page(CONSUMER, 0xE2),
    "volume_decrement": page(CONSUMER, 0xEA),
    "volume_increment": page(CONSUMER, 0xE9),
    "dictation": page(CONSUMER, 0xCF),
    "do_not_disturb": page(GENERIC_DESKTOP, 0x9B),
    "mission_control": page(APPLE_KEYBOARD, 0x10),
    "spotlight": page(APPLE_KEYBOARD, 0x01),
    # Shortcut 160 (symbolic-hotkeys.plist) binds F18 to Show Launchpad (Show Apps on macOS 27),
    # the key Caps Lock sends too.
    "launchpad": FKEY["f18"],
})


def usage(name, where):
    """The usage of a name in TARGET, or exit naming what is missing."""
    if name not in TARGET:
        sys.exit(f"✗ {where}: {name} has no usage in modifier-keys.py's TARGET table; add it there")
    return TARGET[name]


def record():
    with open(MAPPINGS) as f:
        return json.load(f)


def wanted():
    """{preference key: [mapping dicts]} for each external keyboard in the record."""
    out = {}
    for kb in record().get("keyboards", []):
        vendor, product = kb["vendor_id"], kb["product_id"]
        where = f"keyboard {kb.get('name', f'{vendor}-{product}')}"
        pairs = [(usage(src, where), usage(dst, where)) for src, dst in kb.get("modifiers", {}).items()]
        for key, dst in sorted(kb.get("function_keys", {}).items(), key=lambda kv: int(kv[0][1:])):
            src, dst = usage(key, where), usage(dst, where)
            if src != dst:
                pairs.append((src, dst))
        if pairs:
            out[f"{MAPPING_PREFIX}{vendor}-{product}-0"] = [
                {"HIDKeyboardModifierMappingSrc": s, "HIDKeyboardModifierMappingDst": d} for s, d in pairs]
    return out


def live(domain):
    args = ["defaults", "export", domain, "-"] if domain else ["defaults", "-currentHost", "export", "-g", "-"]
    out = subprocess.run(args, capture_output=True)
    return plistlib.loads(out.stdout) if out.returncode == 0 and out.stdout else {}


def as_set(pairs):
    return sorted((p["HIDKeyboardModifierMappingSrc"], p["HIDKeyboardModifierMappingDst"]) for p in pairs or [])


def caps_lock_taken(have):
    """{preference key: its pairs without Caps Lock} for each keyboard whose setting sends Caps Lock
    to another key or to none (Modifier Keys' "Caps Lock key"), which the F18 agent cannot undo."""
    out = {}
    for key, pairs in have.items():
        if not key.startswith(MAPPING_PREFIX) or not isinstance(pairs, list):
            continue
        keep = [p for p in pairs if not (p.get("HIDKeyboardModifierMappingSrc") == CAPS_LOCK
                                         and p.get("HIDKeyboardModifierMappingDst") not in (CAPS_LOCK, FKEY["f18"]))]
        if len(keep) != len(pairs):
            out[key] = keep
    return out


def differing(domain):
    """(mappings to write, the keyboards among them whose Caps Lock setting is taken out)."""
    have = live(domain)
    caps = caps_lock_taken(have)
    todo = dict(caps)
    todo.update({k: v for k, v in wanted().items() if as_set(have.get(k)) != as_set(v)})
    return todo, set(caps)


def check(domain):
    todo, caps = differing(domain)
    for k in todo:
        if k in caps:
            print(f"differs here: keyboard {k.rsplit('.', 1)[1]} has Caps Lock set to another key or to none "
                  "(System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys), so it cannot open Launchpad")
        else:
            print(f"differs here: key mapping of keyboard {k.rsplit('.', 1)[1]}")
    if not todo:
        print("✓ keyboard mappings match macos/keyboard-mappings.json")
    return 1 if todo else 0


def import_(domain):
    todo, _ = differing(domain)
    if not todo:
        print("✓ keyboard mappings already match macos/keyboard-mappings.json")
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
    return 1 if differing(domain)[0] else 0


def builtin_keyboard():
    """(vendor, product, {F-key usage: the usage Apple's Fn layer turns it into}) of the Mac's
    built-in keyboard, from ioreg; None on a Mac without one."""
    if os.environ.get("MODIFIER_KEYS_IOREG"):
        with open(os.environ["MODIFIER_KEYS_IOREG"]) as f:
            text = f.read()
    else:
        text = subprocess.run(["ioreg", "-r", "-c", "AppleHIDKeyboardEventDriverV2", "-l", "-w0"],
                              capture_output=True, text=True).stdout
    for block in re.split(r"\n(?=\+-o )", text):
        if not re.search(r'"Built-In" = (Yes|1)\b', block):
            continue
        fn = re.search(r'"FnFunctionUsageMap" = "([0-9a-fx,]+)"', block)
        if not fn:
            continue
        ids = []
        for name in ("VendorID", "ProductID"):
            m = re.search(rf'"{name}" = (\d+)', block)
            ids.append(int(m.group(1)) if m else 0)
        values = [int(v, 16) for v in fn.group(1).split(",")]
        layer = {page(v >> 16, v & 0xFFFF): page(w >> 16, w & 0xFFFF) for v, w in zip(values[::2], values[1::2])}
        return ids[0], ids[1], layer
    return None


def builtin_pairs():
    """{matching, pairs} giving the built-in keyboard the record's top-row overrides, or {}."""
    found = builtin_keyboard()
    if not found:
        return {}
    vendor, product, layer = found
    pairs = []
    for key, dst in sorted(record().get("built_in_function_keys", {}).items(), key=lambda kv: int(kv[0][1:])):
        src = layer.get(usage(key, "built_in_function_keys"))
        dst = usage(dst, f"built_in_function_keys {key}")
        if src is not None and dst != src:
            pairs.append((src, dst))
    if not pairs:
        return {}
    return {"matching": {"VendorID": vendor, "ProductID": product, "PrimaryUsagePage": 1, "PrimaryUsage": 6},
            "pairs": pairs}


def builtin(_domain):
    print(json.dumps(builtin_pairs()))
    return 0


def main(argv):
    if not argv or argv[0] not in ("check", "import", "builtin"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    domain = os.path.realpath(argv[argv.index("--domain") + 1]) if "--domain" in argv else ""
    return {"check": check, "import": import_, "builtin": builtin}[argv[0]](domain)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
