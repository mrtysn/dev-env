"""What the settings tools (app-settings.py, symbolic-hotkeys.py, system-settings.py) share.

Every machine syncs to one shared record per app or domain. Two things are per machine:

Keeps: machine-keeps.json (committed) names, per machine label, the keys that machine keeps for
itself. Only those go to its <record>.<label> file, on export and import alike; every other key
is shared, whichever machine exports it. Nothing becomes per machine unless it is listed there.

Applied: ~/.local/state/dev-env/applied.json (outside git, per machine) holds the hash of each
shared record as this machine last imported or exported it. Export refuses to overwrite a record
that changed since then (another machine exported it, and this one has not imported it yet), so a
machine that is behind cannot push stale settings over the other's. --force overrides.

DEV_ENV_KEEPS and DEV_ENV_STATE_DIR point both elsewhere (tests).
"""
import hashlib, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _keeps_file():
    return os.environ.get("DEV_ENV_KEEPS") or os.path.join(ROOT, "machine-keeps.json")


def _state_file():
    base = os.environ.get("DEV_ENV_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "dev-env")
    return os.path.join(base, "applied.json")


def kept(tool, record, label):
    """The keys machine `label` keeps for itself in `tool`'s `record` ("*" means the whole file)."""
    if not label or not os.path.exists(_keeps_file()):
        return set()
    with open(_keeps_file()) as f:
        return set(json.load(f).get(label, {}).get(f"{tool}/{record}", []))


def digest(path):
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _load():
    p = _state_file()
    if not os.path.exists(p):
        return {}
    with open(p) as f:
        return json.load(f)


def behind(path):
    """True when the shared record at `path` changed since this machine last imported or exported it,
    or this machine never has."""
    return os.path.exists(path) and _load().get(os.path.realpath(path)) != digest(path)


def mark(path):
    """Record that this machine now holds the shared record at `path` as it is."""
    state = _load()
    key, value = os.path.realpath(path), digest(path)
    if state.get(key) == value:
        return
    state[key] = value
    p = _state_file()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, p)


def refusal(what, step):
    return (f"{what}: the repo's copy changed since this Mac last imported it, so exporting would put "
            f"back older values. Import first (./import.sh --steps {step}), or export --force to overwrite it")
