#!/usr/bin/python3 -I
"""Carry the macOS keyboard shortcuts switched off in System Settings > Keyboard > Keyboard
Shortcuts (com.apple.symbolichotkeys) between machines.

    symbolic-hotkeys.py export   record every shortcut that is off here in symbolic-hotkeys-off.plist
    symbolic-hotkeys.py import   switch the recorded ones off here, then apply them without a logout
    symbolic-hotkeys.py check    list the recorded ones still on here (exit 1 if any)

Only the "off" state moves: a shortcut switched off on one Mac is switched off on the others.
Nothing is switched on, and an entry already off is left alone, so a re-run changes nothing.
Option: --domain PATH reads and writes a plist file instead of the user's domain (tests).
"""
import os, plistlib, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RECORD = os.environ.get("SYMBOLIC_HOTKEYS_RECORD") or os.path.join(HERE, "symbolic-hotkeys-off.plist")  # override: tests
DOMAIN = "com.apple.symbolichotkeys"
ACTIVATE = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
# Names for the entries most often switched off; any other id is still carried, just unnamed.
NAMES = {"28": "Save picture of screen as a file (⇧⌘3)", "29": "Copy picture of screen (⌃⇧⌘3)",
         "30": "Save picture of selected area as a file (⇧⌘4)", "31": "Copy picture of selected area (⌃⇧⌘4)",
         "184": "Screenshot and recording options (⇧⌘5)", "60": "Select the previous input source (⌃Space)",
         "61": "Select next source in Input menu (⌃⌥Space)", "64": "Show Spotlight search (⌘Space)",
         "160": "Show Launchpad", "32": "Mission Control", "33": "Application windows", "36": "Show Desktop"}


def read(domain):
    out = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
    if out.returncode != 0 or not out.stdout:
        return {}
    return plistlib.loads(out.stdout)


def entries(domain):
    return read(domain).get("AppleSymbolicHotKeys", {})


def name(key):
    return NAMES.get(key, f"shortcut {key}")


def export(domain):
    off = {k: v for k, v in entries(domain).items() if not v.get("enabled", True)}
    data = plistlib.dumps(off, fmt=plistlib.FMT_XML, sort_keys=True)
    old = open(RECORD, "rb").read() if os.path.exists(RECORD) else None
    if old == data:
        print(f"✓ symbolic hotkeys already match the repo ({len(off)} off)")
        return 0
    with open(RECORD, "wb") as f:
        f.write(data)
    print(f"✓ exported {len(off)} switched-off shortcuts to macos/symbolic-hotkeys-off.plist")
    return 0


def still_on(domain):
    if not os.path.exists(RECORD):
        return {}, {}
    with open(RECORD, "rb") as f:
        want = plistlib.load(f)
    have = entries(domain)
    return want, {k: v for k, v in want.items() if have.get(k, {}).get("enabled", True)}


def import_(domain):
    want, todo = still_on(domain)
    if not todo:
        print(f"✓ the {len(want)} recorded shortcuts are already off")
        return 0
    whole = read(domain)
    hotkeys = whole.setdefault("AppleSymbolicHotKeys", {})
    for k, v in todo.items():
        entry = dict(hotkeys.get(k) or v)
        entry["enabled"] = False
        hotkeys[k] = entry
        print(f"→ switching off {name(k)}")
    out = subprocess.run(["defaults", "import", domain, "-"],
                         input=plistlib.dumps(whole, fmt=plistlib.FMT_BINARY), capture_output=True)
    if out.returncode != 0:
        print(f"✗ defaults import failed: {out.stderr.decode().strip()}")
        return 1
    if domain == DOMAIN and os.access(ACTIVATE, os.X_OK):
        # Applies the new shortcuts now; without it they take effect at the next login.
        subprocess.run([ACTIVATE, "-u"], capture_output=True)
    left = still_on(domain)[1]
    if left:
        print(f"✗ still on: {', '.join(name(k) for k in left)}")
        return 1
    print(f"✓ switched off {len(todo)} shortcut(s)")
    return 0


def check(domain):
    want, todo = still_on(domain)
    for k in todo:
        print(f"on here, off in the repo: {name(k)}")
    if not todo:
        print(f"✓ the {len(want)} recorded shortcuts are off")
    return 1 if todo else 0


def main(argv):
    if not argv or argv[0] not in ("export", "import", "check"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    domain = DOMAIN
    if "--domain" in argv:
        domain = os.path.realpath(argv[argv.index("--domain") + 1])
    return {"export": export, "import": import_, "check": check}[argv[0]](domain)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
