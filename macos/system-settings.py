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

Across macOS versions: each record keeps the macOS major version it was exported on ("_macos"),
and check and import name the domains recorded on another version, since a key that version
renamed or dropped is written and then ignored, and still reads as matching. A Dock tile whose
app is not on this Mac (Launchpad, on the macOS 27 Mac) is left out and named, not set as a "?" tile.

The home folder is recorded as $HOME and expanded on import. Export refuses any other value that
holds the home path, or an email address, since this repo is public.
Import first saves each domain it changes, whole, to
~/.macos-settings-backup-<date>/<name>.plist; `defaults import <domain> FILE` puts one back
(`defaults -currentHost import com.apple.controlcenter FILE` for control-center-host). Import
writes only the keys that differ: `defaults import` merges them into the domain, keeping the rest.
A domain marked "same_version" in system-settings.json (Spotlight's category list, which macOS
versions change) is applied only on the macOS version it was recorded on.
Options: --label LABEL (this machine's label); --dir DIR reads and writes DIR/<name>.plist files
instead of the user's domains and restarts nothing (tests); --record DIR keeps the record there
instead of macos/system-settings (tests); --macos N takes N as this Mac's major version (tests).
"""
import json, os, plistlib, re, subprocess, sys, time
from urllib.parse import unquote, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
TOKEN = "$HOME"
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")
ACTIVATE = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
# What a Dock tile needs to be rebuilt; the rest (bookmark, GUID, dates) is per machine.
TILE_KEYS = {"file-data", "file-label", "file-type", "bundle-identifier", "arrangement", "displayas",
             "showas", "preferreditemsize", "url", "label"}
GREEN, YELLOW, RED, NC = "\033[0;32m", "\033[1;33m", "\033[0;31m", "\033[0m"


def macos_major():
    out = subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True)
    return out.stdout.strip().split(".")[0]


MACOS = ""  # this Mac's major version, set in main
META = {"_machine", "_macos", "_not_set"}  # the record's own keys; Finder's real keys may start with _ too


def say(colour, text):
    print(f"{colour}{text}{NC}")


def load_domains():
    with open(os.path.join(HERE, "system-settings.json")) as f:
        return json.load(f)["domains"]


class Unreadable(Exception):
    """A domain whose current values could not be read: nothing may be written to it."""


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
        if out.returncode != 0:
            raise Unreadable(f"defaults export {target} failed: {out.stderr.decode().strip()}")
        try:
            return plistlib.loads(out.stdout) if out.stdout else {}
        except Exception as e:
            raise Unreadable(f"defaults export {target} gave no plist: {e}")

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

    def version(self, d):
        return str(load(self.shared_path(d)).get("_macos", ""))

    def shared(self, d):
        allow = re.compile(d["keys"])  # a key since dropped from the allowlist is no longer wanted
        return {k: v for k, v in load(self.shared_path(d)).items() if k not in META and allow.fullmatch(k)}

    def overlay(self, d, label):
        allow = re.compile(d["keys"])
        return {k: v for k, v in load(self.overlay_path(d, label)).items() if k not in META and allow.fullmatch(k)}

    def overlay_version(self, d, label):
        return str(load(self.overlay_path(d, label)).get("_macos", ""))

    def applies(self, d, label):
        """False for a same_version domain recorded on another macOS than this Mac's."""
        if not d.get("same_version"):
            return True
        if label and label != self.owner(d) and self.overlay_version(d, label) == MACOS:
            return True
        return self.version(d) == MACOS

    def wanted(self, d, label):
        if not self.applies(d, label):
            return {}, []
        want = self.shared(d)
        if label and label != self.owner(d):
            want.update(self.overlay(d, label))
            for k in load(self.overlay_path(d, label)).get("_not_set", []):
                want.pop(k, None)
        return present_tiles(d, want)


def tile_path(t):
    url = t.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
    return unquote(urlparse(local(url)).path) if url.startswith("file://") else ""


def present_tiles(d, want):
    """The wanted settings without Dock tiles whose app or folder is not on this Mac, and their labels."""
    skipped = []
    for k in d.get("tiles", []):
        if isinstance(want.get(k), list):
            keep = []
            for t in want[k]:
                path = tile_path(t)
                if path and not os.path.exists(path):
                    skipped.append(t["tile-data"].get("file-label") or os.path.basename(path.rstrip("/")))
                else:
                    keep.append(t)
            want = dict(want, **{k: keep})
    return want, skipped


def version_note(domains, rec, label):
    """A line naming the domains recorded on another macOS major version than this Mac's, or "".
    A domain this Mac has exported its own overlay for, on its own version, is not named."""
    other, skipped = {}, []
    for d in domains:
        if not os.path.exists(rec.shared_path(d)) or rec.version(d) == MACOS:
            continue
        if label and label != rec.owner(d) and rec.overlay_version(d, label) == MACOS:
            continue
        if not rec.applies(d, label):
            skipped.append(d["name"])
            continue
        other.setdefault(rec.version(d) or "an unrecorded version", []).append(d["name"])
    names = [n for v in other.values() for n in v]
    lines = []
    if other:
        vs = "/".join(sorted(other))
        which = "all of them" if len(names) + len(skipped) == sum(os.path.exists(rec.shared_path(d)) for d in domains) and not skipped else ", ".join(names)
        lines.append(f"recorded on macOS {vs}, this Mac runs {MACOS} ({which})")
    if skipped:
        lines.append(f"not applied, recorded on another macOS version: {', '.join(skipped)}")
    return "; ".join(lines)


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
        try:
            live = carried(d, store.read(d), report=True)
        except Unreadable as e:
            say(RED, f"✗ {d['name']}: {e}, not exported")
            continue
        owner = rec.owner(d)
        if not os.path.exists(rec.shared_path(d)) or not owner or owner == label:
            if not live:
                continue
            if write_if_changed(rec.shared_path(d), dict(live, _machine=label or "unknown", _macos=MACOS)):
                changed += 1
                say(GREEN, f"✓ exported {d['name']} ({len(live)} keys)")
            continue
        base = present_tiles(d, rec.shared(d))[0]  # a tile for an app this Mac lacks is not a difference
        diff = {k: v for k, v in live.items() if base.get(k) != v}
        # A shared key this Mac has never written stays unset here, rather than taking the owner's value:
        # a default left alone, or a key this Mac's macOS no longer reads.
        not_set = sorted(k for k in base if k not in live)
        if not_set:
            diff["_not_set"] = not_set
        path = rec.overlay_path(d, label)
        if not diff:
            if os.path.exists(path):
                os.remove(path)
                changed += 1
                say(GREEN, f"✓ {d['name']}: {label} matches the shared record now, removed its overlay")
            continue
        if write_if_changed(path, dict(diff, _macos=MACOS)):
            changed += 1
            say(GREEN, f"✓ exported {d['name']}: {len(diff) - bool(not_set)} keys where {label} differs"
                       + (f", {len(not_set)} it leaves unset" if not_set else ""))
    if not changed:
        say(GREEN, "✓ macOS settings already match the repo")
    return 0


def differing(d, store, rec, label):
    want, skipped = rec.wanted(d, label)
    have = carried(d, store.read(d))
    return want, {k: v for k, v in want.items() if have.get(k) != v}, skipped


def warn_versions(domains, rec, label):
    note = version_note(domains, rec, label)
    if note:
        say(YELLOW, f"! {note}. A key that macOS renamed or dropped is written and then ignored, "
                    "and still reads as matching: look at those settings once by hand.")


def import_(domains, store, rec, label):
    restart, bad, total, written = set(), 0, 0, []
    backup = ""
    warn_versions(domains, rec, label)
    for d in domains:
        try:
            want, todo, skipped = differing(d, store, rec, label)
        except Unreadable as e:
            bad = 1
            say(RED, f"✗ {d['name']}: {e}, left as it is")
            continue
        if skipped:
            say(YELLOW, f"! {d['name']}: left out tiles not on this Mac: {', '.join(skipped)}")
        if not todo:
            continue
        whole = store.read(d)
        if not backup:
            stem = os.path.join(store.dir or HOME, time.strftime(".macos-settings-backup-%Y%m%d-%H%M%S"))
            backup, n = stem, 1
            while os.path.exists(backup):  # a second run in the same second keeps the first one's backup
                n += 1
                backup = f"{stem}-{n}"
            os.makedirs(backup)
        with open(os.path.join(backup, f"{d['name']}.plist"), "wb") as f:
            plistlib.dump(whole, f, fmt=plistlib.FMT_BINARY)
        ok, err = store.write(d, local(todo))  # defaults import merges: other keys stay
        left = differing(d, store, rec, label)[1]
        if not ok or left:
            bad = 1
            say(RED, f"✗ {d['name']}: still different: {', '.join(sorted(left)) or err}")
            continue
        total += len(todo)
        say(GREEN, f"✓ {d['name']}: set {', '.join(sorted(todo))}")
        restart.update(d.get("restart", []))
        if d.get("restart"):
            written.append(d)
    if not total and not bad:
        say(GREEN, "✓ macOS settings already match the repo")
    if backup:
        print(f"  the settings before this import are in {backup}")
    if restart and not store.dir:
        for proc in sorted(restart):
            subprocess.run(["killall", proc], capture_output=True)
        if os.access(ACTIVATE, os.X_OK):
            subprocess.run([ACTIVATE, "-u"], capture_output=True)
        else:
            say(YELLOW, f"! {ACTIVATE} is missing: some changes apply only at the next login")
        settle(sorted(restart))
        print(f"  restarted {', '.join(sorted(restart))}; trackpad, mouse and input source changes "
              "take full effect at the next login")
        bad |= recheck(written, store, rec, label)
    return bad


def settle(procs, timeout=20):
    """Wait until each restarted process runs again, then a little longer for it to write its prefs."""
    end = time.time() + timeout
    for proc in procs:
        while time.time() < end and subprocess.run(["pgrep", "-xq", proc]).returncode != 0:
            time.sleep(0.5)
        if subprocess.run(["pgrep", "-xq", proc]).returncode != 0:
            say(YELLOW, f"! {proc} has not come back after {timeout}s")
    time.sleep(3)


def recheck(written, store, rec, label):
    """Name the values a restarted process wrote back over the import (exit 1 if any)."""
    bad = 0
    for d in written:
        left = differing(d, store, rec, label)[1]
        if left:
            bad = 1
            say(RED, f"✗ {d['name']}: changed back after the restart: {', '.join(sorted(left))}. "
                     "This macOS may not accept the recorded value; export here to record what it keeps.")
    return bad


def check(domains, store, rec, label):
    bad = 0
    warn_versions(domains, rec, label)
    for d in domains:
        try:
            _, todo, skipped = differing(d, store, rec, label)
        except Unreadable as e:
            bad = 1
            print(f"differs here: {d['name']} unreadable ({e})")
            continue
        if skipped:
            print(f"! {d['name']}: tiles not on this Mac, left out: {', '.join(skipped)}")
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
    global MACOS
    MACOS = opt("--macos") or macos_major()
    return {"export": export, "import": import_, "check": check}[argv[0]](load_domains(), store, rec, label)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
