#!/usr/bin/python3 -I
"""Carry chosen apps' settings between machines; apps.json says which apps and which keys.

    app-settings.py export   copy the allowlisted settings of this machine into app-settings/
    app-settings.py import   load them into this machine, for apps that are installed
    app-settings.py check    say per app whether this machine matches the repo (exit 1 if not)

Both directions write only what differs, so a second run changes nothing. Import never
writes to a running app (it would overwrite the change when it quits): it names the app to
quit and moves on. Export refuses any carried value that holds the home folder's path or an
email address, since this repo is public.

Per machine: the machine apps.json names as "owner" writes the shared copies. Any other machine
(--label, from machine-label.sh) writes only where it differs: <app>.<label>.plist with the
differing keys, and for a whole file <stem>.<label><ext> holding the differing keys of a JSON
settings file, or the whole file when it is not one (a keymap). Import lays a machine's overlay
over the shared copy, on that machine only.

Options: --label LABEL (this machine's label), --home DIR (default: $HOME), --ignore-running
(tests, where HOME is a sandbox), --repo DIR and --apps FILE (tests: where the records and the
app list live, default this folder).
"""
import json, os, plistlib, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = HERE                                 # where the records live (--repo)
APPS = os.path.join(HERE, "apps.json")      # --apps
LABEL = OWNER = ""                          # this machine's label (--label); the shared copies' machine
GREEN, YELLOW, RED, NC = "\033[0;32m", "\033[1;33m", "\033[0;31m", "\033[0m"
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def say(colour, text):
    print(f"{colour}{text}{NC}")


def load_apps():
    global OWNER
    with open(APPS) as f:
        cfg = json.load(f)
    OWNER = cfg.get("owner", "")
    return cfg["apps"]


def overlaid():
    """Whether this machine keeps its differences in overlays rather than in the shared copies."""
    return bool(LABEL) and LABEL != OWNER


def plist_overlay_path(a):
    return os.path.join(REPO, f"{a['name']}.{LABEL}.plist")


def file_overlay_path(a, fn):
    stem, ext = os.path.splitext(fn)
    return os.path.join(REPO, a["name"], f"{stem}.{LABEL}{ext}")


def parse_loose(data):
    """A Sublime-style JSON file (comments and trailing commas allowed) as data; None if it is not one."""
    try:
        text = data.decode()
    except UnicodeDecodeError:
        return None
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            in_str = c != '"'
            i += 1
            continue
        if c == '"':
            in_str = True
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        elif c == ",":
            j = i + 1
            while j < n:  # past blanks and comments
                if text[j] in " \t\r\n":
                    j += 1
                elif text.startswith("//", j):
                    k = text.find("\n", j)
                    j = n if k < 0 else k
                elif text.startswith("/*", j):
                    k = text.find("*/", j + 2)
                    j = n if k < 0 else k + 2
                else:
                    break
            if j < n and text[j] in "}]":  # a trailing comma
                i += 1
                continue
        out.append(c)
        i += 1
    try:
        return json.loads("".join(out))
    except ValueError:
        return None


