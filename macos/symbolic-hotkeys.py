#!/usr/bin/python3 -I
"""Carry the macOS keyboard shortcuts of System Settings > Keyboard > Keyboard Shortcuts
(com.apple.symbolichotkeys) between machines: which are on or off, and the keys each one uses.

    symbolic-hotkeys.py export   record every shortcut entry this Mac has written in symbolic-hotkeys.plist
    symbolic-hotkeys.py import   make the same entries match here, then apply them without a logout
    symbolic-hotkeys.py check    list the recorded entries that differ here (exit 1 if any)

macOS writes an entry once a shortcut is changed or switched off, and some on its own; entries it
has not written keep their defaults, here and on the other machine alike. An entry that already
matches is left alone, so a re-run changes nothing.

Per machine: symbolic-hotkeys.plist is the shared record, written by the machine named in its
"_machine" key. Any other machine (--label, from machine-label.sh) records only where it differs, in
symbolic-hotkeys.<label>.plist, and import applies that on top of the shared record. So the work
Mac can keep Show Launchpad on F18 while the home Mac has it off.
Options: --label LABEL (this machine's label); --domain PATH reads and writes a plist file instead
of the user's domain (tests).
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


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, "rb") as f:
        return plistlib.load(f)


def overlay_path(label):
    return os.path.join(os.path.dirname(RECORD), f"symbolic-hotkeys.{label}.plist")


def shared():
    """The shared record's entries, without its "_machine" key."""
    return {k: v for k, v in load(RECORD).items() if not k.startswith("_")}


def owner():
    return load(RECORD).get("_machine", "")


def write(path, data, what):
    blob = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=True)
    old = open(path, "rb").read() if os.path.exists(path) else None
    if old == blob:
        print(f"✓ {what} already match the repo")
        return
    with open(path, "wb") as f:
        f.write(blob)
    print(f"✓ exported {what} to macos/{os.path.basename(path)}")


def export(domain, label):
    live = entries(domain)
    if not os.path.exists(RECORD) or not owner() or owner() == label:
        write(RECORD, dict(live, _machine=label or "unknown"), f"{len(live)} keyboard shortcut entries")
        return 0
    base = shared()
    diff = {k: v for k, v in live.items() if base.get(k) != v}
    write(overlay_path(label), diff, f"{len(diff)} shortcut entries where {label} differs")
    return 0


def wanted(label):
    want = shared()
    if label and label != owner():
        want.update(load(overlay_path(label)))
    return want


def differing(domain, label=""):
    want = wanted(label)
    have = entries(domain)
    return want, {k: v for k, v in want.items() if have.get(k) != v}


def import_(domain, label):
    want, todo = differing(domain, label)
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
    left = differing(domain, label)[1]
    if left:
        print(f"✗ still different: {', '.join(name(k) for k in left)}")
        return 1
    print(f"✓ set {len(todo)} shortcut entr{'y' if len(todo) == 1 else 'ies'}")
    return 0


def check(domain, label):
    want, todo = differing(domain, label)
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
    label = argv[argv.index("--label") + 1] if "--label" in argv else ""
    return {"export": export, "import": import_, "check": check}[argv[0]](domain, label)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
