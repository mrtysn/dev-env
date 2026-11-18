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
