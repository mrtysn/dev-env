# Shared environment contract — hand-curated, never generated via `brew bundle dump`.
# Every machine and profile installs this file. Layers on top, installed by import.sh step 2:
#   Brewfile.<profile>  the machine's primary profile (first in machine-label.sh), e.g. Brewfile.personal
#   Brewfile.<label>    this machine only, e.g. Brewfile.c02
# An entry belongs here when every machine wants it, the work Mac included. Something only
# one profile or one machine wants goes in its layer, and never in two files.
# The `mas` lines at the end are installed by import.sh step 20, not step 2: they need an Apple ID
# signed in to the App Store and a terminal for the sudo password (mas 7 installs as root).

tap "localsend/localsend"       # LocalSend's own tap; the cask is not in homebrew-cask

# ── Shell and terminal
brew "powerlevel10k"            # prompt theme (sourced in zshrc)
brew "zsh-git-prompt"           # git status in the prompt
brew "fzf"                      # fuzzy finder (fzf --zsh integration + fzf-tab plugin)
brew "coreutils"                # GNU utilities (gnubin in PATH)
brew "gawk"                     # GNU awk
brew "tree"                     # directory tree (used by ls plugin)
brew "tmux"                     # terminal multiplexer
brew "htop"                     # process viewer
brew "wget"                     # file retriever
brew "rsync"                    # incremental file transfer, newer than the macOS one
brew "progress"                 # progress of running coreutils commands
brew "tlrc"                     # tldr pages client (the formula that was called tldr)
brew "wifi-password"            # shows the current Wi-Fi password
brew "blueutil"                 # Bluetooth power and discoverable state from the shell
brew "baobab"                   # disk usage analyzer
brew "sleepwatcher"             # runs a script on sleep, wake and idle
brew "syncthing"                # continuous file synchronisation

# ── Development
brew "asdf"                     # runtime version manager (see asdf/tool-versions)
brew "uv"                       # Python packages and environments
brew "cmake"                    # build system
brew "pandoc"                   # markup format conversion
brew "lazygit"                  # git TUI (repo-tabs default mode; config synced in lazygit/)
brew "git-lfs"                  # large-file support
brew "gh"                       # GitHub CLI
brew "awscli"                   # AWS command line
brew "doppler"                  # Doppler secrets CLI
brew "exiftool"                 # reads and writes image metadata
brew "ollama"                   # local LLM runtime
brew "gollama"                  # manages Ollama models
brew "jq"                       # export.sh settings strip + Claude settings merge + hook pipelines
brew "mas"                      # Mac App Store CLI (update-all and the mas lines below; needs an Apple ID)

# ── Terminal, editors and fonts
cask "iterm2"                   # terminal (settings + profiles synced)
cask "font-fira-code"           # Fira Code
cask "font-fira-code-nerd-font" # terminal font assumed by the p10k config
cask "sublime-text"             # $EDITOR 'subl --wait' and lazygit editPreset (personal licence)
cask "dbeaver-community"        # database client
cask "hoppscotch"               # API client
cask "meld"                     # diff and merge
cask "hex-fiend"                # hex editor
cask "devtoys"                  # developer utilities

# ── Window and keyboard
cask "rectangle"                # window snapping
cask "alt-tab"                  # window switcher
cask "itsycal"                  # menu bar calendar
cask "keepingyouawake"          # keep the Mac awake
cask "macshot"                  # screenshots: open source, no telemetry, upload off unless set up
cask "mos"                      # smooth scrolling, scroll direction per device
cask "lunar"                    # brightness for external displays
cask "balance-lock"             # stops audio balance drifting
cask "bluesnooze"               # stops a sleeping Mac connecting to Bluetooth accessories
cask "notunes"                  # stops iTunes or Apple Music launching
cask "funter"                   # shows hidden files in Finder
cask "openinterminal-lite"      # Finder toolbar button: open the folder in Terminal
cask "free-ruler"               # on-screen rulers
cask "numi"                     # calculator and converter
cask "latest"                   # shows pending app updates
cask "coconutbattery"           # battery information
cask "logitech-camera-settings" # camera controls
cask "handy"                    # speech to text

# ── Browsers, chat and sharing
cask "firefox"                  # browser
cask "telegram-desktop"         # Telegram
cask "whatsapp"                 # WhatsApp
cask "zoom"                     # meetings
cask "spotify"                  # music
cask "localsend"                # AirDrop-like file sending (tap above)
cask "rustdesk"                 # remote desktop

# ── Files, images and media
cask "keka"                     # file archiver
cask "kekaexternalhelper"       # helper app for Keka
cask "foxitreader"              # PDF reader
cask "syntax-highlight"         # Quick Look for source files
cask "iina"                     # media player
cask "vlc"                      # media player
cask "kap"                      # screen recorder
cask "gimp"                     # image editor
cask "krita"                    # painting
cask "inkscape"                 # vector graphics
cask "pinta"                    # simple paint program
cask "imageoptim"               # shrinks images
cask "image2icon"               # icon creator
cask "upscayl"                  # AI image upscaler

# ── Mac App Store (the mas lines need an Apple ID signed in; import.sh step 20 installs them)
# Picked 2026-11-17 from the apps in use on the home Mac
cask "opera"                    # browser
cask "google-chrome"            # browser
cask "tailscale-app"            # mesh VPN
cask "oversight"                # mic and camera monitor
cask "blender"                  # 3D
cask "appcleaner"               # uninstaller
cask "maccy"                    # clipboard history
cask "claude"                   # Claude desktop
cask "netiquette"               # network monitor

mas "Aiko", id: 1672085276                # speech to text
mas "Color Picker", id: 1545870783        # colour picker
mas "Day Progress", id: 6450280202        # day progress in the menu bar
mas "Pandan", id: 1569600264              # break timer in the menu bar
mas "Pure Paste", id: 1611378436          # paste without formatting
mas "Spaced", id: 1666327168              # break reminder
mas "uBlock Origin Lite", id: 6745342698  # Safari content blocker
mas "Unsplash Wallpapers", id: 1284863847 # wallpapers
mas "Velja", id: 1607635845               # browser picker
