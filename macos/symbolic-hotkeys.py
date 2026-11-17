#!/usr/bin/python3 -I
"""Carry the macOS keyboard shortcuts of System Settings > Keyboard > Keyboard Shortcuts
(com.apple.symbolichotkeys) between machines: which are on or off, and the keys each one uses.

    symbolic-hotkeys.py export   record every shortcut entry this Mac has written in symbolic-hotkeys.plist
    symbolic-hotkeys.py import   make the same entries match here, then apply them without a logout
    symbolic-hotkeys.py check    list the recorded entries that differ here (exit 1 if any)

macOS writes an entry once a shortcut is changed or switched off, and some on its own; entries it
has not written keep their defaults, here and on the other machine alike. An entry that already
matches is left alone, so a re-run changes nothing.
Option: --domain PATH reads and writes a plist file instead of the user's domain (tests).
"""
import os, plistlib, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RECORD = os.environ.get("SYMBOLIC_HOTKEYS_RECORD") or os.path.join(HERE, "symbolic-hotkeys.plist")  # override: tests
DOMAIN = "com.apple.symbolichotkeys"
ACTIVATE = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
# Names for the entries most often changed; any other id is still carried, just unnamed.
NAMES = {"28": "Save picture of screen as a file", "29": "Copy picture of screen to the clipboard",
         "30": "Save picture of selected area as a file", "31": "Copy picture of selected area to the clipboard",
         "184": "Screenshot and recording options", "60": "Select the previous input source",
         "61": "Select next source in Input menu", "64": "Show Spotlight search",
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
    data = plistlib.dumps(entries(domain), fmt=plistlib.FMT_XML, sort_keys=True)
    old = open(RECORD, "rb").read() if os.path.exists(RECORD) else None
    count = len(plistlib.loads(data))
    if old == data:
        print(f"✓ keyboard shortcuts already match the repo ({count} entries)")
        return 0
    with open(RECORD, "wb") as f:
        f.write(data)
    print(f"✓ exported {count} keyboard shortcut entries to macos/symbolic-hotkeys.plist")
    return 0


def differing(domain):
    if not os.path.exists(RECORD):
        return {}, {}
    with open(RECORD, "rb") as f:
        want = plistlib.load(f)
    have = entries(domain)
    return want, {k: v for k, v in want.items() if have.get(k) != v}


def import_(domain):
    want, todo = differing(domain)
    if not todo:
        print(f"✓ the {len(want)} recorded shortcut entries already match")
        return 0
    whole = read(domain)
    whole.setdefault("AppleSymbolicHotKeys", {}).update(todo)
    for k in todo:
        print(f"→ setting {name(k)} ({'on' if todo[k].get('enabled', True) else 'off'})")
    out = subprocess.run(["defaults", "import", domain, "-"],
                         input=plistlib.dumps(whole, fmt=plistlib.FMT_BINARY), capture_output=True)
    if out.returncode != 0:
        print(f"✗ defaults import failed: {out.stderr.decode().strip()}")
        return 1
    if domain == DOMAIN and os.access(ACTIVATE, os.X_OK):
        # Applies the new shortcuts now; without it they take effect at the next login.
        subprocess.run([ACTIVATE, "-u"], capture_output=True)
    left = differing(domain)[1]
    if left:
        print(f"✗ still different: {', '.join(name(k) for k in left)}")
        return 1
    print(f"✓ set {len(todo)} shortcut entr{'y' if len(todo) == 1 else 'ies'}")
    return 0


def check(domain):
    want, todo = differing(domain)
    for k in todo:
        print(f"differs here: {name(k)}")
    if not todo:
        print(f"✓ the {len(want)} recorded shortcut entries match")
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
