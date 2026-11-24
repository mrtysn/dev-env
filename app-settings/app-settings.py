#!/usr/bin/python3 -I
"""Carry chosen apps' settings between machines; apps.json says which apps and which keys.

    app-settings.py export   copy the allowlisted settings of this machine into app-settings/
    app-settings.py import   load them into this machine, for apps that are installed
    app-settings.py check    say per app whether this machine matches the repo (exit 1 if not)

Both directions write only what differs, so a second run changes nothing. Import never
writes to a running app (it would overwrite the change when it quits): it names the app to
quit and moves on. Export refuses any carried value that holds the home folder's path or an
email address, since this repo is public.

Shared by default: every machine syncs to one copy per app, and an export on any machine updates
it; a key the exporting Mac has never written keeps its recorded value. Only what machine-keeps.json
lists for this machine (--label, from machine-label.sh) goes to its own file: keys of an app in
<app>.<label>.plist, keys of a JSON settings file in <stem>.<label><ext>, or a whole file ("*").
Import lays those over the shared copy on that machine only. Export refuses a copy that changed since
this Mac last imported it (lib/sync_state.py); --force overrides.

Options: --label LABEL (this machine's label), --force, --home DIR (default: $HOME), --ignore-running
(tests, where HOME is a sandbox), --repo DIR and --apps FILE (tests: where the records and the
app list live, default this folder).
"""
import json, os, plistlib, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
import sync_state  # noqa: E402
FORCE = False  # --force: export over a copy this Mac is behind on
REPO = HERE                                 # where the records live (--repo)
APPS = os.path.join(HERE, "apps.json")      # --apps
LABEL = ""                                  # this machine's label (--label)
GREEN, YELLOW, RED, NC = "\033[0;32m", "\033[1;33m", "\033[0;31m", "\033[0m"
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def say(colour, text):
    print(f"{colour}{text}{NC}")


def load_apps():
    with open(APPS) as f:
        return json.load(f)["apps"]


def keeps(record):
    """What this machine keeps for itself in an app (keys) or a carried file (keys, or "*")."""
    return sync_state.kept("app-settings", record, LABEL)


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
    keep = keeps(f"{a['name']}/{fn}")
    mine = read_bytes(file_overlay_path(a, fn)) if keep else None
    if mine is not None and "*" in keep:
        return ("bytes", mine)
    if shared is None:
        return None
    if mine is not None:
        base, patch = parse_loose(shared), parse_loose(mine)
        if isinstance(base, dict) and isinstance(patch, dict):
            base.update({k: v for k, v in patch.items() if k in keep})
            return ("data", base)
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
    keep = keeps(a["name"])
    if keep and os.path.exists(plist_overlay_path(a)):
        with open(plist_overlay_path(a), "rb") as f:
            want.update({k: v for k, v in plistlib.load(f).items() if k in keep})
    return want


def remove_overlay(path, what):
    if not os.path.exists(path):
        return 0
    os.remove(path)
    say(GREEN, f"✓ {what}: {LABEL} keeps nothing of its own now, removed {os.path.basename(path)}")
    return 1


