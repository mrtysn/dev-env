#!/bin/zsh
# Import and setup terminal configuration from this repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

# Machine → label (c01/c02) mapping: single source of truth.
source "$SCRIPT_DIR/machine-label.sh"
cd "$SCRIPT_DIR"

# Claude Code config dirs — override via env if your layout differs.
# Not derived from $CLAUDE_CONFIG_DIR on purpose: that var is session-contextual
# (the claudep alias flips it), so it can't be trusted to name the work dir.
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CLAUDE_PERSONAL_DIR="${CLAUDE_PERSONAL_DIR:-$HOME/.claude-personal}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Dev Environment Import ==="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print "${RED}✗ This script is designed for macOS${NC}"
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to ask yes/no with default
# Usage: ask_yes_no "prompt" [default: y/n]
ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local reply

    if [[ "$default" == "y" ]]; then
        read "reply?${prompt} [Y/n] "
        reply=${reply:-Y}
    else
        read "reply?${prompt} [y/N] "
        reply=${reply:-N}
    fi

    [[ "$reply" =~ ^[Yy]$ ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Homebrew (required - other steps depend on it)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 1: Homebrew ==="
if command_exists brew; then
    print "${GREEN}✓ Homebrew already installed${NC}"
else
    print "${YELLOW}→ Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon
    if [[ $(uname -m) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    print "${GREEN}✓ Homebrew installed${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Brew Packages (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 2: Brew Bundle ==="
# Shared Brewfile + this machine's Brewfile.c01/c2 — brew bundle is natively
# idempotent (skips installed, reports per-item).
BREW_LABEL="$MACHINE_LABEL"  # from machine-label.sh

if [ -f Brewfile ]; then
    print "${BLUE}Shared Brewfile:${NC} $(grep -cE '^(brew|cask|mas) ' Brewfile) entries"
    [[ -n "$BREW_LABEL" && -f "Brewfile.$BREW_LABEL" ]] && \
        print "${BLUE}Machine Brewfile.$BREW_LABEL:${NC} $(grep -cE '^(brew|cask|mas) ' Brewfile.$BREW_LABEL) entries"
    if ask_yes_no "Install brew dependencies (brew bundle)?"; then
        brew bundle --file=Brewfile || print "${RED}✗ some shared Brewfile entries failed${NC}"
        if [[ -n "$BREW_LABEL" && -f "Brewfile.$BREW_LABEL" ]]; then
            brew bundle --file="Brewfile.$BREW_LABEL" || print "${RED}✗ some Brewfile.$BREW_LABEL entries failed${NC}"
        fi
    else
        print "${YELLOW}! Skipped brew bundle${NC}"
    fi
else
    print "${RED}✗ Brewfile not found${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Nerd Font (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 3: asdf Runtimes ==="
# Per-machine pins (asdf/tool-versions.c01|c2) — same one-sided convention as
# .zshrc.<label>: this machine only ever reads its own file.
if [[ -n "$BREW_LABEL" ]] && [ -f "asdf/tool-versions.$BREW_LABEL" ] && command -v asdf >/dev/null 2>&1; then
    print "${BLUE}Runtimes ($BREW_LABEL):${NC} $(tr '\n' ' ' < "asdf/tool-versions.$BREW_LABEL")"
    if ask_yes_no "Install asdf plugins and runtimes? (runtime builds can take a while)"; then
        if [ -f ~/.tool-versions ]; then
            cp ~/.tool-versions ~/.tool-versions.backup-$(date +%Y%m%d-%H%M%S)
            print "${YELLOW}→ Backed up existing ~/.tool-versions${NC}"
        fi
        cp "asdf/tool-versions.$BREW_LABEL" ~/.tool-versions
        while read -r tool _version; do
            [[ -z "$tool" || "$tool" == \#* ]] && continue
            if asdf plugin list 2>/dev/null | grep -qx "$tool"; then
                print "${GREEN}✓ asdf plugin $tool already added${NC}"
            else
                print "${YELLOW}→ Adding asdf plugin $tool...${NC}"
                asdf plugin add "$tool" || print "${RED}✗ plugin $tool failed${NC}"
            fi
        done < "asdf/tool-versions.$BREW_LABEL"
        (cd ~ && asdf install) || print "${RED}✗ some runtimes failed to install${NC}"
    else
        print "${YELLOW}! Skipped asdf runtimes${NC}"
    fi
else
    print "${YELLOW}! No asdf/tool-versions.$BREW_LABEL in repo (or asdf missing), skipping${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Oh-My-Zsh (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 4: Oh-My-Zsh ==="
if [ -d ~/.oh-my-zsh ]; then
    print "${GREEN}✓ Oh-My-Zsh already installed${NC}"
else
    if ask_yes_no "Install Oh-My-Zsh?"; then
        print "${YELLOW}→ Installing Oh-My-Zsh...${NC}"
        if sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
            if [ -d ~/.oh-my-zsh ]; then
                print "${GREEN}✓ Oh-My-Zsh installed${NC}"
            else
                print "${RED}✗ Oh-My-Zsh installation failed (directory not created)${NC}"
            fi
        else
            print "${RED}✗ Oh-My-Zsh installation script failed${NC}"
        fi
    else
        print "${YELLOW}! Skipped Oh-My-Zsh${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Custom Plugins (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 5: Custom Plugins ==="
if [ ! -d ~/.oh-my-zsh ]; then
    print "${YELLOW}! Oh-My-Zsh not installed, skipping plugins${NC}"
elif [ ! -f plugins.list ]; then
    print "${RED}✗ plugins.list not found${NC}"
else
    print "${BLUE}Plugins: $(tr '\n' ' ' < plugins.list)${NC}"
    if ask_yes_no "Install custom plugins?"; then
        mkdir -p ~/.oh-my-zsh/custom/plugins

        # Plugin repository mapping
        declare -A PLUGIN_REPOS=(
            ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
            ["fast-syntax-highlighting"]="https://github.com/zdharma-continuum/fast-syntax-highlighting"
            ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab"
            ["alias-tips"]="https://github.com/djui/alias-tips"
            ["git-it-on"]="https://github.com/peterhurford/git-it-on.zsh"
            ["catimg"]="https://github.com/posva/catimg"
            ["auto-notify"]="https://github.com/MichaelAquilina/zsh-auto-notify"
            ["autoswitch_virtualenv"]="https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv"
            ["cd-ls"]="https://github.com/zshzoo/cd-ls"
            ["autoupdate"]="https://github.com/TamCore/autoupdate-oh-my-zsh-plugins"
            ["ls"]="https://github.com/zpm-zsh/ls"
        )

        while IFS= read -r plugin; do
            # Skip empty lines
            [[ -z "$plugin" ]] && continue

            plugin_dir=~/.oh-my-zsh/custom/plugins/$plugin

            if [ -d "$plugin_dir" ]; then
                print "${GREEN}✓ $plugin already installed${NC}"
            else
                if [ -n "${PLUGIN_REPOS[$plugin]}" ]; then
                    repo_url="${PLUGIN_REPOS[$plugin]}"

                    # Validate repository exists before cloning
                    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$repo_url" 2>/dev/null || echo "000")
                    if [ "$http_status" = "200" ]; then
                        print "${YELLOW}→ Installing $plugin...${NC}"
                        if git clone --quiet "$repo_url" "$plugin_dir" 2>/dev/null; then
                            print "${GREEN}✓ $plugin installed${NC}"
                        else
                            print "${RED}✗ $plugin failed to clone${NC}"
                        fi
                    else
                        print "${RED}✗ $plugin repository unavailable (HTTP $http_status): $repo_url${NC}"
                    fi
                else
                    print "${RED}✗ Unknown plugin: $plugin (no repo mapping)${NC}"
                fi
            fi
        done < plugins.list
    else
        print "${YELLOW}! Skipped custom plugins${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Homebrew command-not-found (informational only)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 6: Homebrew command-not-found ==="
print "${GREEN}✓ command-not-found is now built into Homebrew (no tap required)${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7: FZF Integration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 7: FZF Integration ==="
if [ -f ~/.fzf.zsh ]; then
    print "${GREEN}✓ FZF already configured${NC}"
else
    FZF_INSTALL_PATH="$(brew --prefix 2>/dev/null)/opt/fzf/install"
    if [ -f "$FZF_INSTALL_PATH" ]; then
        if ask_yes_no "Setup FZF shell integration?"; then
            print "${YELLOW}→ Setting up FZF integration...${NC}"
            if "$FZF_INSTALL_PATH" --key-bindings --completion --no-update-rc --no-bash --no-fish; then
                print "${GREEN}✓ FZF configured${NC}"
            else
                print "${RED}✗ FZF configuration failed${NC}"
            fi
        else
            print "${YELLOW}! Skipped FZF integration${NC}"
        fi
    else
        print "${YELLOW}! FZF not installed (install with: brew install fzf)${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 8: Configuration Files (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 8: Configuration Files ==="

# Zsh split label comes from the shared mapping (machine-label.sh).
ZSH_LABEL="$MACHINE_LABEL"

# Check what config files exist in repo
HAS_CONFIG=false
[ -f .zshrc.base ] && HAS_CONFIG=true
[ -f .zshrc.full ] && HAS_CONFIG=true
[ -f .zshrc ] && HAS_CONFIG=true

if [ "$HAS_CONFIG" = false ]; then
    print "${RED}✗ No .zshrc config found in repo${NC}"
else
    # Show what will be copied
    print "${BLUE}Available configs:${NC}"
    if [ -f .zshrc.base ]; then
        echo "  - .zshrc.base  (shared)"
        [ -n "$ZSH_LABEL" ] && [ -f .zshrc.$ZSH_LABEL ] && echo "  - .zshrc.$ZSH_LABEL   (this machine only)"
        echo "  - .zshrc.loader → ~/.zshrc"
    fi
    [ -f .zshrc.full ] && echo "  - .zshrc.full  (legacy monolith)"
    [ -f .p10k.zsh ] && echo "  - .p10k.zsh"

    if ask_yes_no "Copy configuration files? (existing files will be backed up)"; then
        # Backup existing configs
        BACKUP_DIR=""
        if [ -f ~/.zshrc ] || [ -f ~/.zshrc.base ] || [ -f ~/.p10k.zsh ]; then
            BACKUP_DIR=~/.zsh-config-backup-$(date +%Y%m%d-%H%M%S)
            print "${YELLOW}→ Backing up existing configs to $BACKUP_DIR${NC}"
            mkdir -p "$BACKUP_DIR"
            for f in .zshrc .zshrc.base .zshrc.c01 .zshrc.c02 .zshrc.personal .p10k.zsh; do
                [ -f ~/$f ] && cp ~/$f "$BACKUP_DIR/$f"
            done
            print "${GREEN}✓ Existing configs backed up${NC}"
        fi

        # Determine which config files to use
        if [ -f .zshrc.base ]; then
            # Split layout: shared base + this machine's file + loader.
            # The OTHER machine's .zshrc.<label> is deliberately never touched.
            print "${YELLOW}→ Installing split zsh config${NC}"
            cp .zshrc.base ~/.zshrc.base
            print "${GREEN}✓ Copied ~/.zshrc.base${NC}"

            if [ -n "$ZSH_LABEL" ] && [ -f .zshrc.$ZSH_LABEL ]; then
                cp .zshrc.$ZSH_LABEL ~/.zshrc.$ZSH_LABEL
                print "${GREEN}✓ Copied ~/.zshrc.$ZSH_LABEL (this machine)${NC}"
            elif [ -z "$ZSH_LABEL" ]; then
                print "${YELLOW}! Unknown machine — installed base only, no machine-specific file${NC}"
            else
                print "${YELLOW}! No .zshrc.$ZSH_LABEL in repo — base installed without machine file${NC}"
            fi

            # Install the loader as ~/.zshrc (prefer the repo copy; fall back to inline)
            if [ -f .zshrc.loader ]; then
                cp .zshrc.loader ~/.zshrc
            else
                # NOTE: duplicates the machine-label.sh mapping by design —
                # see that file's header (shell startup can't depend on the repo).
                cat > ~/.zshrc << 'EOF'
[[ -f ~/.zshrc.base ]] && source ~/.zshrc.base
case "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" in
  mrtysn-mbp-m2max)  [[ -f ~/.zshrc.c02 ]] && source ~/.zshrc.c02 ;;
esac
EOF
            fi
            print "${GREEN}✓ Installed ~/.zshrc loader${NC}"

        elif [ -f .zshrc.full ]; then
            # Legacy monolith
            print "${YELLOW}→ Copying .zshrc.full${NC}"
            cp .zshrc.full ~/.zshrc
            print "${GREEN}✓ Copied .zshrc${NC}"

        elif [ -f .zshrc ]; then
            # Legacy single file mode
            print "${YELLOW}→ Copying .zshrc${NC}"
            cp .zshrc ~/.zshrc
            print "${GREEN}✓ Copied .zshrc${NC}"
        fi

        # Copy .p10k.zsh
        if [ -f .p10k.zsh ]; then
            print "${YELLOW}→ Copying .p10k.zsh${NC}"
            cp .p10k.zsh ~/.p10k.zsh
            print "${GREEN}✓ Copied .p10k.zsh${NC}"
        fi
    else
        print "${YELLOW}! Skipped configuration files${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 9: iTerm2 Profiles & Settings (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 9: iTerm2 Profiles & Settings ==="
ITERM_DYNAMIC_PROFILES_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
PROFILES_DIR="$SCRIPT_DIR/iterm-profiles"

if [ ! -d "$PROFILES_DIR" ]; then
    print "${RED}✗ iterm-profiles directory not found${NC}"
elif ! command_exists defaults || ! defaults read com.googlecode.iterm2 &>/dev/null; then
    print "${YELLOW}! iTerm2 not installed or never opened, skipping profile setup${NC}"
else
    # List available profiles (exclude font-only for the full profiles option)
    FULL_PROFILES=("$PROFILES_DIR"/*.json(N))
    FULL_PROFILES=(${FULL_PROFILES:#*font-only.json})

    # Check what options are available
    HAS_FULL_PROFILES=false
    HAS_FONT_ONLY=false
    [[ ${#FULL_PROFILES[@]} -gt 0 ]] && HAS_FULL_PROFILES=true
    [[ -f "$PROFILES_DIR/font-only.json" ]] && HAS_FONT_ONLY=true

    if [[ "$HAS_FULL_PROFILES" = false && "$HAS_FONT_ONLY" = false ]]; then
        print "${YELLOW}! No iTerm2 profiles found in repo, skipping${NC}"
    else
        print "${BLUE}iTerm2 profile options:${NC}"
        if [[ "$HAS_FULL_PROFILES" = true ]]; then
            echo "  1) Full profiles - Import all profiles (colors, fonts, settings)"
        else
            echo "  1) [not available - no full profiles in repo]"
        fi
        if [[ "$HAS_FONT_ONLY" = true ]]; then
            echo "  2) Font only - Minimal profile that just sets FiraCode Nerd Font"
        else
            echo "  2) [not available - font-only.json missing]"
        fi
        echo "  3) Skip"
        echo ""
        read "iterm_choice?Select option [1/2/3]: "

        case "$iterm_choice" in
            1)
                if [[ "$HAS_FULL_PROFILES" = true ]]; then
                    print "${YELLOW}→ Installing full iTerm2 profiles...${NC}"
                    mkdir -p "$ITERM_DYNAMIC_PROFILES_DIR"
                    for profile in "${FULL_PROFILES[@]}"; do
                        filename=$(basename "$profile")
                        cp "$profile" "$ITERM_DYNAMIC_PROFILES_DIR/dev-config-$filename"
                        print "${GREEN}✓ Installed ${filename%.json}${NC}"
                    done
                    print "${BLUE}  Restart iTerm2 and select your preferred profile${NC}"
                else
                    print "${RED}✗ Full profiles not available${NC}"
                fi
                ;;
            2)
                if [[ "$HAS_FONT_ONLY" = true ]]; then
                    print "${YELLOW}→ Installing font-only profile...${NC}"
                    mkdir -p "$ITERM_DYNAMIC_PROFILES_DIR"
                    cp "$PROFILES_DIR/font-only.json" "$ITERM_DYNAMIC_PROFILES_DIR/dev-config-font-only.json"
                    print "${GREEN}✓ Font-only profile installed${NC}"
                    print "${BLUE}  Restart iTerm2 and select 'Dev Config (Font Only)' profile${NC}"
                else
                    print "${RED}✗ Font-only profile not available${NC}"
                fi
                ;;
            *)
                print "${YELLOW}! Skipped iTerm2 profiles${NC}"
                ;;
        esac
    fi

    # ── App-level settings ─────────────────────────────────────────────────────
    # Profiles only cover per-profile state. Theme, tab bar geometry, the Minimal
    # tuning knobs, global keymaps and pointer actions are top-level plist keys.
    ITERM_SETTINGS="$SCRIPT_DIR/iterm-settings.json"

    if [ ! -f "$ITERM_SETTINGS" ]; then
        print "${YELLOW}! iterm-settings.json not found, skipping app-level settings${NC}"
    elif ps -Ao comm= | grep -qE '(^|/)iTerm2$'; then
        # ps, not pgrep: pgrep can miss the process under some sandboxed shells,
        # and a false "not running" here means silently discarded settings.
        # iTerm rewrites its plist from memory on quit, so anything written now is
        # silently discarded. Refusing beats writing values that vanish.
        print "${RED}✗ iTerm2 is running — app-level settings NOT applied${NC}"
        print "${BLUE}  Quit iTerm2 completely, then re-run this script to apply them${NC}"
    else
        echo ""
        if ask_yes_no "Apply iTerm2 app-level settings (theme, tab bar, keymaps, pointer actions)?"; then
            print "${YELLOW}→ Applying iTerm2 app-level settings...${NC}"
            if python3 - "$ITERM_SETTINGS" <<'PYTHON_EOF'
import base64
import json
import os
import plistlib
import sys

settings_file = sys.argv[1]
plist_path = os.path.expanduser("~/Library/Preferences/com.googlecode.iterm2.plist")


def restore(obj):
    """Inverse of export.sh's convert_for_json."""
    if isinstance(obj, dict):
        if obj.get("_type") == "data" and "value" in obj:
            return base64.b64decode(obj["value"])
        return {k: restore(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [restore(item) for item in obj]
    return obj


try:
    with open(settings_file) as f:
        settings = restore(json.load(f).get("settings", {}))
except Exception as e:
    print(f"  Could not read {settings_file}: {e}", file=sys.stderr)
    sys.exit(1)

if not settings:
    print("  No settings found in the export, nothing to apply")
    sys.exit(0)

# Merge, don't replace: keys absent from the export (profiles, machine-local state)
# must survive untouched.
try:
    with open(plist_path, "rb") as f:
        plist = plistlib.load(f)
except FileNotFoundError:
    plist = {}
except Exception as e:
    print(f"  Could not read existing plist: {e}", file=sys.stderr)
    sys.exit(1)

changed = [k for k, v in settings.items() if plist.get(k) != v]
plist.update(settings)

try:
    tmp = plist_path + ".tmp"
    with open(tmp, "wb") as f:
        plistlib.dump(plist, f)
    os.replace(tmp, plist_path)
except Exception as e:
    print(f"  Failed to write plist: {e}", file=sys.stderr)
    sys.exit(1)

print(f"  Applied {len(settings)} settings ({len(changed)} changed)")
for k in changed[:10]:
    print(f"    - {k}")
if len(changed) > 10:
    print(f"    ... and {len(changed) - 10} more")
PYTHON_EOF
            then
                # cfprefsd caches the domain; without this it can rewrite the old
                # values over the ones just written.
                killall cfprefsd 2>/dev/null || true
                print "${GREEN}✓ iTerm2 app-level settings applied${NC}"
                print "${BLUE}  Launch iTerm2 to see them${NC}"
            else
                print "${RED}✗ Failed to apply iTerm2 app-level settings${NC}"
            fi
        else
            print "${YELLOW}! Skipped iTerm2 app-level settings${NC}"
        fi
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 10: Default Shell (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 10: Default Shell ==="
if [ "$SHELL" = "/bin/zsh" ]; then
    print "${GREEN}✓ zsh is already the default shell${NC}"
else
    if ask_yes_no "Set zsh as default shell? (requires password)"; then
        print "${YELLOW}→ Setting zsh as default shell...${NC}"
        if chsh -s /bin/zsh; then
            print "${GREEN}✓ zsh set as default shell${NC}"
        else
            print "${RED}✗ Failed to set default shell (you can run 'chsh -s /bin/zsh' manually)${NC}"
        fi
    else
        print "${YELLOW}! Skipped setting default shell${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 11: Tmux Configuration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 11: Tmux Configuration ==="

if ! command_exists tmux; then
    print "${YELLOW}! tmux not installed, skipping (install with: brew install tmux)${NC}"
else
    # Machine label from the shared mapping (machine-label.sh).
    TMUX_CONF=""

    if [[ -n "$MACHINE_LABEL" ]]; then
        TMUX_CONF="tmux/$MACHINE_LABEL.conf"
    else
        print "${BLUE}Unknown machine (see machine-label.sh)${NC}"
        echo "  1) C01 — Office Mac (Ctrl-a prefix, blue status bar)"
        echo "  2) C02 — Home Mac (Ctrl-s prefix, green status bar)"
        echo "  3) Skip"
        echo ""
        read "tmux_choice?Select machine [1/2/3]: "

        case "$tmux_choice" in
            1)
                TMUX_CONF="tmux/c01.conf"
                MACHINE_NAME="C01 (Office)"
                ;;
            2)
                TMUX_CONF="tmux/c02.conf"
                MACHINE_NAME="C02 (Home)"
                ;;
            *)
                print "${YELLOW}! Skipped tmux configuration${NC}"
                ;;
        esac
    fi

    if [[ -n "$TMUX_CONF" ]]; then
        print "${BLUE}Detected: $MACHINE_NAME${NC}"

        if ask_yes_no "Setup tmux configuration?"; then
            # Symlink tmux config
            TMUX_CONF_ABS="$SCRIPT_DIR/$TMUX_CONF"
            if [ -L ~/.tmux.conf ] && [ "$(readlink ~/.tmux.conf)" = "$TMUX_CONF_ABS" ]; then
                print "${GREEN}✓ ~/.tmux.conf already symlinked to $TMUX_CONF${NC}"
            else
                if [ -f ~/.tmux.conf ]; then
                    print "${YELLOW}→ Backing up existing ~/.tmux.conf${NC}"
                    cp ~/.tmux.conf ~/.tmux.conf.backup-$(date +%Y%m%d-%H%M%S)
                fi
                ln -sf "$TMUX_CONF_ABS" ~/.tmux.conf
                print "${GREEN}✓ Symlinked ~/.tmux.conf → $TMUX_CONF${NC}"
            fi

            # Copy bin scripts. The list is derived from what the repo tracks, so a
            # new tool needs no edit here — matching export.sh.
            mkdir -p ~/bin
            for tool in "$SCRIPT_DIR"/bin/*(N:t); do
                cp "$SCRIPT_DIR/bin/$tool" ~/bin/$tool
                chmod +x ~/bin/$tool
                print "${GREEN}✓ Copied $tool to ~/bin/${NC}"
            done

            # Copy sessions config example (only if not present)
            if [ ! -f ~/.tmux-sessions.conf ]; then
                cp "$SCRIPT_DIR/tmux/tmux-sessions.conf.example" ~/.tmux-sessions.conf
                print "${GREEN}✓ Created ~/.tmux-sessions.conf from example${NC}"
            else
                print "${GREEN}✓ ~/.tmux-sessions.conf already exists (kept)${NC}"
            fi

            # Append SSH config snippet (guarded by marker comment)
            SSH_MARKER="# --- Tmux Cross-SSH ---"
            if [ -f ~/.ssh/config ] && grep -qF "$SSH_MARKER" ~/.ssh/config; then
                print "${GREEN}✓ SSH config already contains tmux cross-SSH entries${NC}"
            else
                if ask_yes_no "Append tmux cross-SSH entries to ~/.ssh/config?"; then
                    mkdir -p ~/.ssh
                    chmod 700 ~/.ssh
                    echo "" >> ~/.ssh/config
                    cat "$SCRIPT_DIR/ssh/config.snippet" >> ~/.ssh/config
                    chmod 600 ~/.ssh/config
                    print "${GREEN}✓ Appended cross-SSH entries to ~/.ssh/config${NC}"
                    print "${YELLOW}  Note: Update C1-PLACEHOLDER and C2-PLACEHOLDER with actual IPs${NC}"
                else
                    print "${YELLOW}! Skipped SSH config${NC}"
                fi
            fi
        else
            print "${YELLOW}! Skipped tmux configuration${NC}"
        fi
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 12: Claude Code Settings (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 12: Claude Code Settings ==="

# "<repo subdir>:<target config dir>"
AGENTS_DIR="agents"
CLAUDE_PAIRS=(
    "$AGENTS_DIR/claude:${CLAUDE_DIR}"
    "$AGENTS_DIR/claude-personal:${CLAUDE_PERSONAL_DIR}"
)

# Collect the pairs we actually have settings for
AVAILABLE_CLAUDE=()
for pair in "${CLAUDE_PAIRS[@]}"; do
    [ -f "${pair%%:*}/settings.json" ] && AVAILABLE_CLAUDE+=("$pair")
done

if [[ ${#AVAILABLE_CLAUDE[@]} -eq 0 ]]; then
    print "${YELLOW}! No Claude settings found in repo, skipping${NC}"
else
    # Asked per directory, not once for all: a config dir this machine does not
    # have is one it does not use, so creating it defaults to no. Machines differ
    # in how many Claude configs they run, and an absent dir is that answer.
    for pair in "${AVAILABLE_CLAUDE[@]}"; do
        src="${pair%%:*}/settings.json"
        target_dir="${pair##*:}"
        target="$target_dir/settings.json"
        shown="${target_dir/#$HOME/~}"

        if [ -d "$target_dir" ]; then
            claude_prompt="Update $shown/settings.json from $src? (backed up first)"
            claude_default="y"
        else
            claude_prompt="$shown does not exist — create it and copy $src there?"
            claude_default="n"
        fi

        if ! ask_yes_no "$claude_prompt" "$claude_default"; then
            print "${YELLOW}! Skipped $shown${NC}"
            continue
        fi

        mkdir -p "$target_dir"
        if [ -f "$target" ]; then
            cp "$target" "$target.backup-$(date +%Y%m%d-%H%M%S)"
            print "${YELLOW}→ Backed up existing $target${NC}"
        fi
        cp "$src" "$target"
        print "${GREEN}✓ Copied $src → $target${NC}"
    done
fi

# The guard hooks in settings.json resolve their checkout from a machine-local
# paths.local.sh and exit 2 when they cannot, so a config dir without that file
# refuses every Bash tool call.
if [ -f "${CLAUDE_DIR}/settings.json" ] && grep -q 'AGENTS_SHARED_DIR' "${CLAUDE_DIR}/settings.json"; then
    if ! CLAUDE_DIR="${CLAUDE_DIR}" "$SCRIPT_DIR/agents/claude/write-paths-local.sh"; then
        print "${YELLOW}! No paths.local.sh written — Claude Code will refuse Bash tool calls until one exists${NC}"
        print "${YELLOW}  Fix with: agents/claude/write-paths-local.sh --path <agents-shared checkout>${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 13: Window & Keyboard Configs (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 13: Window & Keyboard Configs ==="

HAS_WK=false
[ -f .phoenix.js ] && HAS_WK=true
[ -f karabiner/karabiner.json ] && HAS_WK=true

if [ "$HAS_WK" = false ]; then
    print "${YELLOW}! No Phoenix/Karabiner configs in repo, skipping${NC}"
else
    print "${BLUE}Available configs:${NC}"
    [ -f .phoenix.js ] && echo "  - .phoenix.js → ~/.phoenix.js (Phoenix window manager)"
    [ -f karabiner/karabiner.json ] && echo "  - karabiner/karabiner.json → ~/.config/karabiner/karabiner.json (Karabiner keymaps)"

    if ask_yes_no "Copy window & keyboard configs? (existing files will be backed up)"; then
        if [ -f .phoenix.js ]; then
            if [ -f ~/.phoenix.js ]; then
                cp ~/.phoenix.js ~/.phoenix.js.backup-$(date +%Y%m%d-%H%M%S)
                print "${YELLOW}→ Backed up existing ~/.phoenix.js${NC}"
            fi
            cp .phoenix.js ~/.phoenix.js
            print "${GREEN}✓ Copied ~/.phoenix.js${NC}"
        fi

        if [ -f karabiner/karabiner.json ]; then
            mkdir -p ~/.config/karabiner
            if [ -f ~/.config/karabiner/karabiner.json ]; then
                cp ~/.config/karabiner/karabiner.json ~/.config/karabiner/karabiner.json.backup-$(date +%Y%m%d-%H%M%S)
                print "${YELLOW}→ Backed up existing ~/.config/karabiner/karabiner.json${NC}"
            fi
            cp karabiner/karabiner.json ~/.config/karabiner/karabiner.json
            print "${GREEN}✓ Copied ~/.config/karabiner/karabiner.json${NC}"
            print "${BLUE}  Restart Karabiner-Elements to apply${NC}"
        fi
    else
        print "${YELLOW}! Skipped window & keyboard configs${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 14: lazygit + repo-tabs Configuration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 14: lazygit + repo-tabs Configuration ==="

LAZYGIT_DIR="$HOME/Library/Application Support/lazygit"
HAS_LG=false
[ -f lazygit/config.yml ] && HAS_LG=true
[ -d repo-tabs ] && HAS_LG=true

if [ "$HAS_LG" = false ]; then
    print "${YELLOW}! No lazygit/repo-tabs configs in repo, skipping${NC}"
else
    print "${BLUE}Available configs:${NC}"
    [ -f lazygit/config.yml ] && echo "  - lazygit/config.yml + themes → $LAZYGIT_DIR/"
    [ -d repo-tabs ] && echo "  - repo-tabs/theme-* → ~/.config/repo-tabs/ (group themes for repo-tabs lazy)"

    if ask_yes_no "Copy lazygit & repo-tabs configs? (existing files will be backed up)"; then
        if [ -f lazygit/config.yml ]; then
            mkdir -p "$LAZYGIT_DIR/themes"
            if [ -f "$LAZYGIT_DIR/config.yml" ]; then
                cp "$LAZYGIT_DIR/config.yml" "$LAZYGIT_DIR/config.yml.backup-$(date +%Y%m%d-%H%M%S)"
                print "${YELLOW}→ Backed up existing lazygit config.yml${NC}"
            fi
            cp lazygit/config.yml "$LAZYGIT_DIR/config.yml"
            for t in lazygit/themes/*.yml(N); do
                cp "$t" "$LAZYGIT_DIR/themes/${t:t}"
            done
            print "${GREEN}✓ Copied lazygit config + themes${NC}"
        fi
        if [ -d repo-tabs ]; then
            mkdir -p ~/.config/repo-tabs
            for g in repo-tabs/theme-*(N); do
                cp "$g" ~/.config/repo-tabs/"${g:t}"
            done
            print "${GREEN}✓ Copied repo-tabs group themes${NC}"
            print "${BLUE}  repos.txt is machine-local — seed it with 'repo-tabs focus' on first run${NC}"
        fi
    else
        print "${YELLOW}! Skipped lazygit & repo-tabs configs${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Complete
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Import Complete ==="
echo ""
print "${GREEN}✓ Setup finished${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Powerlevel10k config wizard will run on first start (if not configured)"
echo "  3. Machine-specific aliases live in ~/.zshrc.c01 (Office) / ~/.zshrc.c02 (Home); shared config in ~/.zshrc.base"
echo ""
if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    echo "Your old configs are backed up at: $BACKUP_DIR"
    echo ""
fi
