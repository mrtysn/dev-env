#!/usr/bin/python3 -I
"""Carry macOS settings (Finder, Dock, global UI and input, trackpad and mouse, screenshots, menu bar
and Control Center) between machines; system-settings.json says which domains and which keys.

    system-settings.py export   record this Mac's allowlisted settings in macos/system-settings/
    system-settings.py import   make this Mac match the record, then restart what shows them
    system-settings.py check    list the recorded settings that differ here (exit 1 if any)

Both directions write only what differs, so a second run changes nothing. A key this Mac has
never written is not recorded: it keeps macOS's default on the other machine too.

Per machine: system-settings/<name>.plist is the shared record, written by the machine in its
"_machine" key. Any other machine (--label, from machine-label.sh) records only the keys where it
differs, in <name>.<label>.plist, and import applies that on top of the shared record.

The home folder is recorded as $HOME and expanded on import. Export refuses any other value that
holds the home path, or an email address, since this repo is public.
Import first saves each domain it changes, whole, to
~/.macos-settings-backup-<date>/<name>.plist; `defaults import <domain> FILE` puts one back.
Options: --label LABEL (this machine's label); --dir DIR reads and writes DIR/<name>.plist files
instead of the user's domains and restarts nothing (tests); --record DIR keeps the record there
instead of macos/system-settings (tests).
"""
import json, os, plistlib, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
TOKEN = "$HOME"
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")
ACTIVATE = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
# What a Dock tile needs to be rebuilt; the rest (bookmark, GUID, dates) is per machine.
TILE_KEYS = {"file-data", "file-label", "file-type", "bundle-identifier", "arrangement", "displayas",
             "showas", "preferreditemsize", "url", "label"}
GREEN, YELLOW, RED, NC = "\033[0;32m", "\033[1;33m", "\033[0;31m", "\033[0m"


def say(colour, text):
    print(f"{colour}{text}{NC}")


def load_domains():
    with open(os.path.join(HERE, "system-settings.json")) as f:
        return json.load(f)["domains"]


class Store:
    """Where the live settings are: the user's domains, or plist files under --dir (tests)."""

    def __init__(self, test_dir):
        self.dir = test_dir

    def cmd(self, d):
        if self.dir:
            return ["defaults"], os.path.join(self.dir, f"{d['name']}.plist")
        return (["defaults", "-currentHost"] if d.get("host") else ["defaults"]), d["domain"]

    def read(self, d):
        base, target = self.cmd(d)
        if self.dir and not os.path.exists(target):
            return {}
        out = subprocess.run([*base, "export", target, "-"], capture_output=True)
        return plistlib.loads(out.stdout) if out.returncode == 0 and out.stdout else {}

    def write(self, d, whole):
        base, target = self.cmd(d)
        out = subprocess.run([*base, "import", target, "-"],
                             input=plistlib.dumps(whole, fmt=plistlib.FMT_BINARY), capture_output=True)
        return out.returncode == 0, out.stderr.decode().strip()


def tile(t):
    """A Dock tile reduced to what rebuilds it. Spacers keep only their type."""
    data = {k: v for k, v in t.get("tile-data", {}).items() if k in TILE_KEYS}
    if "file-data" in data:
        data["file-data"] = {k: v for k, v in data["file-data"].items() if k.startswith("_CFURLString")}
    return {"tile-type": t.get("tile-type", ""), "tile-data": data}


def portable(v):
    """The value as recorded: the home folder as $HOME. Bytes are left as they are."""
    if isinstance(v, str):
        return v.replace(HOME, TOKEN)
    if isinstance(v, dict):
        return {k: portable(x) for k, x in v.items()}
    if isinstance(v, list):
        return [portable(x) for x in v]
    return v


def local(v):
    if isinstance(v, str):
        return v.replace(TOKEN, HOME)
    if isinstance(v, dict):
        return {k: local(x) for k, x in v.items()}
    if isinstance(v, list):
        return [local(x) for x in v]
    return v


def leaks(v):
    text = repr(v)
    return HOME in text or EMAIL.search(text) is not None


def carried(d, live, report=False):
    """The allowlisted keys of a domain, in recorded form."""
    allow = re.compile(d["keys"])
    tiles = set(d.get("tiles", []))
    out = {}
    for k, v in live.items():
        if not allow.fullmatch(k):
            continue
        if k in tiles and isinstance(v, list):
            v = [tile(t) for t in v]
        v = portable(v)
        if leaks(v):
            if report:
                say(RED, f"✗ {d['name']}: key {k} holds a home path or an address, not exported")
            continue
        out[k] = v
    return out


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, "rb") as f:
        return plistlib.load(f)