def write_shared(path, data, what):
    """Write a shared copy unless this Mac is behind on it; (repo changed, refused)."""
    if os.path.exists(path) and read_bytes(path) == data:
        return 0, 0
    if sync_state.behind(path) and not FORCE:
        say(RED, "✗ " + sync_state.refusal(what, 16))
        return 0, 1
    write_if_changed(path, data)
    sync_state.mark(path)
    say(GREEN, f"✓ exported {what}")
    return 1, 0


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
    changed = refused = 0
    for a in apps:
        name = a["name"]
        if "files" in a:
            for fn in a["files"]:
                src = os.path.join(home, a["dir"], fn)
                if not os.path.exists(src):
                    continue
                data = read_bytes(src)
                if home.encode() in data or EMAIL.search(data.decode("utf-8", "replace")):
                    say(RED, f"✗ {name}/{fn} holds a home path or an address: not exported, fix the live file")
                    continue
                c, r = export_file(a, fn, data)
                changed, refused = changed + c, refused | r
            continue
        src = os.path.join(home, a["file"])
        if not os.path.exists(src):
            say(YELLOW, f"! {name}: no settings on this machine, skipped")
            continue
        allow = re.compile(a["keys"])
        live = {}
        for k, v in read_plist(src).items():
            if not allow.fullmatch(k):
                continue
            if leaks(v, home):
                say(RED, f"✗ {name}: key {k} holds a home path or an address, not exported")
                continue
            live[k] = v
        keep = keeps(name)
        changed += export_mine(plist_overlay_path(a), name,
                               plistlib.dumps({k: v for k, v in live.items() if k in keep}, fmt=plistlib.FMT_XML, sort_keys=True)
                               if any(k in keep for k in live) else None)
        repo_file = os.path.join(REPO, f"{name}.plist")
        stored = {}
        if os.path.exists(repo_file):
            with open(repo_file, "rb") as f:
                stored = plistlib.load(f)
        new = dict(stored)  # a key this Mac never wrote, or keeps for itself, stays as recorded
        for k, v in live.items():
            if k not in keep:
                # Keep the repo's copy of a value that is only reordered, so an export writes nothing.
                new[k] = stored[k] if k in stored and same(stored[k], v) else v
        if new == stored and os.path.exists(repo_file):
            continue
        c, r = write_shared(repo_file, plistlib.dumps(new, fmt=plistlib.FMT_XML, sort_keys=True), f"{name} ({len(new)} keys)")
        changed, refused = changed + c, refused | r
    if not changed and not refused:
        say(GREEN, "✓ app settings already match the repo")
    return refused


def export_mine(path, what, data):
    """Write what this machine keeps for itself (None: nothing); 1 when the repo changed."""
    if data is None:
        return remove_overlay(path, what)
    if write_if_changed(path, data):
        say(GREEN, f"✓ exported {what}: what {LABEL} keeps for itself")
        return 1
    return 0


def export_file(a, fn, live):
    """Export one carried file: the shared copy, and this machine's kept part. (changed, refused)."""
    what, shared_path = f"{a['name']}/{fn}", os.path.join(REPO, a["name"], fn)
    keep = keeps(what)
    if "*" in keep:
        return export_mine(file_overlay_path(a, fn), what, live), 0
    shared = read_bytes(shared_path)
    mine, base = parse_loose(live), parse_loose(shared) if shared is not None else None
    if keep and isinstance(mine, dict):
        changed = export_mine(file_overlay_path(a, fn), what,
                              (json.dumps({k: v for k, v in mine.items() if k in keep}, indent=4, sort_keys=True) + "\n").encode()
                              if any(k in keep for k in mine) else None)
        rest = dict(base) if isinstance(base, dict) else {}
        rest.update({k: v for k, v in mine.items() if k not in keep})
        if isinstance(base, dict) and rest == base:
            return changed, 0
        c, r = write_shared(shared_path, (json.dumps(rest, indent=4, sort_keys=True) + "\n").encode(), what)
        return changed + c, r
    if shared is not None and file_matches(("bytes", shared), live):
        return 0, 0
    return write_shared(shared_path, live, what)


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
            mark_shared(a)
            say(GREEN, f"✓ {name} settings already match")
            continue
        if not ignore_running and is_running(a["app"]):
            say(YELLOW, f"! {name} is running: quit it, then re-run this step ({len(diff)} to load)")
            continue
        try:
            load(a, home, diff)
            if status(a, home)[0] == "match":
                mark_shared(a)
        except PermissionError as e:
            say(YELLOW, refused(a, e))
    return 0


def mark_shared(a):
    """Record that this machine holds an app's shared copies as they are now."""
    paths = [os.path.join(REPO, a["name"], fn) for fn in a["files"]] if "files" in a else [os.path.join(REPO, f"{a['name']}.plist")]
    for path in paths:
        sync_state.mark(path)


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
    global FORCE
    FORCE = "--force" in argv
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
