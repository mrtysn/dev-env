#!/usr/bin/python3 -I
"""Carry the macOS keyboard shortcuts of System Settings > Keyboard > Keyboard Shortcuts
(com.apple.symbolichotkeys) between machines: which are on or off, and the keys each one uses.

    symbolic-hotkeys.py export   record every shortcut entry this Mac has written in symbolic-hotkeys.plist
    symbolic-hotkeys.py import   make the same entries match here, then apply them without a logout
    symbolic-hotkeys.py check    list the recorded entries that differ here (exit 1 if any)

macOS writes an entry once a shortcut is changed or switched off, and some on its own; entries it
has not written keep their defaults, here and on the other machine alike. An entry that already
matches is left alone, so a re-run changes nothing.

Shared by default: symbolic-hotkeys.plist is the one record every machine syncs to; an export on
any machine updates it, and an entry the exporting Mac has never written keeps its recorded value.
Only the entries machine-keeps.json lists for this machine (--label, from machine-label.sh) go to
symbolic-hotkeys.<label>.plist instead, laid over the shared record on import here. No machine
keeps an entry today: Show Launchpad (Show Apps on macOS 27) on F18, the key Caps Lock sends, is shared.
Export refuses a record that changed since this Mac last imported it (lib/sync_state.py).
Options: --label LABEL (this machine's label); --force; --domain PATH reads and writes a plist file instead
of the user's domain (tests).
"""
import os, plistlib, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
import sync_state  # noqa: E402
FORCE = False  # --force: export over a record this Mac is behind on
RECORD = os.environ.get("SYMBOLIC_HOTKEYS_RECORD") or os.path.join(HERE, "symbolic-hotkeys.plist")  # override: tests
DOMAIN = "com.apple.symbolichotkeys"
ACTIVATE = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
# Names for the entries most often changed; any other id is still carried, just unnamed.
NAMES = {"28": "Save picture of screen as a file", "29": "Copy picture of screen to the clipboard",
         "30": "Save picture of selected area as a file", "31": "Copy picture of selected area to the clipboard",
         "184": "Screenshot and recording options", "60": "Select the previous input source",
         "61": "Select next source in Input menu", "64": "Show Spotlight search",
         "160": "Show Launchpad (Show Apps on macOS 27)", "32": "Mission Control", "33": "Application windows", "36": "Show Desktop"}


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


def write(path, data, what):
    blob = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=True)
    old = open(path, "rb").read() if os.path.exists(path) else None
    if old == blob:
        print(f"✓ {what} already match the repo")
        return
    with open(path, "wb") as f:
        f.write(blob)
    print(f"✓ exported {what} to macos/{os.path.basename(path)}")


def keeps(label):
    return sync_state.kept("symbolic-hotkeys", "symbolic-hotkeys", label)


def export(domain, label):
    live = entries(domain)
    keep = keeps(label)
    mine = {k: v for k, v in live.items() if k in keep}
    path = overlay_path(label) if label else ""
    if mine:
        write(path, mine, f"the shortcut entries {label} keeps ({', '.join(name(k) for k in sorted(mine))})")
    elif path and os.path.exists(path):
        os.remove(path)
        print(f"✓ {label} keeps no shortcut entries of its own now, removed macos/{os.path.basename(path)}")
    base = shared()
    new = dict(base)  # an entry this Mac never wrote, or keeps for itself, stays as recorded
    new.update({k: v for k, v in live.items() if k not in keep})
    if new == base and os.path.exists(RECORD):
        print("✓ keyboard shortcut entries already match the repo")
        return 0
    if sync_state.behind(RECORD) and not FORCE:
        print("✗ " + sync_state.refusal("keyboard shortcuts", 17))
        return 1
    write(RECORD, new, f"{len(new)} keyboard shortcut entries")
    sync_state.mark(RECORD)
    return 0


def wanted(label):
    want = shared()
    keep = keeps(label)
    want.update({k: v for k, v in load(overlay_path(label)).items() if k in keep} if label else {})
    return want


def differing(domain, label=""):
    want = wanted(label)
    have = entries(domain)
    return want, {k: v for k, v in want.items() if have.get(k) != v}


def import_(domain, label):
    want, todo = differing(domain, label)
    if not todo:
        sync_state.mark(RECORD)
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
    sync_state.mark(RECORD)
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
    global FORCE
    FORCE = "--force" in argv
    return {"export": export, "import": import_, "check": check}[argv[0]](domain, label)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
