# Shared environment contract — hand-curated, never generated via `brew bundle dump`.
# Every machine and profile installs this file. Layers on top, installed by import.sh step 2:
#   Brewfile.<profile>  the machine's primary profile (first in machine-label.sh), e.g. Brewfile.personal
#   Brewfile.<label>    this machine only, e.g. Brewfile.c02
brew "powerlevel10k"            # prompt theme (sourced in zshrc)
brew "fzf"                      # fuzzy finder (fzf --zsh integration + fzf-tab plugin)
brew "asdf"                     # runtime version manager (see asdf/tool-versions)
brew "coreutils"                # GNU utilities (gnubin in PATH)
brew "tree"                     # directory tree (used by ls plugin)
brew "tmux"                     # terminal multiplexer
brew "lazygit"                  # git TUI (repo-tabs default mode; config synced in lazygit/)
brew "git-lfs"                  # large-file support
brew "jq"                       # export.sh settings strip + Claude settings merge + hook pipelines
cask "iterm2"                   # terminal (settings + profiles synced)
cask "font-fira-code-nerd-font" # terminal font assumed by the p10k config
