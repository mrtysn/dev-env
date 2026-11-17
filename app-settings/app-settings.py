#!/usr/bin/python3 -I
"""Carry chosen apps' settings between machines; apps.json says which apps and which keys.

    app-settings.py export   copy the allowlisted settings of this machine into app-settings/
    app-settings.py import   load them into this machine, for apps that are installed
    app-settings.py check    say per app whether this machine matches the repo (exit 1 if not)

Both directions write only what differs, so a second run changes nothing. Import never
writes to a running app (it would overwrite the change when it quits): it names the app to
quit and moves on. Export refuses any carried value that holds the home folder's path or an
email address, since this repo is public.

Options: --home DIR (default: $HOME), --ignore-running (tests, where HOME is a sandbox).
"""
import json, os, plistlib, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
GREEN, YELLOW, RED, NC = "\033[0;32m", "\033[1;33m", "\033[0;31m", "\033[0m"
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def say(colour, text):
    print(f"{colour}{text}{NC}")


def load_apps():
    with open(os.path.join(HERE, "apps.json")) as f:
        return json.load(f)["apps"]


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
                if write_if_changed(os.path.join(HERE, name, fn), data):
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
        repo_file = os.path.join(HERE, f"{name}.plist")
        if os.path.exists(repo_file):
            with open(repo_file, "rb") as f:
                stored = plistlib.load(f)
            for k, v in kept.items():
                if k in stored and same(stored[k], v):
                    kept[k] = stored[k]
        data = plistlib.dumps(kept, fmt=plistlib.FMT_XML, sort_keys=True)
        if write_if_changed(os.path.join(HERE, f"{name}.plist"), data):
            changed += 1
            say(GREEN, f"✓ exported {name} ({len(kept)} keys)")
    if not changed:
        say(GREEN, "✓ app settings already match the repo")
    return 0


def status(a, home):
    """(state, detail): state is 'absent', 'match' or 'differs'."""
    if not os.path.isdir(a["app"]):
        return "absent", None
    if "files" in a:
        diff = []
        for fn in a["files"]:
            repo = os.path.join(HERE, a["name"], fn)
            if not os.path.exists(repo):
                continue
            live = os.path.join(home, a["dir"], fn)
            with open(repo, "rb") as f:
                want = f.read()
            have = open(live, "rb").read() if os.path.exists(live) else None
            if have != want:
                diff.append(fn)
        return ("differs", diff) if diff else ("match", None)
    repo = os.path.join(HERE, f"{a['name']}.plist")
    if not os.path.exists(repo):
        return "match", None
    with open(repo, "rb") as f:
        want = plistlib.load(f)
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
            shutil.copyfile(os.path.join(HERE, name, fn), live)
        say(GREEN, f"✓ {name}: loaded {', '.join(diff)}")
        return
    path = os.path.join(home, a["file"])
    with open(os.path.join(HERE, f"{name}.plist"), "rb") as f:
        want = plistlib.load(f)
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
    home = os.path.expanduser("~")
    if "--home" in argv:
        home = os.path.realpath(argv[argv.index("--home") + 1])  # defaults treats /var and /private/var as two files
    apps = load_apps()
    if argv[0] == "export":
        return export(apps, home)
    if argv[0] == "import":
        return import_(apps, home, "--ignore-running" in argv)
    return check(apps, home)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