class Record:
    def __init__(self, record_dir):
        self.dir = record_dir

    def shared_path(self, d):
        return os.path.join(self.dir, f"{d['name']}.plist")

    def overlay_path(self, d, label):
        return os.path.join(self.dir, f"{d['name']}.{label}.plist")

    def owner(self, d):
        return load(self.shared_path(d)).get("_machine", "")

    def shared(self, d):
        return {k: v for k, v in load(self.shared_path(d)).items() if not k.startswith("_")}

    def wanted(self, d, label):
        want = self.shared(d)
        if label and label != self.owner(d):
            want.update(load(self.overlay_path(d, label)))
        return want


def write_if_changed(path, data):
    blob = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=True)
    if os.path.exists(path) and open(path, "rb").read() == blob:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(blob)
    return True


def export(domains, store, rec, label):
    changed = 0
    for d in domains:
        live = carried(d, store.read(d), report=True)
        if not live:
            continue
        owner = rec.owner(d)
        if not os.path.exists(rec.shared_path(d)) or not owner or owner == label:
            if write_if_changed(rec.shared_path(d), dict(live, _machine=label or "unknown")):
                changed += 1
                say(GREEN, f"✓ exported {d['name']} ({len(live)} keys)")
            continue
        base = rec.shared(d)
        diff = {k: v for k, v in live.items() if base.get(k) != v}
        path = rec.overlay_path(d, label)
        if not diff:
            if os.path.exists(path):
                os.remove(path)
                changed += 1
                say(GREEN, f"✓ {d['name']}: {label} matches the shared record now, removed its overlay")
            continue
        if write_if_changed(path, diff):
            changed += 1
            say(GREEN, f"✓ exported {d['name']}: {len(diff)} keys where {label} differs")
    if not changed:
        say(GREEN, "✓ macOS settings already match the repo")
    return 0


def differing(d, store, rec, label):
    want = rec.wanted(d, label)
    have = carried(d, store.read(d))
    return want, {k: v for k, v in want.items() if have.get(k) != v}


def import_(domains, store, rec, label):
    restart, bad, total = set(), 0, 0
    backup = ""
    for d in domains:
        want, todo = differing(d, store, rec, label)
        if not todo:
            continue
        whole = store.read(d)
        if not backup:
            backup = os.path.join(store.dir or HOME, time.strftime(".macos-settings-backup-%Y%m%d-%H%M%S"))
            os.makedirs(backup)
        with open(os.path.join(backup, f"{d['name']}.plist"), "wb") as f:
            plistlib.dump(whole, f, fmt=plistlib.FMT_BINARY)
        whole.update(local(todo))
        ok, err = store.write(d, whole)
        left = differing(d, store, rec, label)[1]
        if not ok or left:
            bad = 1
            say(RED, f"✗ {d['name']}: still different: {', '.join(sorted(left)) or err}")
            continue
        total += len(todo)
        say(GREEN, f"✓ {d['name']}: set {', '.join(sorted(todo))}")
        restart.update(d.get("restart", []))
    if not total and not bad:
        say(GREEN, "✓ macOS settings already match the repo")
    if backup:
        print(f"  the settings before this import are in {backup}")
    if restart and not store.dir:
        for proc in sorted(restart):
            subprocess.run(["killall", proc], capture_output=True)
        if os.access(ACTIVATE, os.X_OK):
            subprocess.run([ACTIVATE, "-u"], capture_output=True)
        print(f"  restarted {', '.join(sorted(restart))}; trackpad, mouse and input source changes "
              "take full effect at the next login")
    return bad


def check(domains, store, rec, label):
    bad = 0
    for d in domains:
        _, todo = differing(d, store, rec, label)
        for k in sorted(todo):
            bad = 1
            print(f"differs here: {d['name']} {k}")
    if not bad:
        print("✓ the recorded macOS settings match")
    return bad


def main(argv):
    if not argv or argv[0] not in ("export", "import", "check"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    def opt(name, default=""):
        return argv[argv.index(name) + 1] if name in argv else default
    store = Store(os.path.realpath(opt("--dir")) if "--dir" in argv else "")
    rec = Record(opt("--record") or os.path.join(HERE, "system-settings"))
    label = opt("--label")
    return {"export": export, "import": import_, "check": check}[argv[0]](load_domains(), store, rec, label)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