def read_bytes(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def file_want(a, fn):
    """What this machine should hold for a carried file: ("bytes", data) or ("data", dict); None if the
    repo has no copy."""
    shared = read_bytes(os.path.join(REPO, a["name"], fn))
    if shared is None:
        return None
    if overlaid():
        mine = read_bytes(file_overlay_path(a, fn))
        if mine is not None:
            base, patch = parse_loose(shared), parse_loose(mine)
            if isinstance(base, dict) and isinstance(patch, dict):
                base.update(patch)
                return ("data", base)
            return ("bytes", mine)
    return ("bytes", shared)


def file_matches(want, have):
    """A file matches when its bytes are the same, or both are JSON settings holding the same values."""
    if have is None:
        return False
    kind, value = want
    if kind == "bytes" and have == value:
        return True
    if kind == "bytes":
        value = parse_loose(value)
        if value is None:
            return False
    return parse_loose(have) == value


def plist_want(a):
    """The shared keys with this machine's overlay laid over them."""
    want = {}
    shared = os.path.join(REPO, f"{a['name']}.plist")
    if os.path.exists(shared):
        with open(shared, "rb") as f:
            want = plistlib.load(f)
    if overlaid() and os.path.exists(plist_overlay_path(a)):
        with open(plist_overlay_path(a), "rb") as f:
            want.update(plistlib.load(f))
    return want


def remove_overlay(path, what):
    if not os.path.exists(path):
        return 0
    os.remove(path)
    say(GREEN, f"✓ {what}: {LABEL} matches the shared copy now, removed its overlay")
    return 1


def wrong_file(a):
    """Why a plist app's `file` is not the one the installed app reads, or None. An app reads the
    preferences named after its bundle id (a sandboxed one inside its container), so a file whose
    path lacks that id is written for nothing: the app keeps its defaults and nothing says so."""
    info = os.path.join(a["app"], "Contents", "Info.plist")
    if "file" not in a or not os.path.exists(info):
        return None
    with open(info, "rb") as f:
        bid = plistlib.load(f).get("CFBundleIdentifier", "")
    if bid and bid not in a["file"]:
        return f"its file is not under its bundle id {bid}: fix the path in apps.json"
    return None


def read_plist(path):
    """The live values, through cfprefsd (a file read can miss unsaved changes)."""
    if not os.path.exists(path):
        return {}
    out = subprocess.run(["defaults", "export", path, "-"], capture_output=True)
    live = plistlib.loads(out.stdout) if out.returncode == 0 and out.stdout else {}
    if not live and os.path.getsize(path) > 0:
        # defaults answers empty for a group container outside the real home: read the file.
        with open(path, "rb") as f:
            return plistlib.load(f)
    return live


def leaks(value, home):
    text = repr(value)
    return home in text or EMAIL.search(text) is not None


def is_running(app):
    """Any process running an executable from the bundle, helpers and login items included.
    A helper's command line can be just its bundle ID, so pgrep -f on the path misses it."""
    if subprocess.run(["pgrep", "-f", f"{app}/Contents/"], capture_output=True).returncode == 0:
        return True
    exes = []
    for root, dirs, files in os.walk(os.path.join(app, "Contents")):
        if os.path.basename(root) == "MacOS":
            exes += [os.path.join(root, f) for f in files if os.access(os.path.join(root, f), os.X_OK)]
    return bool(exes) and subprocess.run(["lsof", "-t", "--", *exes], capture_output=True).stdout.strip() != b""


def write_if_changed(path, data):
    if os.path.exists(path):
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return True


def same(a, b):
    """Equal values; a string holding JSON compares as data, since apps (Rectangle) rewrite such
    a string with its entries reordered, which is the same setting."""
    if a == b:
        return True
    # Mos keeps JSON in data (bytes) values rather than strings; compare those as data too.
    if isinstance(a, bytes) and isinstance(b, bytes):
        try:
            a, b = a.decode(), b.decode()
        except UnicodeDecodeError:
            return False
    if isinstance(a, str) and isinstance(b, str):
        try:
            return unordered(json.loads(a)) == unordered(json.loads(b))
        except ValueError:
            return False
    return False


def unordered(x):
    """A flat [key, value, key, value, ...] list, which is how Swift encodes a dictionary, as a
    dict, so the same pairs in another order compare equal; lists and dicts inside likewise."""
    if isinstance(x, dict):
        return {k: unordered(v) for k, v in x.items()}
    if isinstance(x, list):
        keys = x[0::2]
        if x and len(x) % 2 == 0 and all(isinstance(k, (int, str)) for k in keys) and len(set(keys)) == len(keys):
            return {k: unordered(v) for k, v in zip(keys, x[1::2])}
        return [unordered(v) for v in x]
    return x


def export(apps, home):
    changed = 0
    for a in apps:
        name = a["name"]
        if "files" in a:
            src_dir = os.path.join(home, a["dir"])
            for fn in a["files"]:
                src = os.path.join(src_dir, fn)
                if not os.path.exists(src):
                    continue
                with open(src, "rb") as f:
                    data = f.read()
                if home.encode() in data or EMAIL.search(data.decode("utf-8", "replace")):
                    say(RED, f"✗ {name}/{fn} holds a home path or an address: not exported, fix the live file")
                    continue
                shared_path = os.path.join(REPO, name, fn)
                if overlaid() and os.path.exists(shared_path):
                    changed += export_file_overlay(a, fn, read_bytes(shared_path), data)
                    continue
                if write_if_changed(shared_path, data):
                    changed += 1
                    say(GREEN, f"✓ exported {name}/{fn}")
            continue
        src = os.path.join(home, a["file"])
        if not os.path.exists(src):
            say(YELLOW, f"! {name}: no settings on this machine, skipped")
            continue
        allow = re.compile(a["keys"])
        live = read_plist(src)
        kept = {}
        for k, v in live.items():
            if not allow.fullmatch(k):
                continue
            if leaks(v, home):
                say(RED, f"✗ {name}: key {k} holds a home path or an address, not exported")
                continue
            kept[k] = v
        # Keep the repo's copy of a value that is only reordered, so an export writes nothing.
        repo_file = os.path.join(REPO, f"{name}.plist")
        if overlaid() and os.path.exists(repo_file):
            with open(repo_file, "rb") as f:
                stored = plistlib.load(f)
            diff = {k: v for k, v in kept.items() if not same(stored.get(k), v)}
            path = plist_overlay_path(a)
            if os.path.exists(path):  # keep a reordered value as stored, as for the shared copy
                with open(path, "rb") as f:
                    before = plistlib.load(f)
                diff = {k: before[k] if k in before and same(before[k], v) else v for k, v in diff.items()}
            if not diff:
                changed += remove_overlay(path, name)
            elif write_if_changed(path, plistlib.dumps(diff, fmt=plistlib.FMT_XML, sort_keys=True)):
                changed += 1
                say(GREEN, f"✓ exported {name}: {len(diff)} keys where {LABEL} differs")
            continue
        if os.path.exists(repo_file):
            with open(repo_file, "rb") as f:
                stored = plistlib.load(f)
            for k, v in kept.items():
                if k in stored and same(stored[k], v):
                    kept[k] = stored[k]
        data = plistlib.dumps(kept, fmt=plistlib.FMT_XML, sort_keys=True)
        if write_if_changed(repo_file, data):
            changed += 1
            say(GREEN, f"✓ exported {name} ({len(kept)} keys)")
    if not changed:
        say(GREEN, "✓ app settings already match the repo")
    return 0


def export_file_overlay(a, fn, shared, live):
    """Write this machine's difference from a shared file; returns 1 when the repo changed."""
    what, path = f"{a['name']}/{fn}", file_overlay_path(a, fn)
    if file_matches(("bytes", shared), live):
        return remove_overlay(path, what)
    base, mine = parse_loose(shared), parse_loose(live)
    if isinstance(base, dict) and isinstance(mine, dict):
        diff = {k: v for k, v in mine.items() if base.get(k) != v}
        gone = sorted(k for k in base if k not in mine)
        if gone:
            say(YELLOW, f"! {what}: {LABEL} lacks {', '.join(gone)}; an overlay only sets keys, so import "
                        "brings them back. Set them here instead of deleting them")
        if not diff:
            return remove_overlay(path, what)
        data, detail = (json.dumps(diff, indent=4, sort_keys=True) + "\n").encode(), f"{len(diff)} keys"
    else:
        data, detail = live, "the whole file"
    if not write_if_changed(path, data):
        return 0
    say(GREEN, f"✓ exported {what}: {detail} where {LABEL} differs")
    return 1


def status(a, home):
    """(state, detail): state is 'absent', 'match' or 'differs'."""
    if not os.path.isdir(a["app"]):
        return "absent", None
    if "files" in a:
        diff = []
        for fn in a["files"]:
            want = file_want(a, fn)
            if want is not None and not file_matches(want, read_bytes(os.path.join(home, a["dir"], fn))):
                diff.append(fn)
        return ("differs", diff) if diff else ("match", None)
    want = plist_want(a)
    if not want:
        return "match", None
    have = read_plist(os.path.join(home, a["file"]))
    diff = sorted(k for k, v in want.items() if not same(have.get(k), v))
    return ("differs", diff) if diff else ("match", None)


def refused(a, e):
    """Name what macOS wants when it refuses an app's group container."""
    if os.path.exists(os.path.dirname(e.filename or "")):
        # The container exists, so the app made it; the shell's app is what is refused.
        return (f"! {a['name']}: macOS refused {e.filename}: allow this terminal to access data "
                "from other apps (System Settings > Privacy & Security), then re-run this step")
    # macOS lets only the app itself create its group container: an app that was
    # installed but never opened has none, and makedirs there is refused.
    return (f"! {a['name']}: macOS refused {e.filename}: open {os.path.basename(a['app'])} once, "
            "quit it, then re-run this step")


def import_(apps, home, ignore_running):
    for a in apps:
        name = a["name"]
        try:
            state, diff = status(a, home)
        except PermissionError as e:
            say(YELLOW, refused(a, e))
            continue
        if state == "absent":
            say(YELLOW, f"! {name}: not installed, skipped")
            continue
        if state == "match":
            say(GREEN, f"✓ {name} settings already match")
            continue
        if not ignore_running and is_running(a["app"]):
            say(YELLOW, f"! {name} is running: quit it, then re-run this step ({len(diff)} to load)")
            continue
        try:
            load(a, home, diff)
        except PermissionError as e:
            say(YELLOW, refused(a, e))
    return 0


def load(a, home, diff):
    name = a["name"]
    if "files" in a:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        for fn in diff:
            live = os.path.join(home, a["dir"], fn)
            os.makedirs(os.path.dirname(live), exist_ok=True)
            if os.path.exists(live):
                shutil.copy2(live, f"{live}.backup-{stamp}")
            kind, value = file_want(a, fn)
            data = value if kind == "bytes" else (json.dumps(value, indent=4, sort_keys=True) + "\n").encode()
            with open(live, "wb") as f:
                f.write(data)
        say(GREEN, f"✓ {name}: loaded {', '.join(diff)}")
        return
    path = os.path.join(home, a["file"])
    want = plist_want(a)
    merged = read_plist(path)
    merged.update(want)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = subprocess.run(["defaults", "import", path, "-"],
                         input=plistlib.dumps(merged, fmt=plistlib.FMT_BINARY), capture_output=True)
    if out.returncode != 0 or status(a, home)[0] != "match":
        # `defaults import` exits 0 yet writes nothing into some paths (a group container
        # outside the real home). The app is quit here, so the file itself is safe to write.
        with open(path, "wb") as f:
            plistlib.dump(merged, f, fmt=plistlib.FMT_BINARY)
        subprocess.run(["killall", "-u", str(os.getuid()), "cfprefsd"], capture_output=True)
        if status(a, home)[0] != "match":
            say(RED, f"✗ {name}: could not write {path}")
            return
    say(GREEN, f"✓ {name}: loaded {len(diff)} settings")


def check(apps, home):
    bad = 0
    for a in apps:
        try:
            state, diff = status(a, home)
        except PermissionError as e:
            bad = 1
            print(f"{a['name']}: unreadable ({e.filename}: macOS refused this terminal)")
            continue
        if state == "differs":
            bad = 1
            print(f"{a['name']}: differs ({', '.join(diff[:6])}{'…' if len(diff) > 6 else ''})")
        else:
            print(f"{a['name']}: {'not installed' if state == 'absent' else 'matches'}")
    return bad


def main(argv):
    if not argv or argv[0] not in ("export", "import", "check"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    global REPO, APPS, LABEL
    home = os.path.expanduser("~")
    def opt(name):
        return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None
    REPO = os.path.realpath(opt("--repo") or REPO)
    APPS = opt("--apps") or APPS
    LABEL = opt("--label") or ""
    if "--home" in argv:
        home = os.path.realpath(argv[argv.index("--home") + 1])  # defaults treats /var and /private/var as two files
    apps, refused = [], 0
    for a in load_apps():
        why = wrong_file(a)
        if why:
            say(RED, f"✗ {a['name']}: {why}")
            refused = 1
        else:
            apps.append(a)
    if argv[0] == "export":
        return export(apps, home) or refused
    if argv[0] == "import":
        return import_(apps, home, "--ignore-running" in argv) or refused
    return check(apps, home) or refused


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
