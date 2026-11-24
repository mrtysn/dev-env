#!/usr/bin/python3 -I
"""Keep the asdf runtime pins (~/.tool-versions) in step across machines: the newest version wins.

    sync-tool-versions.py check    list the runtimes import would set here (exit 1 if any)
    sync-tool-versions.py import   install them: a runtime the repo has newer, or this Mac lacks
    sync-tool-versions.py export   raise the repo's pins to the runtimes this Mac has newer

asdf/tool-versions is the one shared record. A Mac's pins move only up: import never installs an
older version than this Mac runs, and export never lowers a pin, so `update-all` (which bumps this
Mac to the newest releases) then export.sh on either Mac moves the repo up, and the other Mac's
next import follows. A pin that is not a version (java `system`) is set only where the tool is not
pinned yet. A tool machine-keeps.json lists for this machine ("asdf/tool-versions") keeps this Mac's
own pin, recorded in asdf/tool-versions.<label>, exactly, up or down.

To move a runtime back down, edit asdf/tool-versions and run import --allow-downgrade.
Options: --label LABEL (this machine's label); --allow-downgrade; --live FILE (default
~/.tool-versions), --record DIR (default this folder) and ASDF=<command> (tests).
"""
import os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
import sync_state  # noqa: E402

GREEN, YELLOW, RED, NC = "\033[0;32m", "\033[1;33m", "\033[0;31m", "\033[0m"
ASDF = os.environ.get("ASDF", "asdf")


def say(colour, text):
    print(f"{colour}{text}{NC}")


def parse(path):
    """{tool: version} in file order; the first version of a line is its pin."""
    pins = {}
    if not os.path.exists(path):
        return pins
    with open(path) as f:
        for line in f:
            parts = line.split("#", 1)[0].split()
            if len(parts) >= 2:
                pins[parts[0]] = parts[1]
    return pins


def dump(path, pins):
    text = "".join(f"{t} {v}\n" for t, v in pins.items())
    if os.path.exists(path) and open(path).read() == text:
        return False
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def key(v):
    """A sortable form of a version (24.22.3, 3.12.16, 10.0.400), or None for one that is not (system)."""
    if not re.match(r"^v?\d", v):
        return None
    return tuple(int(p) if p.isdigit() else -1 for p in re.split(r"[.\-+]", v.lstrip("v")))


def newer(a, b):
    """True when version a is newer than version b; False when either is not a version."""
    ka, kb = key(a), key(b)
    return ka is not None and kb is not None and ka > kb


class Repo:
    def __init__(self, record_dir, label):
        self.shared_path = os.path.join(record_dir, "tool-versions")
        self.own_path = os.path.join(record_dir, f"tool-versions.{label}") if label else ""
        self.keep = sync_state.kept("asdf", "tool-versions", label)

    def wanted(self):
        """(shared pins, this machine's kept pins)."""
        own = {t: v for t, v in parse(self.own_path).items() if t in self.keep} if self.own_path else {}
        return parse(self.shared_path), own


def plan(repo, live, allow_down=False):
    """[(tool, have, want)] import would set."""
    shared, own = repo.wanted()
    todo = []
    for tool, want in {**shared, **own}.items():
        have = live.get(tool)
        if tool in own or allow_down:
            if have != want:
                todo.append((tool, have, want))
        elif have is None or newer(want, have):
            todo.append((tool, have, want))
    return todo


def check(repo, live_path, allow_down):
    todo = plan(repo, parse(live_path), allow_down)
    for tool, have, want in todo:
        print(f"differs here: {tool} {have or '(not pinned)'} -> {want}")
    if not todo:
        print("✓ asdf pins are at or above the repo's")
    return 1 if todo else 0


def run(*args):
    return subprocess.run([ASDF, *args], cwd=os.path.expanduser("~"), capture_output=True, text=True)


def import_(repo, live_path, allow_down):
    todo = plan(repo, parse(live_path), allow_down)
    if not todo:
        say(GREEN, "✓ asdf pins are at or above the repo's")
        sync_state.mark(repo.shared_path)
        return 0
    if os.path.exists(live_path):
        shutil.copy2(live_path, f"{live_path}.backup-{time.strftime('%Y%m%d-%H%M%S')}")
    plugins = set(run("plugin", "list").stdout.split())
    live, bad = parse(live_path), 0
    for tool, have, want in todo:
        if tool not in plugins:
            out = run("plugin", "add", tool)
            if out.returncode != 0:
                say(RED, f"✗ asdf plugin {tool} could not be added: {out.stderr.strip()}")
                bad = 1
                continue
        if key(want) is not None:
            print(f"→ installing {tool} {want} (a runtime build can take a while)")
            out = run("install", tool, want)
            if out.returncode != 0:
                say(RED, f"✗ {tool} {want} failed to install; pin left at {have or 'none'}: {out.stderr.strip()[-300:]}")
                bad = 1
                continue
        live[tool] = want
        dump(live_path, live)  # after each tool, so a later failure keeps the ones that worked
        say(GREEN, f"✓ {tool} {have or '(not pinned)'} -> {want}")
    if not bad:
        sync_state.mark(repo.shared_path)
    return bad


def export(repo, live_path):
    live = parse(live_path)
    if not live:
        say(YELLOW, f"! no pins in {live_path}, nothing exported")
        return 0
    shared, own = repo.wanted()
    mine = {t: v for t, v in live.items() if t in repo.keep}
    if repo.own_path:
        if mine:
            if dump(repo.own_path, mine):
                say(GREEN, f"✓ exported this machine's own pins: {' '.join(f'{t} {v}' for t, v in mine.items())}")
        elif os.path.exists(repo.own_path):
            os.remove(repo.own_path)
    new, raised = dict(shared), []
    for tool, have in live.items():
        if tool in repo.keep:
            continue
        if tool not in new or newer(have, new[tool]):
            raised.append(f"{tool} {new.get(tool, '(new)')} -> {have}")
            new[tool] = have
    if not raised:
        say(GREEN, "✓ the repo's asdf pins are at or above this Mac's")
        return 0
    dump(repo.shared_path, new)
    sync_state.mark(repo.shared_path)
    say(GREEN, f"✓ raised asdf pins: {', '.join(raised)}")
    return 0


def main(argv):
    if not argv or argv[0] not in ("check", "import", "export"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    def opt(name, default=""):
        return argv[argv.index(name) + 1] if name in argv else default
    repo = Repo(opt("--record") or HERE, opt("--label"))
    live = opt("--live") or os.path.expanduser("~/.tool-versions")
    down = "--allow-downgrade" in argv
    if argv[0] == "export":
        return export(repo, live)
    return (check if argv[0] == "check" else import_)(repo, live, down)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
