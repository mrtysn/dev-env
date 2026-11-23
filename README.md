# iTerm + ZSH Developer Configuration

Complete terminal setup for macOS developers using zsh, oh-my-zsh, and Powerlevel10k.

Supports easy export/import workflow for syncing configuration across machines.

## Features

- **Powerlevel10k theme** - Fast, customizable prompt with git integration
- **Smart plugin loading** - Full features in regular terminal, lightweight in Claude Code
- **Enhanced navigation** - Better ls, tree views, directory switching
- **Git enhancements** - Fast completions, fancy logs, GitHub integration
- **Syntax highlighting** - Real-time command validation
- **Auto-suggestions** - Fish-like command completion
- **FZF integration** - Fuzzy finder for history and files
- **Development tools** - Support for Node.js, Go, .NET, Python, Perl
- **macOS integration** - iTerm tab colors, notifications, macOS-specific commands
- **Split configuration** - Base config + personal customizations kept separate

## Quick Start

### For New Setup (Import)

```bash
# Clone this repo
git clone <your-repo-url> ~/iterm-zsh-dev-config
cd ~/iterm-zsh-dev-config

# Run import script
./import.sh
```

The import script is idempotent - safe to run multiple times.

### For Existing Setup (Export)

```bash
# Navigate to repo
cd ~/iterm-zsh-dev-config

# Export your current configuration
./export.sh

# Commit and push changes
git add .
git commit -m "Update config"
git push
```

## Machines and Profiles

Two things select what a machine gets.

- **Machine label** (`c02`, `c03`, ...): `machine-label.sh` maps the Mac's LocalHostName to it.
  The label names every per-machine file: `.zshrc.<label>`, `Brewfile.<label>`,
  `tmux/<label>.conf`, `asdf/tool-versions.<label>`. `.zshrc.loader` repeats the hostname
  cases, because shell startup must not depend on this repo.
- **Profile** (`personal` or `work`): what a Claude config folder, and the machine as a whole,
  is used for. `machine-label.sh` lists each machine's profiles; the first is its primary one.

| Label | Machine | LocalHostName | Profiles |
|---|---|---|---|
| c02 | Home Mac | `mrtysn-mbp-m2max` | personal |
| c03 | Work Mac | `mrtysn-mbp-m5` | work, personal |

A new machine is one case in `machine-label.sh` and one in `.zshrc.loader`, plus whichever
per-machine files it needs.

### Brewfile layers

`import.sh` step 2 runs `brew bundle` on each layer that exists, in order:

1. `Brewfile`: what every machine wants, the work Mac included: shell and terminal tools,
   git and cloud tooling, editors, window and keyboard utilities, everyday apps and the Mac
   App Store apps (`mas "<name>", id: <id>`).
2. `Brewfile.<primary profile>`: `Brewfile.personal` holds casks that need a system grant or a
   driver extension a managed machine may refuse (karabiner-elements, phoenix, sourcetree).
   `Brewfile.work` holds what every work machine wants beyond the shared file.
3. `Brewfile.<label>`: this machine only.

