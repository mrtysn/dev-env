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

Exports your current terminal configuration to this repo.

What it exports:
- Your full `.zshrc` as `.zshrc.full`
- Your `.p10k.zsh` configuration
- List of installed custom plugins
- List of required brew packages
- Claude Code `settings.json` for both config dirs (`agents/claude/`, `agents/claude-personal/`); machine-local `*.local.json` and memory are never exported

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
2. Installs required brew packages
3. Installs FiraCode Nerd Font (for terminal icons)
4. Installs Oh-My-Zsh (if not present)
5. Clones all custom plugins
6. Sets up Homebrew command-not-found
7. Configures FZF integration
8. Backs up existing configs and copies repo configs to home directory
9. Installs iTerm2 profiles (full profiles or font-only)
10. Sets zsh as default shell
11. Sets up tmux configuration (per-machine)
12. Backs up and copies Claude Code `settings.json` into `~/.claude` and `~/.claude-personal`

The script is idempotent - it checks what's already installed and skips those steps.

```bash
./import.sh
```

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

# Copy configs from this repo
cp .zshrc.base ~/.zshrc.base
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
- `brew-packages.list` - List of required brew packages
- `iterm-profiles/` - iTerm2 dynamic profile configurations
  - `default.json` - Full Default profile
  - `hotkey-window.json` - Full Hotkey Window profile
  - `web-browser.json` - Full Web Browser profile
  - `font-only.json` - Minimal profile (just sets FiraCode Nerd Font)
- `.gitignore` - Git ignore rules

## Credits

- [Oh-My-Zsh](https://ohmyz.sh/)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- All plugin authors (see Plugin Details section)

## License

Feel free to use, modify, and share.
