# Which iTerm2 top-level preference keys export.sh keeps out of the (public) repo.
# One definition for export.sh, which drops them, and import.sh --check, which must not
# report them as unexported. Run with exec() inside those scripts' embedded python.
import re

# Machine-local / volatile state that must never reach the repo.
# Spaces are written as [ ] — a trailing "\ " before a newline escapes the newline
# in re.VERBOSE, which silently disables the pattern.
DENY = re.compile(r"""^(
      NoSync
    | NSWindow[ ]Frame[ ]
    | NSSplitView[ ]
    | NSToolbar[ ]
    | SU[A-Z]
    | NSNavLastRootDirectory$
    | NSNavPanelExpandedSize
    | NeverWarnAboutShortLivedSessions_
    | findMode_iTerm$
    | kCPK
    | iTerm\ Version$
    | New\ Bookmarks$
    | Bookmarks$
)""", re.VERBOSE)

# The repo is public. Anything credential-shaped is withheld and reported.
# "token" is only credential-shaped when qualified — a bare match also hits
# AiMaxTokens / AiResponseMaxTokens, which are integer limits, not secrets.
SECRET = re.compile(
    r"secret|password|passphrase|credential|api[-_]?key"
    r"|(access|refresh|auth|bearer|session|id)[-_]?token"
    r"|oauth|bearer",
    re.I,
)


def looks_secret(key, value):
    """A key is withheld when its name, or its string value, looks credential-shaped."""
    if SECRET.search(key):
        return True
    return isinstance(value, str) and bool(SECRET.search(value))


# Profiles iTerm creates for itself, not ones the owner made: export leaves them out, and
# import never has a file for them. "tmux" is the profile iTerm adds the first time a tmux
# session opens with TmuxUsesDedicatedProfile on; it is a copy of Default plus a hotkey off.
AUTO_CREATED_PROFILES = {"tmux"}