An entry is listed once, in the layer that owns it. The `mas` lines need an Apple ID signed in
to the App Store: step 2 checks (macOS's Accounts database, then `mas account` where mas has it,
otherwise it asks) and, with no Apple ID, skips every `mas` entry with a message instead of failing; re-run the step once
signed in. They also need root: mas 7 installs through `sudo`. A shell with no terminal (an agent's) and no
cached sudo credential cannot type the password, so step 2 skips the `mas` apps not yet installed, says so
again at its end, and `--check` lists them as a change. Run `./import.sh --steps 2` in a terminal to install
them; `--answer mas-signed-in=yes` alone does not.

Only the primary profile's layer is installed, so the work Mac's personal config folder does
not bring the personal casks with it. `export.sh` reports installed formulae and casks that no
layer lists; it never writes a Brewfile.

### Claude config folders

A machine may run any number of Claude config folders, one per account: `~/.claude` and any
`~/.claude-<name>` (set `CLAUDE_CONFIG_DIRS` to a space-separated list to name them instead).
Each folder declares its profile in its own, never-synced `paths.local.sh`:

    AGENT_PROFILE="work"

Its `settings.json` is built, never copied:

    agents/claude/settings.json                 base: valid on every machine and profile
  + agents/claude/overlays/<profile>.json       committed overlay (personal.json)
  + agents/claude/overlays/<profile>.local.json untracked overlay (work.local.json)

The personal overlay holds the auto-mode text about the homelab and the personal domains, and
the hooks for personal-only tools (system-one, agent-request-limiter, bigarrow). The work
overlay names the employer's GitHub org, domains and production markers, so it is never
committed: `overlays/work.json.example` has `<FILL: ...>` placeholders, and the merge refuses a
file that still has one. `agents/claude/settings-profile.sh` does the merge
(`merge PROFILE`), the comparison (`check DIR`) and the folder discovery (`dirs`);
`agents/claude/test-settings-profile.sh` checks it.

The merge concatenates arrays instead of replacing them, so an overlay adds hooks and
allow rules to the base's. `autoMode.environment` is merged by field label: an overlay line
`**Source control**: ...` replaces the base line with that label in place, keeping the base's
section order, and a new label is appended.

`import.sh` step 12 asks each folder's profile when its `paths.local.sh` has none, records it
there (`write-paths-local.sh --profile`), and writes the merged settings. `export.sh` writes no
Claude settings: it refuses a folder whose live file differs from the merge and names the keys,
with a diff. Move the change into the base or the overlay, then re-run step 12. The comparison
ignores `feedbackSurveyState`, `theme` (the theme picker's choice; step 12 keeps it), `env.AGENTS_SHARED` and the order of hooks within an event
(Claude Code runs them in parallel).

### One Chrome profile per Claude account

Claude-in-Chrome opens `https://clau.de/chrome/...` with `open -a "Google Chrome"`, which lands in
whichever Chrome profile was last used. `agents/claude/chrome-open-shim/open` is a PATH shim that adds
`--profile-directory` to that one call. It is opt-in per machine: run
`agents/claude/chrome-open-shim/install.sh`, then put the Chrome profile folder (`Profile 1`, `Default`;
see `~/Library/Application Support/Google/Chrome`) in each config folder's `paths.local.sh`:

    CLAUDE_CHROME_PROFILE="Profile 1"

The `claude()` wrapper in `.zshrc.base` puts the shim first on `PATH` only when it is installed. A folder
with no profile, and every other `open` call, passes through unchanged. `test-open-shim.sh` checks it.

### Setting up a fresh config folder

The base settings call hooks that live outside this repo, and a new folder has none of them
until you set them up. `import.sh` step 12 writes `settings.json` and `paths.local.sh`; then,
with `CLAUDE_CONFIG_DIR` set to the folder (leave it unset for `~/.claude`):

```bash
# 1. Status line and its event hook: clone cc-statusline next to this repo, so step 12 can record
#    CC_STATUSLINE_DIR (or set it in paths.local.sh by hand), then link its hook into the folder.
git clone <cc-statusline-url> "$(dirname "$PWD")/cc-statusline"
CLAUDE_CONFIG_DIR=~/.claude-<name> "$(dirname "$PWD")/cc-statusline/scripts/install-event-hook.zsh"

# 2. agents-shared: links the profile's rules, skills and commands, and hooks/subagent-guard.sh
CLAUDE_CONFIG_DIR=~/.claude-<name> <agents-shared checkout>/scripts/init-global.sh
```

Re-run `import.sh` after cloning cc-statusline if the folder's `paths.local.sh` has no
`CC_STATUSLINE_DIR`; until then the status line is blank. Without step 1 the
`cc-statusline-event.zsh` hook entries point at a missing file, and without step 2 the
`subagent-guard.sh` entry does. `agents/claude/verify-hook-paths.sh` checks the guards only.

### Setting up the work Mac

1. Set its hostname: `sudo scutil --set LocalHostName mrtysn-mbp-m5`.
2. Clone this repo, agents-shared, tools and cc-statusline into the dev root. tools is
   private, so its clone needs a GitHub login that can read it; the others are public.
3. Copy `agents/claude/overlays/work.json.example` to `agents/claude/overlays/work.local.json`
   and fill in every placeholder.
4. Run `./import.sh`. Step 2 installs `Brewfile`, `Brewfile.work` and `Brewfile.c03`. The `mas`
   apps in `Brewfile` wait for the work Mac's own Apple ID: step 2 detects that no App Store
   account is signed in and skips them; sign in, then re-run step 2. Step 12
   asks the profile of `~/.claude` (work) and offers to add a folder for the personal account
   (for example `~/.claude-personal`, personal).
5. For each config folder, follow "Setting up a fresh config folder" (cc-statusline's
   `install-event-hook.zsh`, then agents-shared's `scripts/init-global.sh`).
6. Write the push denylist by hand (step 15 says where) before the first push from this machine.
   It holds only the employer's own names and internal terms and is never a copy of the home
   machine's list, which names private projects and people. Leave `core.hooksPath` unset globally
   on this machine: step 15 routes agents-shared and this repo through the guard per repo.
7. Install the command-line tools. Tell the `tools` repo this is a work machine, then run its
   installer; the profile file is untracked, and without it every tool is linked:

   ```bash
   mkdir -p ~/.config/tools && echo work > ~/.config/tools/profile
   <tools checkout>/install.sh
   ```

   On a work profile the installer skips the tools named in `tools/personal-only.txt`.
8. Clone each repo the installer reported as `skipped: <path> is not on this machine` into the
   dev root, next to `tools`, then run `tools/install.sh` again. The tools README says which
   repos link themselves instead.

### Push name guard

This repo is public. `import.sh` step 15 points this clone's `core.hooksPath` at
agents-shared's `githooks/`, whose `pre-push` refuses a push that adds a line, path or commit
message naming an entry on a local, untracked denylist. It skips private GitHub repos, scans
public and unknown ones, and still runs a repo's own hooks (git-lfs and the like). It refuses
every scanned push while the denylist is missing, and passes every push while it holds no
entries, so step 15 warns when the file has only comments or blank lines. By hand:

```bash
git -C <this repo> config core.hooksPath "$AGENTS_SHARED/githooks"
```

- **Personal machine:** enabling the guard globally is the recommended setup, so every public repo
  is covered: `git config --global core.hooksPath "$AGENTS_SHARED/githooks"`.
- **Work machine:** the guard runs per repo, agents-shared and this repo only, as step 15 sets it,
  and never globally, because globally it would run on the employer's repos. The work machine's
  denylist is written there by hand and holds only the employer's own names and internal terms.
  It is never a copy of the home machine's list, which names private projects and people.

### macOS keyboard shortcuts

`export.sh` records every entry macOS has written for System Settings > Keyboard > Keyboard Shortcuts
(`com.apple.symbolichotkeys`: each shortcut changed or switched off, and some macOS writes itself) in
`macos/symbolic-hotkeys.plist`, with its on/off state and its keys. `import.sh` step 17 makes the same
entries match on another machine, after asking, and applies them without a logout; entries never
written keep macOS's defaults everywhere. `macos/symbolic-hotkeys.py check` lists recorded entries that
differ here; `macos/test-symbolic-hotkeys.zsh` tests it on a copy of the settings.

Per machine: `macos/symbolic-hotkeys.plist` belongs to the machine in its `_machine` key (c02). Export
on any other machine writes only where it differs, to `macos/symbolic-hotkeys.<label>.plist`, and
import applies that on top of the shared record. c03's file binds Show Launchpad to F18, the key
step 18 maps Caps Lock to, where the home Mac has Karabiner doing it.

### App settings

`app-settings/apps.json` lists the apps whose settings move between machines and, per app, an
**allowlist** of the preference keys that may: this repo is public, and an app's preferences
also hold locations, licence data, device IDs and window positions, which a list of keys to
drop would miss. Sublime Text carries its `Packages/User` settings files instead of keys.

    app-settings/app-settings.py export   # this machine's allowlisted settings into app-settings/
    app-settings/app-settings.py import   # into this machine, for installed apps (import.sh step 16)
    app-settings/app-settings.py check    # per app: matches or differs

Both directions write only what differs, so re-runs change nothing. Import skips a running app
(it would write its old values back on quit) and says to quit it first. Export refuses a value
that holds the home folder's path or an email address. `export.sh` runs the export;
`app-settings/test-app-settings.zsh` imports into an empty home twice and checks the second run
loads nothing. To carry another app, add it to `apps.json` with the keys that are settings, run
the export, and read the new file before committing.

## Configuration Structure

### Base Configuration (`.zshrc.base`)

Generic setup that works for any developer. Includes:
- Oh-My-Zsh setup with plugin management
- Smart plugin loading (different for Claude Code vs normal terminal)
- Shell enhancements (history, completion, syntax highlighting)
- Tool integrations (Homebrew, FZF, asdf)
- Development paths (pnpm, Go, .NET, Perl, GNU coreutils)
- Generic aliases (gitlog, python3, brew update)
- Password prompt notifications

**Do not modify this file** - it's managed by the repo and updated via export/import.

### Personal Configuration (`.zshrc.personal`)

Your personal customizations. This is where you add:
- Project-specific aliases
- Custom functions
- Personal tool configurations
- Navigation shortcuts
- Editor preferences

**Modify this freely** - it's yours to customize.

### How It Works

Your actual `~/.zshrc` sources both files:

```bash
# Source base configuration
[ -f ~/.zshrc.base ] && source ~/.zshrc.base

# Source personal configuration
[ -f ~/.zshrc.personal ] && source ~/.zshrc.personal
```

This allows you to:
- Keep generic setup synced across machines via git
- Maintain machine-specific customizations independently
- Update base config without losing personal settings

## Scripts

### `export.sh`

Exports your current terminal configuration to this repo. It asks "Continue?" once; `./export.sh --yes` skips the question, and without a terminal (an agent's shell) it refuses to run unless `--yes` is given.

What it exports:
- Your full `.zshrc` as `.zshrc.full`
- Your `.p10k.zsh` configuration
- List of installed custom plugins
- A report of brew packages no Brewfile layer lists
- A check of every Claude config folder's `settings.json` against base + its profile's
  overlays (see "Claude config folders"); it writes nothing there, and machine-local
  `*.local.json` and memory are never read

Paths inside the base and overlays must resolve at runtime on every machine, so a
hardcoded `/Users/<name>/...` silently breaks the other machine. Hooks living under the config dir use
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; a repo that sits at a different depth per machine is
never probed for at fixed paths: every hook, the status line included, reads its checkout from
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/paths.local.sh` (machine-local, never exported).

The two kinds differ only in what an unset path does. Cosmetic tooling (the status line, the
tab-status and focus-policy hooks) exits 0 and quietly does nothing. A safety hook must not: the
`PreToolUse` guards exit 2, blocking the tool call, so a machine with a different layout is never
left unguarded and unwarned.

`import.sh` writes that file for you as part of step 12, deriving the checkout
from an existing rules symlink or a sibling of this repo and asking if it finds
neither — it never guesses a layout. To write or repair it by hand, run
`agents/claude/write-paths-local.sh` (`--path DIR` to name the checkout, `--yes`
for non-interactive); `agents/claude/verify-hook-paths.sh` confirms every hook
resolves. `agents/claude/paths.local.sh.example` documents the shape (`AGENT_PROFILE`,
`AGENTS_SHARED_DIR`, `CC_STATUSLINE_DIR` and the optional ones).

After export, you should:
1. Review the changes
2. Split personal customizations into `.zshrc.personal` if needed
3. Commit and push

```bash
./export.sh
```

### `import.sh`

Sets up your terminal from this repo configuration.

What it does:
1. Installs Homebrew (if not present)
2. Installs brew dependencies via `brew bundle`: `Brewfile`, `Brewfile.<primary profile>`, `Brewfile.<label>` (includes FiraCode Nerd Font)
3. Installs this machine's asdf plugins and runtimes from `asdf/tool-versions.<label>`
4. Installs Oh-My-Zsh (if not present)
5. Clones all custom plugins
6. Sets up Homebrew command-not-found
7. Configures FZF integration
8. Copies the zsh configs to the home directory, backing up any that differ
9. Installs iTerm2 profiles (full profiles or font-only) and applies app-level iTerm2 settings; those apply only while iTerm2 is not running, so run `import.sh` from Terminal.app for them, or quit iTerm2 and re-run. A profile that is already saved in iTerm2 (the machine `export.sh` reads) is not installed as a dynamic profile, because iTerm2 refuses a dynamic profile with a saved profile's Guid; import removes such a dynamic copy. When the saved profile differs from the repo's file, import lists the differing settings and asks whether to replace the saved one (default no, plist backed up first, iTerm2 quit); `--check` reports the difference and says to run `export.sh` if this machine is newer
10. Sets zsh as default shell
11. Sets up tmux configuration (per-machine)
12. For each Claude config folder (`~/.claude`, every `~/.claude-*`, and any you add when asked): records its profile and agents-shared checkout in `paths.local.sh` via `agents/claude/write-paths-local.sh` (the guard hooks refuse every Bash tool call until it resolves), then backs up and writes `settings.json` as base + that profile's overlays
13. Copies the Phoenix and Karabiner configs, each only where its app is installed
14. Copies lazygit and repo-tabs configs
15. Routes this clone's pushes through agents-shared's name guard
16. Loads the app settings in `app-settings/` for each app that is installed (see "App settings"). macshot's ⇧⌘9 does nothing until macshot has been opened once and granted Screen Recording. Launch each app once before its first import: Lunar, for one, switches its own brightness mode on first launch and would overwrite what step 16 loaded. An app whose settings sit in a group container (coconutBattery) needs it opened once first, and the terminal allowed to access data from other apps (System Settings > Privacy & Security); the step names which and carries on
17. Sets the macOS keyboard shortcuts as recorded (`macos/symbolic-hotkeys.plist`, written by `export.sh`): on or off, and their keys, asking first
18. On a Mac without Karabiner-Elements, does with macOS's own settings what Karabiner does: a login agent maps Caps Lock to F18 with `hidutil` (`macos/capslock-to-f18.zsh`; the machine's shortcuts bind F18, as c03 binds it to Show Apps), and each keyboard gets the modifier swaps `karabiner/karabiner.json` makes for it (`macos/modifier-keys.py`; applies when the keyboard reconnects or at the next login)

`./import.sh --steps 16,17` (or ranges, `2-5,16`) runs only those steps; with `--check` it compares only those.
A machine can decline optional steps for good: `MACHINE_SKIP_STEPS` in `machine-label.sh` (c03 declines step 14), which both the run and `--check` leave out unless `--steps` names them. Step 3 skips a machine whose `asdf/tool-versions.<label>` is empty.

The script is idempotent: a second run installs nothing and writes nothing. A file that already
matches the repo is left alone (`already matches`), and only a file that differs is backed up
before it is replaced. `./import.sh --check` proves it without a second run (see below).

```bash
./import.sh
./import.sh --check   # compare only
```

`--check` runs each step's own comparison and writes nothing: no file, backup, `defaults`, brew or
asdf install, git config or `killall`; it asks nothing and opens nothing. It prints one line per
step, `✓ step N: matches`, `✗ step N: would change <what>` or `- step N: not checked (<why>)` (such
as iTerm2's app-level settings while iTerm2 runs), and exits 1 when any step would change. Step 2
is `brew bundle check` per layer (the mas apps are skipped without an App Store login, and brew is
kept from auto-updating, so the only network use is whatever `brew bundle check` itself does);
step 3 compares the pins file and whether each pinned runtime is installed.
Step 9 also reports iTerm2's tmux prefs (`OpenTmuxWindowsIn`, `AutoHideTmuxClientSession`,
`TmuxUsesDedicatedProfile`) as a change when unset, and `export.sh` warns for the same keys; `clo` needs them.

### Non-interactive use (agents)

Every prompt in `import.sh` has a key, and `--answer KEY=VALUE` (repeatable) answers it. With
`--non-interactive`, or whenever stdin is not a terminal, a prompt without an answer stops the run with
exit 2 and prints its key, so an agent never hangs. Yes/no keys take `yes` or `no`. Every interactive
prompt added to `import.sh` must take a key: `ask_yes_no KEY "prompt"` and `ask_value KEY "prompt" VAR`
refuse a call without one.

| Key | Step | Value |
|---|---|---|
| `brew-bundle` (2), `asdf-runtimes` (3), `oh-my-zsh` (4), `custom-plugins` (5), `fzf` (7), `copy-zsh-configs` (8) | as listed | yes/no |
| `iterm-profiles` | 9 | `full`, `font` or `skip` |
| `replace-saved-profile:<profile>` | 9 | yes/no, one per profile file name without `.json` (`default`) |
| `iterm-app-settings` | 9 | yes/no |
| `default-shell-zsh` | 10 | yes/no (`chsh` still asks for the password) |
| `tmux-machine-config` | 11 | `c02`-style machine name or `skip`, only on an unknown machine |
| `tmux-config`, `tmux-ssh-config` | 11 | yes/no |
| `claude-extra-folders` | 12 | comma-separated folders, e.g. `~/.claude-work,~/.claude-personal`; absent means none |
| `claude-create-folder:<folder>`, `claude-write-settings:<folder>`, `claude-profile:<folder>` | 12 | yes/no, yes/no, profile name; `<folder>` as printed (`~/.claude-work`) |
| `copy-window-configs`, `copy-lazygit-configs` | 13, 14 | yes/no |
| `name-guard-pre-push` (15), `app-settings` (16), `macos-shortcuts` (17), `caps-lock-f18` and `karabiner-modifier-keys` (18) | as listed | yes/no |
| `mas-signed-in` | 2 | yes/no; unanswered counts as signed out |

## Detailed Installation Steps

If you prefer manual installation instead of using the import script:

### 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install required packages

```bash
brew install powerlevel10k fzf asdf coreutils tree
```

### 3. Install Oh-My-Zsh

```bash
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### 4. Install custom Oh-My-Zsh plugins

```bash
# Create custom plugins directory
mkdir -p ~/.oh-my-zsh/custom/plugins

# Install all required plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting ~/.oh-my-zsh/custom/plugins/fast-syntax-highlighting
git clone https://github.com/Aloxaf/fzf-tab ~/.oh-my-zsh/custom/plugins/fzf-tab
git clone https://github.com/djui/alias-tips ~/.oh-my-zsh/custom/plugins/alias-tips
git clone https://github.com/peterhurford/git-it-on.zsh ~/.oh-my-zsh/custom/plugins/git-it-on
git clone https://github.com/posva/catimg ~/.oh-my-zsh/custom/plugins/catimg
git clone https://github.com/Mumbleskates/hitchhiker ~/.oh-my-zsh/custom/plugins/hitchhiker
git clone https://github.com/MichaelAquilina/zsh-auto-notify ~/.oh-my-zsh/custom/plugins/auto-notify
git clone https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv ~/.oh-my-zsh/custom/plugins/autoswitch_virtualenv
git clone https://github.com/bernardop/iterm-tab-color ~/.oh-my-zsh/custom/plugins/iterm-tab-color
git clone https://github.com/zshzoo/cd-ls ~/.oh-my-zsh/custom/plugins/cd-ls
git clone https://github.com/TamCore/autoupdate-oh-my-zsh-plugins ~/.oh-my-zsh/custom/plugins/autoupdate
git clone https://github.com/zpm-zsh/ls ~/.oh-my-zsh/custom/plugins/ls
```

### 5. Setup command-not-found

```bash
brew tap homebrew/command-not-found
```

### 6. Setup FZF

```bash
$(brew --prefix)/opt/fzf/install --key-bindings --completion --no-update-rc --no-bash --no-fish
```

### 7. Apply configuration files

```bash
# Backup existing configs (if any)
mv ~/.zshrc ~/.zshrc.backup 2>/dev/null
mv ~/.p10k.zsh ~/.p10k.zsh.backup 2>/dev/null

# Link the shared base so the repo stays the single source of truth;
# copy only if this clone is temporary
ln -sf "$PWD/.zshrc.base" ~/.zshrc.base
# cp .zshrc.base ~/.zshrc.base   # alternative to the symlink above
cp .zshrc.personal ~/.zshrc.personal
cp .p10k.zsh ~/.p10k.zsh

# Create main .zshrc that sources both
cat > ~/.zshrc << 'EOF'
# Source base configuration
[ -f ~/.zshrc.base ] && source ~/.zshrc.base

# Source personal configuration
[ -f ~/.zshrc.personal ] && source ~/.zshrc.personal
EOF

# Reload configuration
source ~/.zshrc
```

On first launch, the Powerlevel10k configuration wizard will run. Choose your preferred style.

## Customization

### Adding Your Own Aliases

Edit `~/.zshrc.personal`:

```bash
# Your custom aliases
alias myproject="cd /path/to/your/project"
alias gs="git status"
```

### Changing Editor

Edit `~/.zshrc.personal`:

```bash
export EDITOR='vim'  # or 'nano', 'nvim', etc.
```

### Modifying Powerlevel10k Theme

Run the configuration wizard anytime:

```bash
p10k configure
```

### Adding More Plugins

Browse available plugins:
- Built-in: `ls ~/.oh-my-zsh/plugins/`
- Community: [Awesome Zsh Plugins](https://github.com/unixorn/awesome-zsh-plugins)

Add plugin names to the `plugins=()` array in `.zshrc.base` (if generic) or install to `~/.oh-my-zsh/custom/plugins/` and add to your personal plugins list.

## Plugin Details

### Custom Plugins (require git clone)

- **zsh-autosuggestions** - Fish-like autosuggestions
- **fast-syntax-highlighting** - Real-time syntax highlighting
- **fzf-tab** - Tab completion with FZF
- **alias-tips** - Reminds you of available aliases
- **git-it-on** - Open files/branches on GitHub
- **catimg** - Display images in terminal
- **hitchhiker** - Misc utilities
- **auto-notify** - Notifications for long-running commands
- **autoswitch-virtualenv** - Auto Python virtualenv switching
- **iterm-tab-color** - Color tabs by directory
- **cd-ls** - Auto ls after cd
- **autoupdate** - Auto-update custom plugins
- **ls** - Enhanced ls with colors and icons

### Built-in Plugins (come with oh-my-zsh)

- **gitfast** - Fast git completions
- **copypath** - Copy current path to clipboard
- **copybuffer** - Copy command buffer to clipboard
- **command-not-found** - Suggest package to install
- **macos** - macOS-specific utilities
- **asdf** - Version manager integration
- **isodate** - ISO date utilities
- **colored-man-pages** - Colorized man pages
- **dircycle** - Cycle through directory history

## Workflow Examples

### Setting Up New Machine

```bash
# 1. Clone your config repo
git clone <your-repo-url> ~/iterm-zsh-dev-config
cd ~/iterm-zsh-dev-config

# 2. Run import
./import.sh

# 3. Restart terminal
# Powerlevel10k wizard will run on first start

# 4. Customize personal config
vim ~/.zshrc.personal
```

### Updating Configuration

```bash
# After making changes to your terminal setup
cd ~/iterm-zsh-dev-config
./export.sh

# Review changes
git diff

# Commit and push
git add .
git commit -m "Update terminal config"
git push
```

### Syncing to Another Machine

```bash
# On the machine you want to update
cd ~/iterm-zsh-dev-config
git pull
./import.sh

# Restart terminal to apply changes
```

## Troubleshooting

### ls command errors

Make sure GNU coreutils is installed:
```bash
brew install coreutils
```

### Plugin not found errors

Verify custom plugins are installed:
```bash
ls ~/.oh-my-zsh/custom/plugins/
```

Re-run import script if any are missing:
```bash
./import.sh
```

### FZF not working

Reinstall FZF integration:
```bash
$(brew --prefix)/opt/fzf/install --key-bindings --completion --no-update-rc --no-bash --no-fish
```

### Terminal icons not displaying correctly

This config uses FiraCode Nerd Font for terminal icons. If icons appear as boxes or question marks:

1. Ensure the font is installed:
   ```bash
   brew install --cask font-fira-code-nerd-font
   ```

2. Configure iTerm2 to use the font:
   - Open iTerm2 Preferences → Profiles → Text
   - Set Font to "FiraCode Nerd Font Mono"
   - Or re-run `./import.sh` and select the iTerm2 profile option

### Slow shell startup

The config includes Claude Code detection for minimal plugin loading. You can also:
- Remove unused plugins from `.zshrc.base`
- Disable plugins you don't use
- Run `omz plugin disable <plugin-name>`

### Import script fails partway

The script is idempotent - just run it again:
```bash
./import.sh
```

It will skip already-completed steps and continue from where it left off.

### Personal config overwritten

The import script never overwrites `~/.zshrc.personal` if it already exists. Your personal customizations are safe.

## Development Tools Setup

This config assumes you'll use `asdf` for version management. Example setup:

```bash
# Install asdf plugins
asdf plugin add nodejs
asdf plugin add golang
asdf plugin add dotnet

# Install versions
asdf install nodejs latest
asdf install golang latest
asdf install dotnet latest

# Set global versions
asdf global nodejs latest
asdf global golang latest
asdf global dotnet latest
```

## Files in This Repo

- `README.md` - This file
- `export.sh` - Export current config to repo
- `import.sh` - Import config from repo and setup environment
- `.zshrc.base` - Base configuration (generic)
- `.zshrc.personal` - Personal configuration (customize freely)
- `.p10k.zsh` - Powerlevel10k theme config
- `plugins.list` - List of custom plugins to install
- `machine-label.sh` - hostname → machine label and profiles
- `Brewfile` - Shared brew, cask and Mac App Store dependencies, hand-curated — never `brew bundle dump`ed
- `Brewfile.personal` / `Brewfile.work` - Per-profile brew dependencies
- `Brewfile.c02` / `Brewfile.c03` - Machine-specific brew dependencies
- `asdf/tool-versions.<label>` - Per-machine runtime pins (each machine exports/imports only its own)
- `agents/claude/` - Claude settings base, `overlays/`, and the scripts that merge, check and set up config folders
- `iterm-profiles/` - iTerm2 dynamic profile configurations
  - `default.json` - Full Default profile
  - `hotkey-window.json` - Full Hotkey Window profile
  - `web-browser.json` - Full Web Browser profile
  - `font-only.json` - Minimal profile (just sets FiraCode Nerd Font)
- `iterm-settings.json` - iTerm2 **app-level** preferences (see below)
- `.gitignore` - Git ignore rules

## iTerm2 app-level settings

Profiles alone cannot reproduce the setup. Theme, tab bar position and width, the
Minimal-theme tuning knobs, global keymaps, pointer actions and custom colour presets are
**top-level** plist keys that live outside any profile. `iterm-settings.json` captures them.

**Keys are copied verbatim from the live plist and must never be hand-typed.** iTerm reads
CamelCase names (`MinimalDeslectedColoredTabAlpha`) while its internal symbols are
lowercase-first (`minimalDeslectedColoredTabAlpha`). Writing the lowercase spelling via
`defaults write` creates a separate key that nothing ever reads — it looks like it worked
and changes nothing.

**iTerm2 must be quit before importing.** It rewrites its plist from memory on quit, so
settings written while it is running are silently discarded. `import.sh` checks for a running
iTerm2 and refuses rather than writing values that would vanish.

What is excluded, by pattern:

| Pattern | Why |
|---|---|
| `NoSync*` | iTerm's own marker for machine-local state |
| `NSWindow Frame *`, `NSSplitView *`, `NSToolbar *` | window and panel geometry |
| `SU[A-Z]*` | Sparkle updater state |
| `NSNavLastRootDirectory`, `NSNavPanelExpandedSize*` | file-panel geometry and last path |
| `NeverWarnAboutShortLivedSessions_*` | per-profile-GUID dismissals |
| `findMode_iTerm`, `kCPK*` | transient UI state |
| `New Bookmarks` | profiles, exported separately |

**This repository is public.** The export also runs a secrets gate: any key or string value
matching a credential pattern is withheld from the export and named in the output for manual
review. Read `iterm-settings.json` before committing.

The export filter (the exclusion patterns, the secrets gate and the profiles iTerm creates for
itself, such as `tmux`) lives in `iterm-filter.py`, one definition used by `export.sh` and
`import.sh --check`. `--check` also reports a setting present in the live plist that
`iterm-settings.json` lacks, as `N unexported: KEY, ...`: set by hand in iTerm and never exported,
so run `export.sh` and read the diff.

## Credits

- [Oh-My-Zsh](https://ohmyz.sh/)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- All plugin authors (see Plugin Details section)

## License

Feel free to use, modify, and share.

## Known Gaps

- **The c03 files are empty until the work Mac exports.** `.zshrc.c03`,
  `tmux/c03.conf` and `asdf/tool-versions.c03` were added before the machine
  existed; its first `./export.sh` fills them.
- **A loader case added in the repo is lost by exporting first.** `export.sh`
  copies the live `~/.zshrc` over `.zshrc.loader`; it warns when the repo copy maps
  a machine the live file lacks. Run `import.sh` step 8 on each machine after
  adding a machine.

## Deliberately Not Synced

Referenced by the environment but excluded from this (public) repo — set up manually on a new machine:

- `claude` CLI — native installer, not brew-managed
- `~/.gitconfig` + `~/.gitconfig-personal` — git identity / includeIf split
- `~/.ssh/config` — ssh hosts (security material)
- `~/.config/repo-tabs/repos.txt` — same reason; seeds itself via `repo-tabs focus`
- Claude hooks (`~/.claude*/hooks/`) — referenced by synced settings.json; pending content review
- Each Claude config folder's `paths.local.sh` — its profile and checkout paths
- `agents/claude/overlays/*.local.json` — gitignored; the work overlay names the employer
